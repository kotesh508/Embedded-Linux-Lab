# Issue 10 — Ch10: Boot Delay / Probe Timing — All 4 Exercises

## Chapter
Ch10 — Boot Delay, Probe Timing, deferred probe, initcall_debug

---

## Theory Background

### Why probe() Must Return Fast

```
Boot sequence:
  kernel init → platform bus scan → driver_attach()
                                      └── probe() called

probe() runs in:
  - kernel init context (early boot): synchronous, blocks everything
  - insmod context: blocks insmod syscall

If probe() blocks with msleep(3000):
  - Boot takes 3+ extra seconds
  - Other drivers waiting behind this one are also delayed
  - watchdog may fire if blocking too long
  - User sees slow boot, delayed userspace

Rule: probe() must return in < 1ms for simple drivers
      Use workqueue/delayed_work for any hardware wait > 1ms
```

### Three Probe Timing Patterns

```
Pattern 1 — BAD: blocking sleep
  probe() {
      msleep(3000);   ← blocks 3 seconds
      return 0;
  }

Pattern 2 — BAD: unnecessary deferred probe
  probe() {
      return -EPROBE_DEFER;  ← always defer, infinite retry
  }
  /* -EPROBE_DEFER = "dependency not ready yet, retry later"
   * Only use when a required resource (clock, regulator, GPIO)
   * is genuinely not available yet */

Pattern 3 — GOOD: non-blocking + delayed work
  probe() {
      schedule_delayed_work(&work, msecs_to_jiffies(3000));
      return 0;   ← returns immediately (718 us in our test)
  }
  work_fn() {
      /* hardware init runs here, outside probe context */
  }
```

### initcall_debug — Boot Timing Tool

```bash
# Add to kernel cmdline in bootargs:
initcall_debug

# Output in dmesg:
calling  sensor_stack_ex4_driver_init+0x0/0x1000
initcall sensor_stack_ex4_driver_init+0x0/0x1000 returned 0 after 833 usecs

# Shows: function name, return code, time taken
# Use to find slow drivers adding boot delay
```

### ktime — Measuring probe() Duration

```c
ktime_t start = ktime_get();
/* ... do work ... */
ktime_t end = ktime_get();

pr_info("probe took %lld us\n", ktime_to_us(ktime_sub(end, start)));
pr_info("probe took %lld ms\n", ktime_to_ms(ktime_sub(end, start)));
pr_info("probe took %lld ns\n", ktime_to_ns(ktime_sub(end, start)));
```

---

## Ex1 — msleep() in probe() Blocks Boot

### Bug Description
`msleep(3000)` inside `sensor_probe()` blocks the probe for 3+ seconds.
During this time the kernel cannot proceed with other driver initialization.
At boot this delays userspace by the same amount.

### Reproduce Steps

```bash
# Host: build + deploy
cd ~/30days_workWith_BSP/my_projects/ch10_bootdelay
make clean && make
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 /tmp/qemu-mount
sudo cp *.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# QEMU — measure wall clock time
date
insmod /home/root/sensor_driver_delay_ex1.ko
date
dmesg | grep "Sensor Delay" | tail -5
rmmod sensor_driver_delay_ex1
```

### Actual Output (Buggy)

```
Wed Mar 25 03:46:15 UTC 2026    ← before insmod

[  215.036146] Sensor Delay [PROBE]: probe() called!
[  215.036532] Sensor Delay [BUG]: msleep(3000) blocking probe — 3 second boot delay!
[  218.147677] Sensor Delay [BUG]: woke after 3110 ms — boot delayed!
[  218.148512] Sensor Delay [PROBE]: Ready

Wed Mar 25 03:46:19 UTC 2026    ← after insmod — 4 seconds elapsed!
```

### Root Cause

```
Timeline:
  03:46:15  insmod starts
  03:46:15  probe() called
  03:46:15  msleep(3000) — kernel thread sleeps, nothing else runs
  03:46:18  msleep returns (3110ms actual)
  03:46:19  insmod returns to shell
  
Wall clock: 4 seconds lost to one driver's probe()
dmesg timestamps: 215.036 → 218.148 = 3112ms delay
```

### Fix Commands

```bash
# Remove msleep, add delayed_work instead
# See Ex3 for complete fix
sed -i 's/msleep(3000)/\/\* FIXED: use delayed_work instead \*\//' sensor_driver_delay_ex1.c
```

---

## Ex2 — Unnecessary EPROBE_DEFER

### Bug Description
Driver returns `-EPROBE_DEFER` on every probe attempt. The kernel retries
deferred probes after all other drivers load, but if the condition never
becomes true the driver never binds. After attempt=1 the kernel stops
retrying during our test — driver never loads.

### Actual Output (Buggy)

```
[  218.598122] Sensor Defer [PROBE]: probe() called! attempt=1
[  218.598529] Sensor Defer [BUG]: returning EPROBE_DEFER attempt=1 (unnecessary!)

# After sleep 5 — no more retry attempts shown
# rmmod fails — module never fully loaded (probe failed)
```

### When to Use EPROBE_DEFER Correctly

