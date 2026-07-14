# Issue 06 — Ch06: High CPU Usage (Book 2) — All 3 Exercises

## Chapter
Ch06 — High CPU Usage: Performance Issue from Polling Loops

---

## Theory Background

```
Kernel thread with no sleep:
  while (!done) {
      check_hardware();  ← runs millions of times per second
  }
  → CPU at 100% — system unresponsive on that core

With sleep:
  while (!kthread_should_stop()) {
      check_hardware();
      msleep(10);   ← yield CPU, 100Hz polling rate
  }
  → CPU at 0.1% — fully responsive

Best: interrupt-driven
  No polling thread at all.
  Hardware notifies via IRQ → handler runs only when needed.
  CPU at 0% when idle.

Key Rule:
  Never poll hardware in a tight loop without sleep.
  Prefer interrupt-driven design over polling.
  If polling required: msleep() for ms delays, usleep_range() for us.
  mdelay() is CPU busy-wait — NEVER use in a thread.
```

---

## Ex1 — BUG: Tight Polling Loop Pins CPU at 100%

### Bug Code

```c
static int my_poll_thread(void *data)
{
    while (!kthread_should_stop()) {
        u32 status = readl(dev->base + STATUS_REG);
        if (status & DATA_READY)
            process_data(dev);
        /* NO SLEEP — CPU burns at 100% */
    }
    return 0;
}
```

### Symptom Log

```
# In QEMU — run top:
PID  USER  %CPU  COMMAND
1234 root  99.9  my_poll_thread

# dmesg:
[  225.101] HIGH_CPU [BUG]: poll thread started — no sleep!
[  225.102] HIGH_CPU [BUG]: CPU will run at 100%
```

### Verify

```bash
insmod high_cpu_driver.ko
top                              # see 99% on poll thread
cat /proc/1234/status | grep voluntary  # context switches = 0
```

---

## Ex2 — FIX: msleep() Yields CPU Between Polls

### Fix Code

```c
static int fixed_poll_thread(void *data)
{
    while (!kthread_should_stop()) {
        u32 status = readl(dev->base + STATUS_REG);
        if (status & DATA_READY)
            process_data(dev);
        msleep(10);   /* yield CPU — 100Hz poll rate, 0.1% CPU */
    }
    return 0;
}
```

### Fixed Output

```
# top after fix:
PID  USER  %CPU  COMMAND
1234 root   0.1  fixed_poll_thread   ← from 99.9% to 0.1%
```

---

## Ex3 — BEST: Interrupt-Driven (Zero CPU When Idle)

### IRQ-Driven Pattern

```c
static irqreturn_t my_handler(int irq, void *dev_id)
{
    u32 status = readl(dev->base + STATUS_REG);
    if (status & DATA_READY)
        process_data(dev);
    writel(status, dev->base + STATUS_REG);  /* clear interrupt */
    return IRQ_HANDLED;
}

static int my_probe(struct platform_device *pdev)
{
    int irq = platform_get_irq(pdev, 0);
    return devm_request_irq(&pdev->dev, irq, my_handler,
                             IRQF_TRIGGER_RISING, "my_irq", pdev);
    /* No kernel thread — hardware notifies us */
    /* CPU usage: 0% idle, brief spike per interrupt */
}
```

---

## Reproduce Steps

```bash
cd ~/30days_workWith_BSP/my_projects/book2/ch06_high_cpu
make clean && make
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp high_cpu_driver.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — BUG
insmod /home/root/high_cpu_driver.ko
top   # observe 99% CPU on poll thread
dmesg | grep HIGH_CPU

# FIXED
rmmod high_cpu_driver
insmod /home/root/high_cpu_driver_fixed.ko
top   # observe near 0% CPU
rmmod high_cpu_driver_fixed
```

---

## Key Takeaways

1. Tight polling loop → 100% CPU → system unresponsive
2. `msleep(10)` → 100Hz polling → 0.1% CPU — for polling that cannot use IRQ
3. Interrupt-driven = best — CPU at 0% idle, only wakes on event
4. `mdelay()` = CPU busy-wait — NEVER use in a kernel thread
5. `usleep_range(min, max)` for sub-millisecond delays in threads
6. `perf top` or `top` identifies high-CPU kernel threads immediately

---
---

# Issue 07 — Ch07: Softirq Misuse (Book 2) — All 3 Exercises

## Chapter
Ch07 — Softirq Misuse: System Instability from Illegal Context

---

## Theory Background

### Linux Interrupt Deferral Hierarchy

