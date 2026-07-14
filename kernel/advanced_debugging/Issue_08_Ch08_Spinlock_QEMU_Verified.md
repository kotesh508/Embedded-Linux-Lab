# Issue 08 — Ch08: Spinlock Misuse (Book 2)

## Chapter
Ch08 — Spinlock Misuse: System Hang from Missing spin_unlock on Error Path

---

## Environment

| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194-yocto-standard |
| Module | spinlock_driver.ko |
| Source | ~/30days_workWith_BSP/my_projects/book2/ch08_spinlock/ |
| Device | /dev/spinlock_dev |
| Bug | spin_lock() on error path returns without spin_unlock() |
| Symptom | Second write hangs forever — lock held forever |

---

## Theory Background

### Spinlock Rules

```
spin_lock()   → disables preemption on this CPU
              → if already locked: SPINS (busy-wait) until released
              → NEVER sleeps

After spin_lock(), you MUST call spin_unlock() on EVERY exit path:
  ✓ normal success path
  ✓ every error path
  ✓ early return
  ✓ goto label

Missing spin_unlock on ANY path:
  → lock held forever
  → next spin_lock() spins forever
  → CPU stuck at 100% in spin loop
  → RCU stall warning after ~5 seconds
  → soft lockup warning after 22 seconds
  → system unresponsive

Fix: goto pattern
  spin_lock(&lock);
  if (error) { ret = -EBUSY; goto out; }   /* safe */
  do_work();
  ret = len;
out:
  spin_unlock(&lock);   /* ALWAYS reached */
  return ret;
```

---

## Ex1 — BUG: Missing spin_unlock on Busy Error Path

### Bug Code

```c
static ssize_t buggy_write(struct file *f, ...)
{
    spin_lock(&dev->lock);         /* lock acquired */
    pr_info("SPINLOCK [BUG]: got lock\n");

    if (dev->busy) {
        pr_err("device busy — returning WITHOUT unlock!\n");
        return -EBUSY;             /* BUG: returns without spin_unlock */
                                   /* lock is now held forever */
    }

    dev->busy = 1;
    do_work(dev);
    spin_unlock(&dev->lock);      /* only reached on non-busy path */
    return len;
}
```

### Actual QEMU Output — BUG Mode

```
root@qemuarm64:~# insmod /home/root/spinlock_driver.ko use_fix=0
[ 1557.222534] SPINLOCK [INIT]: mode=BUG
[ 1557.227536] SPINLOCK [INIT]: /dev/spinlock_dev created (major=249)
[ 1557.228233] SPINLOCK [INIT]: busy=1 initially
[ 1557.228675] SPINLOCK [INIT]: first write triggers busy path (no unlock in BUG mode)
[ 1557.232820] SPINLOCK [INIT]: second write hangs in BUG mode

root@qemuarm64:~# echo "a" > /dev/spinlock_dev
[ 1557.268344] SPINLOCK [OPEN]: opened
[ 1557.271637] SPINLOCK [BUG]: write called (busy=1)
[ 1557.272351] SPINLOCK [BUG]: got lock
[ 1557.272884] SPINLOCK [BUG]: device busy — returning WITHOUT unlock!
[ 1557.274140] SPINLOCK [BUG]: lock is now held forever!
sh: write error: Device or resource busy

root@qemuarm64:~# echo "b" > /dev/spinlock_dev   ← HANGS HERE
[ 1557.302234] SPINLOCK [OPEN]: opened
[ 1557.303098] SPINLOCK [BUG]: write called (busy=1)
             ← spin_lock() tries to acquire lock already held = SPINS FOREVER

# After ~21 seconds — RCU stall warning:
[ 1578.309388] rcu: INFO: rcu_preempt detected stalls on CPUs/tasks:
[ 1578.311004] rcu: rcu_preempt kthread starved for 5252 jiffies!
[ 1578.328242]  queued_spin_lock_slowpath+0x60/0x2e0
[ 1578.328667]  buggy_write+0x54/0x124 [spinlock_driver]
[ 1578.329226]  vfs_write+0xf8/0x2a0
             ← Call trace shows stuck at spin_lock inside buggy_write
```

### Stage Identification

```
t=0:   First write → spin_lock() acquired ✓
       dev->busy=1 → error path → return -EBUSY
       BUG: spin_unlock() NEVER called
       Lock state: HELD FOREVER

t=0+:  Second write → spin_lock() called
       Lock already held → CPU enters spin loop
       while (lock_is_held) { cpu_relax(); }  ← infinite loop

t=21s: Kernel detects CPU stuck in spin loop
       RCU stall warning printed
       Call trace: queued_spin_lock_slowpath → buggy_write

t=∞:   Lock never released — system hangs on that device forever
```

---

## Ex2 — FIX: goto Pattern — Single Unlock Point

### Fix Code