```c
/* CORRECT use — dependency genuinely not ready */
clk = devm_clk_get(&pdev->dev, "sensor_clk");
if (IS_ERR(clk)) {
    if (PTR_ERR(clk) == -EPROBE_DEFER)
        return -EPROBE_DEFER;  /* clock not ready yet, retry */
    return PTR_ERR(clk);       /* real error */
}

/* WRONG use — always defer regardless of state */
return -EPROBE_DEFER;   /* BUG: never resolves */
```

### Fix

```bash
# Only return EPROBE_DEFER when a dependency is genuinely missing
# Never return it unconditionally
sed -i '/return -EPROBE_DEFER/d' sensor_driver_delay_ex2.c
# Add proper dependency check before the defer
```

---

## Ex3 — FIXED: delayed_work Instead of msleep

### Fix Description
Replace `msleep(3000)` with `schedule_delayed_work()`. probe() returns in
718 microseconds. The 3-second hardware init runs asynchronously in a
workqueue thread after probe returns.

### Actual Output (Fixed)

```
[  224.058007] Sensor Delay [PROBE]: probe() called!
[  224.058724] Sensor Delay [FIXED]: probe() returned in 718 us — no blocking!
[  224.061295] Sensor Delay [PROBE]: Ready — init scheduled in 3s

# Shell returns immediately — no boot delay

# After sleep 4:
[  227.107853] Sensor Delay [FIXED]: delayed init done — ran outside probe()
[  227.110740] Sensor Delay [FIXED]: device 20014000.kotesh-sensor-chardev fully initialized
```

### Key Numbers

| Metric | Buggy (msleep) | Fixed (delayed_work) |
|--------|---------------|----------------------|
| probe() duration | 3110 ms | 718 us |
| Boot delay | 3+ seconds | < 1 ms |
| Hardware init | In probe (blocking) | In workqueue (async) |
| Wall clock impact | +4 seconds to insmod | immediate |

### Fix Pattern

```c
struct sensor_priv {
    struct delayed_work init_work;
    struct platform_device *pdev;
};

static void sensor_init_work(struct work_struct *work)
{
    struct sensor_priv *priv = container_of(
        to_delayed_work(work), struct sensor_priv, init_work);
    /* hardware init here — safe, not in probe context */
    pr_info("delayed init done\n");
}

static int sensor_probe(struct platform_device *pdev)
{
    struct sensor_priv *priv = devm_kzalloc(...);
    priv->pdev = pdev;
    platform_set_drvdata(pdev, priv);

    INIT_DELAYED_WORK(&priv->init_work, sensor_init_work);
    schedule_delayed_work(&priv->init_work, msecs_to_jiffies(3000));

    return 0;   /* returns immediately */
}

static int sensor_remove(struct platform_device *pdev)
{
    struct sensor_priv *priv = platform_get_drvdata(pdev);
    cancel_delayed_work_sync(&priv->init_work);  /* wait for work to finish */
    return 0;
}
```

---

## Ex4 — ktime Probe Timing + initcall_debug

### Description
Measure probe() duration using `ktime_get()`. Fast hardware init
completes in 833 microseconds — well within the < 1ms target.

### Actual Output

```
[  228.876042] Sensor Timing [PROBE]: probe() start = 228809101712 ns
[  228.876535] Sensor Timing [PROBE]: fast init complete
[  228.876878] Sensor Timing [PROBE]: probe() took 833 us
[  228.877206] Sensor Timing [PROBE]: Ready
[  229.144646] Sensor Timing [PROBE]: remove() called!
```

### initcall_debug Evidence

```
# From dmesg — driver framework call chain:
[    6.248579]  platform_probe+0x70/0xf0
[    6.248801]  really_probe.part.0+0x94/0x310
[    6.251377]  do_one_initcall+0x68/0x2c0

# To enable full initcall_debug output add to bootargs:
# initcall_debug
# Expected output format:
# calling  sensor_timing_driver_init+0x0 @ 228809101
# initcall sensor_timing_driver_init+0x0 returned 0 after 833 usecs
```

### Probe Timing Guidelines

```
< 100 us   → excellent — pure register init
< 1 ms     → acceptable — simple hardware setup
1–10 ms    → marginal — add ktime measurement, consider async
> 10 ms    → use delayed_work or devm_request_threaded_irq
> 100 ms   → always async — never block probe this long
> 1000 ms  → msleep in probe — critical bug, fix immediately
```

---

## Ch10 Complete Summary

| Ex | Bug/Feature | Probe Duration | Fix |
|----|-------------|---------------|-----|
| Ex1 | msleep(3000) in probe | 3110 ms | delayed_work |
| Ex2 | EPROBE_DEFER misuse | never loads | check real dependency |
| Ex3 | delayed_work | 718 us | schedule_delayed_work |
| Ex4 | ktime timing | 833 us | ktime_get() measurement |

---

## Key Takeaways

1. **probe() must return fast** — target < 1ms, never use msleep()
2. **delayed_work** = correct pattern for hardware needing time to initialize
3. **EPROBE_DEFER** = only when a genuine dependency (clock/regulator/GPIO) is missing
4. **ktime_get()** = measure probe duration, add to all production drivers
5. **initcall_debug** = boot cmdline option to find slow drivers at boot time
6. **cancel_delayed_work_sync()** in remove() = wait for work to finish before cleanup
7. **3110ms vs 718us** = 4300x improvement from msleep → delayed_work