```
Hardware IRQ (top half)
  → runs with IRQs disabled
  → MUST be extremely fast (< 1us)
  → acknowledge hardware, schedule bottom half only

Softirq / Tasklet (bottom half)
  → IRQs enabled, cannot sleep
  → MUST NOT: mutex_lock, msleep, kmalloc(GFP_KERNEL)
  → CAN: spin_lock, kfree, kzalloc(GFP_ATOMIC), readl/writel
  → for quick processing only (< 100us)

Workqueue (deferred work)
  → runs in kernel thread context
  → CAN sleep, CAN use mutex, CAN do I/O
  → use for anything slow or blocking

Key Rule:
  Any slow, blocking, or sleeping work → WORKQUEUE.
  Tasklet/softirq → queue work, return immediately.
  CONFIG_DEBUG_ATOMIC_SLEEP=y detects illegal sleeps instantly.
```

---

## Ex1 — BUG: Sleep in Tasklet Context

### Bug Code

```c
static void my_tasklet_handler(unsigned long data)
{
    mutex_lock(&my_mutex);    /* ILLEGAL: may sleep */
    msleep(5);                /* ILLEGAL: sleep in atomic context */
    kmalloc(100, GFP_KERNEL); /* ILLEGAL: GFP_KERNEL may sleep */
    mutex_unlock(&my_mutex);
}
```

### Symptom Log

```
[  2.34] BUG: sleeping function called from invalid context
[  2.34] in_atomic(): 1, irqs_disabled(): 0
[  2.34] Call Trace:
[  2.34]  __might_sleep+0x...
[  2.34]  mutex_lock+0x...
[  2.34]  my_tasklet_handler+0x...
```

---

## Ex2 — FIX: Tasklet Queues, Workqueue Executes

### Fix Code

```c
static DECLARE_WORK(my_work, my_work_handler);

static void my_tasklet_handler(unsigned long data)
{
    queue_work(system_wq, &my_work);  /* returns immediately — no sleep */
}

static void my_work_handler(struct work_struct *work)
{
    /* Workqueue context: CAN sleep, CAN use mutex, CAN do I/O */
    mutex_lock(&my_mutex);
    msleep(5);             /* safe here */
    do_heavy_work();
    mutex_unlock(&my_mutex);
}
```

---

## Ex3 — DETECT: CONFIG_DEBUG_ATOMIC_SLEEP

```bash
bitbake linux-yocto -c menuconfig
# Kernel hacking →
#   [*] Sleep inside atomic section checking (CONFIG_DEBUG_ATOMIC_SLEEP=y)

# Rebuild + test:
insmod softirq_driver.ko
dmesg | grep "sleeping function called"
```

---

## Reproduce Steps

```bash
cd ~/30days_workWith_BSP/my_projects/book2/ch07_softirq
make clean && make
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp softirq_driver.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — BUG
insmod /home/root/softirq_driver.ko
dmesg | grep "BUG: sleeping"

# FIXED
rmmod softirq_driver
insmod /home/root/softirq_driver_fixed.ko
dmesg | grep SOFTIRQ
rmmod softirq_driver_fixed
```

---

## Key Takeaways

1. Tasklets/softirqs CANNOT sleep — use workqueue for any blocking work
2. `mutex_lock`, `msleep`, `kmalloc(GFP_KERNEL)` all illegal in softirq context
3. Pattern: tasklet queues work → workqueue handler executes it
4. `GFP_ATOMIC` = allocate without sleeping — safe in softirq/IRQ context
5. `CONFIG_DEBUG_ATOMIC_SLEEP=y` catches illegal sleeps immediately
6. `queue_work(system_wq, &work)` is the standard deferred work call

---
---

# Issue 08 — Ch08: Spinlock Misuse (Book 2) — All 3 Exercises

## Chapter
Ch08 — Spinlock Misuse: System Hang from Missing Unlock

---

## Theory Background

### Spinlock Rules

```
spin_lock() → disables preemption on this CPU
            → if already locked: spins (burns CPU) until released
            → NEVER sleep while holding a spinlock

ILLEGAL while holding a spinlock:
  sleep / msleep / wait_event  ← can never wake up
  mutex_lock                   ← may sleep internally
  kmalloc(GFP_KERNEL)          ← may sleep on low memory
  copy_from/to_user            ← may page fault (sleep)

ALLOWED while holding a spinlock:
  kfree, kzalloc(GFP_ATOMIC)
  atomic operations
  readl/writel (register access)
  spin_lock on DIFFERENT lock (careful of ordering)

Key Rule:
  Every spin_lock() MUST have a matching spin_unlock()
  on EVERY possible exit path including ALL error paths.
  Use goto pattern to guarantee single unlock point.
```