```c
static ssize_t fixed_write(struct file *f, ...)
{
    int ret = 0;

    spin_lock(&dev->lock);        /* lock acquired */

    if (dev->busy) {
        pr_warn("device busy — goto out (unlock guaranteed)\n");
        ret = -EBUSY;
        goto out;                 /* SAFE: falls through to spin_unlock */
    }

    if (len > MAX) {
        ret = -EINVAL;
        goto out;                 /* SAFE: multiple error paths, one unlock */
    }

    dev->busy = 1;
    do_work(dev);
    ret = len;

out:
    spin_unlock(&dev->lock);      /* ALWAYS reached — every path */
    return ret;
}
```

### FIXED Mode Test — Pending Full Verification

```
# Test commands for FIXED mode (run after BUG mode test + reboot):

insmod /home/root/spinlock_driver.ko use_fix=1
echo "a" > /dev/spinlock_dev    ← busy path, lock released cleanly
echo "b" > /dev/spinlock_dev    ← works fine — no hang
dmesg | grep SPINLOCK
rmmod spinlock_driver

# Expected output:
# SPINLOCK [FIXED]: write called (busy=1)
# SPINLOCK [FIXED]: device busy — goto out (unlock guaranteed)
# SPINLOCK [FIXED]: write called (busy=1)   ← second write also succeeds
# No hang — lock correctly released on error path
```

---

## Ex3 — IRQ-Safe: spin_lock_irqsave

### When to Use irqsave Variant

```c
/*
 * If an IRQ handler also takes the same lock:
 *
 * Normal: spin_lock() only disables preemption
 *         IRQ fires → IRQ handler calls spin_lock() → deadlock
 *         (same CPU, IRQ handler can never get lock)
 *
 * Fix: spin_lock_irqsave() also disables IRQs on this CPU
 */

unsigned long flags;

spin_lock_irqsave(&dev->lock, flags);     /* disable IRQs + acquire lock */
/* critical section */
spin_unlock_irqrestore(&dev->lock, flags); /* release lock + restore IRQs */
```

---

## CONFIG_DEBUG_SPINLOCK Detection

```bash
# Enable in Yocto:
bitbake linux-yocto -c menuconfig
# Kernel hacking → Lock Debugging →
#   [*] Spinlock and rw-lock debugging: basic checks
# CONFIG_DEBUG_SPINLOCK=y

# Detects:
# - Unlocking a lock that was not locked
# - Double-lock on same CPU
# - Unlock from wrong CPU

# Expected dmesg on double-unlock:
# BUG: spinlock bad magic on CPU#0
# BUG: spinlock wrong CPU on CPU#0
```

---

## Reproduce Steps

```bash
# HOST — Build
cd ~/30days_workWith_BSP/my_projects/book2/ch08_spinlock
make clean && make

# Deploy
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp spinlock_driver.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount

~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — BUG (requires reboot after)
insmod /home/root/spinlock_driver.ko use_fix=0
echo "a" > /dev/spinlock_dev    # triggers busy, no unlock
echo "b" > /dev/spinlock_dev    # HANGS — Ctrl+C after 5s
dmesg | grep -E "SPINLOCK|rcu|soft lockup"
# Reboot QEMU

# INSIDE QEMU — FIXED
insmod /home/root/spinlock_driver.ko use_fix=1
echo "a" > /dev/spinlock_dev    # busy path — returns cleanly
echo "b" > /dev/spinlock_dev    # no hang
dmesg | grep SPINLOCK
rmmod spinlock_driver
```

---

## What I Checked

```
✔ BUG: first write
  → SPINLOCK [BUG]: got lock
  → SPINLOCK [BUG]: device busy — returning WITHOUT unlock!
  → SPINLOCK [BUG]: lock is now held forever!
  → return -EBUSY (no spin_unlock called)

✔ BUG: second write
  → SPINLOCK [BUG]: write called (busy=1)
  → silence — spinning on locked spinlock
  → RCU stall: queued_spin_lock_slowpath → buggy_write
  → system hangs on /dev/spinlock_dev forever

✔ RCU stall call trace
  → queued_spin_lock_slowpath+0x60/0x2e0
  → buggy_write+0x54/0x124 [spinlock_driver]
  → confirms: stuck inside spin_lock() in buggy_write
```

---

## Root Cause vs Fix Summary

| | BUG | FIXED |
|--|-----|-------|
| Error path | `return -EBUSY` without unlock | `goto out` → `spin_unlock` |
| Lock state after error | HELD FOREVER | RELEASED cleanly |
| Second write | HANGS in spin loop | Returns normally |
| RCU stall | YES — after 21 seconds | NONE |
| Pattern | inline return | goto + single unlock point |

---

## Key Takeaways

1. Every `spin_lock()` needs `spin_unlock()` on **every** exit path
2. `goto` pattern = one `spin_unlock()` that all paths reach — production standard
3. Missing unlock = next `spin_lock()` spins forever = system hang
4. RCU stall warning at 5252 jiffies = ~5 seconds of CPU stuck in spin
5. Call trace shows `queued_spin_lock_slowpath` = stuck waiting for lock
6. `spin_lock_irqsave` when IRQ handler takes the same lock
7. `CONFIG_DEBUG_SPINLOCK=y` detects double-lock and unlock-without-lock
8. Spinlock holds preemption disabled — never sleep while holding one