---

## Ex1 — BUG: Missing spin_unlock on Error Path

### Bug Code

```c
static ssize_t my_write(struct file *f, ...)
{
    spin_lock(&dev->lock);

    if (dev->busy) {
        pr_err("device busy\n");
        return -EBUSY;          /* RETURNS WITHOUT UNLOCKING! */
    }

    dev->busy = 1;
    do_work(dev);
    spin_unlock(&dev->lock);
    return len;
}
```

### Symptom Log

```
# First write triggers busy path:
[  5.1] SPINLOCK [BUG]: device busy — returning WITHOUT unlock

# Second write hangs forever:
[  27.1] BUG: soft lockup - CPU#0 stuck for 22s!
[  27.1] Call Trace:
[  27.1]  _raw_spin_lock+0x...
[  27.1]  my_write+0x...     ← stuck waiting for lock never released
```

---

## Ex2 — FIX: goto Pattern Guarantees Single Unlock

### Fix Code

```c
static ssize_t my_write(struct file *f, ...)
{
    int ret = 0;

    spin_lock(&dev->lock);

    if (dev->busy) { ret = -EBUSY;  goto out; }   /* safe exit */
    if (len > BUF)  { ret = -EINVAL; goto out; }   /* safe exit */

    dev->busy = 1;
    do_work(dev);
    ret = len;

out:
    spin_unlock(&dev->lock);    /* ALWAYS reached — every path */
    return ret;
}
```

---

## Ex3 — IRQ-Safe: spin_lock_irqsave

```c
/* When IRQ handler also takes the same lock: */
unsigned long flags;

spin_lock_irqsave(&dev->lock, flags);    /* disables local IRQs */
/* critical section */
spin_unlock_irqrestore(&dev->lock, flags); /* restores IRQ state */

/* Without irqsave: IRQ handler tries to take same lock → CPU deadlock */
```

---

## Reproduce Steps

```bash
cd ~/30days_workWith_BSP/my_projects/book2/ch08_spinlock
make clean && make
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp spinlock_driver.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — BUG
insmod /home/root/spinlock_driver.ko
echo "trigger" > /dev/spinlock_dev   # triggers busy path (no unlock)
echo "trigger" > /dev/spinlock_dev   # hangs here
dmesg | grep "soft lockup"

# Reboot, test FIXED
insmod /home/root/spinlock_driver_fixed.ko
echo "trigger" > /dev/spinlock_dev   # returns error, lock released
echo "trigger" > /dev/spinlock_dev   # works — no hang
rmmod spinlock_driver_fixed
```

---

## Key Takeaways

1. Every `spin_lock()` needs matching `spin_unlock()` on ALL exit paths
2. goto pattern = single unlock point — safest approach for multi-path functions
3. `spin_lock_irqsave()` when IRQ handlers take the same lock
4. `CONFIG_DEBUG_SPINLOCK=y` detects double-lock and unlock-without-lock
5. Sleeping while holding spinlock = system hang — no recovery possible
6. `CONFIG_PROVE_LOCKING=y` (lockdep) tracks all spinlock state across paths

---
---

# Issue 09 — Ch09: Advanced Boot Optimization (Book 2) — All 4 Exercises

## Chapter
Ch09 — Boot Time Optimization: async_schedule, initcall_debug, ktime

---

## Theory Background

```
Boot timeline:
  U-Boot → kernel decompress → driver probe() calls → userspace

probe() calls are SEQUENTIAL by default.
One slow probe blocks all drivers behind it.

msleep(5000) in probe() = 5 extra seconds EVERY boot.

Tools:
  initcall_debug  → shows each driver's probe time at boot
  ktime_get()     → measure probe() duration in code
  async_schedule  → run slow init in background thread

Targets:
  < 100 us  → excellent (pure register setup)
  < 1 ms    → acceptable (simple hardware)
  > 10 ms   → use delayed_work or async_schedule
  > 100 ms  → always async
  > 1000 ms → critical bug, fix immediately
```

---

## Ex1 — MEASURE: ktime_get() in probe()

```c
static int my_probe(struct platform_device *pdev)
{
    ktime_t t_start = ktime_get();

    /* hardware init */
    hardware_reset();
    msleep(50);
    hardware_configure();

    ktime_t t_end = ktime_get();
    pr_info("BOOT [TIMING]: probe took %lld us\n",
            ktime_to_us(ktime_sub(t_end, t_start)));
    return 0;
}
```

---

## Ex2 — FIND: initcall_debug in Bootargs

```bash
# Add to QEMU bootargs in boot_qemu.sh:
# -append "console=ttyAMA0 root=/dev/vda rw initcall_debug printk.time=1"

# Expected dmesg output:
# calling  my_driver_init+0x0/0x1000
# initcall my_driver_init+0x0/0x1000 returned 0 after 5021456 usecs
#                                                        ↑ 5 seconds!

# Find all slow probes:
dmesg | grep "returned.*usecs" | sort -t' ' -k7 -rn | head -10
```

---

## Ex3 — FIX: delayed_work Instead of msleep in probe()

```c
struct my_priv {
    struct delayed_work init_work;
};

static void my_init_work(struct work_struct *work)
{
    struct my_priv *priv = container_of(
        to_delayed_work(work), struct my_priv, init_work);
    msleep(5000);        /* runs in workqueue — not blocking boot */
    hardware_configure(priv);
    pr_info("BOOT [FIXED]: async init complete\n");
}

static int my_probe(struct platform_device *pdev)
{
    struct my_priv *priv = devm_kzalloc(&pdev->dev,
                                         sizeof(*priv), GFP_KERNEL);
    INIT_DELAYED_WORK(&priv->init_work, my_init_work);
    schedule_delayed_work(&priv->init_work, msecs_to_jiffies(100));
    return 0;   /* returns immediately — boot continues */
}

static int my_remove(struct platform_device *pdev)
{
    struct my_priv *priv = platform_get_drvdata(pdev);
    cancel_delayed_work_sync(&priv->init_work);  /* wait before cleanup */
    return 0;
}
```

---

## Ex4 — ADVANCED: async_schedule

```c
#include <linux/async.h>

static void my_async_init(void *data, async_cookie_t cookie)
{
    msleep(5000);   /* runs in background — does not block boot */
    pr_info("BOOT [ASYNC]: init complete\n");
}

static int my_probe(struct platform_device *pdev)
{
    async_schedule(my_async_init, pdev);
    return 0;   /* returns in microseconds */
}
```

---

## Reproduce Steps

```bash
cd ~/30days_workWith_BSP/my_projects/book2/ch09_boot_opt
make clean && make
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp *.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — slow probe
date && insmod /home/root/boot_delay_driver.ko && date
dmesg | grep "BOOT\|probe took"

# FIXED probe
date && insmod /home/root/boot_delay_fixed.ko && date
sleep 6
dmesg | grep "BOOT\|async\|delayed"
rmmod boot_delay_fixed
```

---

## Key Takeaways

1. `initcall_debug` in bootargs shows every driver's probe time
2. `ktime_get()` measures probe duration — add to all production drivers
3. `delayed_work` = probe returns immediately, init runs asynchronously
4. `cancel_delayed_work_sync()` in remove() — MUST wait for work to finish
5. `async_schedule()` = most aggressive — for truly independent hardware init
6. Check hardware datasheet — often 5000ms was copied from old reference code needing only 50ms
7. `mdelay()` = CPU busy-wait — never use in probe() or threads

---
---

# Issue 10 — Ch10: Thread Synchronization (Book 2) — All 4 Exercises

## Chapter
Ch10 — Multi-thread Synchronization: Protecting Compound Shared State

---

## Theory Background

### Why Protecting Individual Fields Is Not Enough

```
struct shared {
    char buf[1024];   /* field 1 */
    int  len;         /* field 2 */
    bool ready;       /* field 3 */
};

Producer writes:
  data.len = 512;        /* step 1 */
  memcpy(data.buf, ...); /* step 2 */
  data.ready = true;     /* step 3 */

Consumer reads:
  if (data.ready)         /* sees: true (step 3 done) */
      use(data.buf, data.len);  /* may see OLD buf and len! */

Consumer saw ready=true but observed partial state.
All three fields must be updated and read as an ATOMIC UNIT.

Key Rule:
  Protect ALL fields of a shared struct with the SAME lock.
  Both writer AND reader must hold the lock.
  A read is not safe just because it is "read-only".
```

---

## Ex1 — BUG: No Mutex on Compound Update

### Bug Code

```c
struct shared_data { char buf[1024]; int len; bool ready; };
static struct shared_data data;

void producer(void)
{
    memcpy(data.buf, new_data, len);  /* step 1 */
    data.len = len;                    /* step 2 */
    data.ready = true;                 /* step 3 — consumer may wake here */
}

void consumer(void)
{
    if (data.ready)                        /* true */
        process(data.buf, data.len);       /* BUG: may see old buf/len */
}
```

### Symptom Log

```
[  3.4] SYNC [consumer]: processed 0 bytes   ← expected 512
[  3.5] SYNC [consumer]: processed 512 bytes ← sometimes correct
# No crash — just wrong intermittent behavior
```

---

## Ex2 — FIX: mutex Protects Compound State as Atomic Unit

### Fix Code

```c
static DEFINE_MUTEX(data_mutex);

void producer(void)
{
    mutex_lock(&data_mutex);
    memcpy(data.buf, new_data, len);  /* all updates */
    data.len = len;                    /* under same */
    data.ready = true;                 /* lock */
    mutex_unlock(&data_mutex);
}

void consumer(void)
{
    mutex_lock(&data_mutex);
    if (data.ready)
        process(data.buf, data.len);  /* atomic check-and-use */
    mutex_unlock(&data_mutex);
}
/* Consumer guaranteed: sees ALL old state or ALL new state — never mixed */
```

---

## Ex3 — PATTERN: Reader/Writer Lock for Performance

```c
static DEFINE_RWLOCK(data_rwlock);

void producer(void)
{
    write_lock(&data_rwlock);   /* exclusive — all readers blocked */
    update_data();
    write_unlock(&data_rwlock);
}

void consumer(void)
{
    read_lock(&data_rwlock);    /* shared — other readers proceed */
    use_data();
    read_unlock(&data_rwlock);
}
/* Use when reads are frequent and writes are rare */
```

---

## Ex4 — PATTERN: completion for Event Signaling

```c
static DECLARE_COMPLETION(data_ready);

void producer(void)
{
    prepare_data();
    complete(&data_ready);      /* signal: data is ready */
}

void consumer(void)
{
    wait_for_completion(&data_ready);  /* blocks until producer calls complete() */
    use_data();                         /* guaranteed: full state visible */
}

/* completion is designed exactly for event signaling:
   - no race between check and wait
   - more expressive than flag + lock
   - built-in memory ordering guarantees */
```

---

## Reproduce Steps

```bash
cd ~/30days_workWith_BSP/my_projects/book2/ch10_thread_sync
make clean && make
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp *.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — BUG
insmod /home/root/thread_sync_driver.ko
dmesg | grep SYNC
# Observe inconsistent consumer output

# FIXED
rmmod thread_sync_driver
insmod /home/root/thread_sync_fixed.ko
dmesg | grep SYNC
# Consumer always sees complete state
rmmod thread_sync_fixed
```

---

## Book 2 Complete Quick Reference

| Ch | Issue | Symptom | Root Cause | Key Fix | Verify |
|----|-------|---------|-----------|---------|--------|
| 01 | Race Condition | Wrong counter | No lock on shared var | atomic_t / spinlock | correct count |
| 02 | Deadlock | System hang | Circular lock order | Consistent order | no soft lockup |
| 03 | Memory Corruption | Random crash | Buffer overflow | bounds check + KASAN | KASAN silent |
| 04 | DMA Issue | Wrong data | Virtual not physical | dma_map_single() | data matches |
| 05 | Panic Analysis | Kernel panic | NULL pointer | addr2line + null check | no panic |
| 06 | High CPU | 100% CPU | Busy-poll loop | msleep / IRQ-driven | CPU near 0% |
| 07 | Softirq Misuse | Sleep in atomic | Mutex in tasklet | Move to workqueue | no BUG: sleep |
| 08 | Spinlock Hang | System hang | Missing unlock | goto + unlock | no soft lockup |
| 09 | Boot Optimization | Slow boot | msleep in probe() | delayed_work | fast probe |
| 10 | Thread Sync | Wrong shared state | No mutex on compound | mutex + completion | KCSAN silent |

---

## Key Takeaways (Ch10)

1. Protect ALL fields of shared struct with SAME lock — not individually
2. Both writer AND reader must hold the lock — reads are not inherently safe
3. `completion` = best for producer/consumer event signaling — no race possible
4. `rwlock` = performance optimization when reads >> writes
5. `CONFIG_KCSAN=y` detects data races automatically — use in dev kernel
6. Memory ordering: lock acquisition provides implicit barriers on both sides
7. Compound state must be seen as ALL-old or ALL-new — never partial
