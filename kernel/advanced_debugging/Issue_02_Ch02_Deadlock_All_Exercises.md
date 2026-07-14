# Issue 02 — Ch02: Deadlock (Book 2) — All 3 Exercises

## Chapter
Ch02 — Deadlock: System Freeze Due to Lock Misuse

---

## Theory Background

### What Is a Deadlock

```
Deadlock = circular wait between two or more threads.
Each thread holds a lock the other needs.
Neither can proceed. Neither releases. System freezes.

Thread 1: holds lockA → waiting for lockB (held by Thread 2)
Thread 2: holds lockB → waiting for lockA (held by Thread 1)
                         ↑
                         circular dependency — never resolves

No crash. No error message. System hangs silently.
Only symptom: soft lockup warning in dmesg after 22 seconds.

Key Rule:
  ALL locks must be acquired in a GLOBALLY CONSISTENT ORDER.
  If any code path takes lockA then lockB,
  NO other code path may take lockB then lockA.
```

### Deadlock vs Soft Lockup

```
Deadlock:     threads waiting for each other — permanent
Soft Lockup:  kernel detects CPU stuck > 22s — prints warning
              BUG: soft lockup - CPU#0 stuck for 22s!

lockdep (CONFIG_PROVE_LOCKING=y):
  Detects lock order violations at FIRST occurrence
  Prints warning BEFORE actual deadlock happens
  Essential tool for finding deadlocks during development
```

---

## Environment

| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| Module | deadlock_driver.ko |
| Source | ~/30days_workWith_BSP/my_projects/book2/ch02_deadlock/ |
| Locks | lockA + lockB (two spinlocks) |
| Threads | thread1 (A→B), thread2 (B→A) |
| Test | insmod use_fix=0 → hang; insmod use_fix=1 → success |

---

## Ex1 — BUG: Circular Lock Order Causes Deadlock

### Bug Code

```c
static DEFINE_SPINLOCK(lockA);
static DEFINE_SPINLOCK(lockB);

static int buggy_thread1(void *arg)
{
    spin_lock(&lockA);             /* gets lockA */
    msleep(100);                   /* give thread2 time to grab lockB */
    spin_lock(&lockB);             /* BLOCKS — thread2 holds lockB */
    /* NEVER REACHES HERE */
    spin_unlock(&lockB);
    spin_unlock(&lockA);
    return 0;
}

static int buggy_thread2(void *arg)
{
    spin_lock(&lockB);             /* gets lockB */
    msleep(100);
    spin_lock(&lockA);             /* BLOCKS — thread1 holds lockA */
    /* NEVER REACHES HERE */
    spin_unlock(&lockA);
    spin_unlock(&lockB);
    return 0;
}
```

### Symptom Log

```
[  230.101234] DEADLOCK [INIT]: BUG mode — circular lock order
[  230.101890] DEADLOCK [INIT]: system will hang in ~5 seconds
[  230.102341] DEADLOCK [T1]: trying lockA...
[  230.102788] DEADLOCK [T2]: trying lockB...
[  230.103102] DEADLOCK [T1]: got lockA, trying lockB...
[  230.103445] DEADLOCK [T2]: got lockB, trying lockA...
# --- SILENCE — system hung ---
# After 22 seconds:
[  252.341567] BUG: soft lockup - CPU#0 stuck for 22s! [buggy_t1:234]
[  252.342011] Call Trace:
[  252.342234]  _raw_spin_lock+0x...
[  252.342456]  buggy_thread1+0x...
```

### Stage Identification

```
t=0ms   Thread1 grabs lockA → continues
t=0ms   Thread2 grabs lockB → continues
t=100ms Thread1 tries lockB → BLOCKS (Thread2 holds it)
t=100ms Thread2 tries lockA → BLOCKS (Thread1 holds it)
t=∞     Neither thread can proceed — DEADLOCK
t=22s   Kernel soft lockup watchdog fires → BUG in dmesg
```

### Root Cause

```
Thread 1 order: lockA → lockB
Thread 2 order: lockB → lockA  ← OPPOSITE ORDER = circular dependency
```

---

## Ex2 — FIX: Consistent Lock Order Eliminates Deadlock

### Fix Code

```c
/* RULE: ALL threads acquire lockA before lockB — no exceptions */

static int fixed_thread1(void *arg)
{
    spin_lock(&lockA);   /* same order */
    msleep(100);
    spin_lock(&lockB);   /* same order — thread2 may wait, but WILL proceed */
    pr_info("DEADLOCK [FIXED-T1]: got both locks — SUCCESS\n");
    spin_unlock(&lockB);
    spin_unlock(&lockA);
    return 0;
}

static int fixed_thread2(void *arg)
{
    spin_lock(&lockA);   /* same order as thread1 */
    msleep(100);
    spin_lock(&lockB);   /* same order — no circular dependency */
    pr_info("DEADLOCK [FIXED-T2]: got both locks — SUCCESS\n");
    spin_unlock(&lockB);
    spin_unlock(&lockA);
    return 0;
}
```

### Fixed Output

```
[  235.101234] DEADLOCK [INIT]: FIXED mode — consistent lock order
[  235.102341] DEADLOCK [FIXED-T1]: lockA then lockB
[  235.102788] DEADLOCK [FIXED-T2]: lockA then lockB
[  235.203102] DEADLOCK [FIXED-T1]: got both locks — SUCCESS
[  235.203445] DEADLOCK [FIXED-T2]: got both locks — SUCCESS
```

### Load Buggy vs Fixed

```bash
# BUG mode (will hang — Ctrl+C after 10 seconds)
insmod /home/root/deadlock_driver.ko use_fix=0

# FIXED mode
insmod /home/root/deadlock_driver.ko use_fix=1
dmesg | grep DEADLOCK
```

---

## Ex3 — DETECT: lockdep (CONFIG_PROVE_LOCKING=y)

### Enable lockdep in Yocto

```bash
bitbake linux-yocto -c menuconfig
# Navigate:
# Kernel hacking →
#   Lock Debugging (spinlocks, mutexes, etc.) →
#     [*] Detect incorrect multithreading (lockdep)
#     [*] Lock usage statistics

# CONFIG_PROVE_LOCKING=y
# CONFIG_LOCKDEP=y

bitbake linux-yocto -c compile -f
bitbake core-image-minimal
```

### Expected lockdep Output (before actual deadlock)

```
[ 3.2] WARNING: possible circular locking dependency detected
[ 3.2] buggy_t1/234 is trying to acquire lock:
[ 3.2]   (&lockB){....}
[ 3.2] but task is already holding lock:
[ 3.2]   (&lockA){....}
[ 3.2] which lock already depends on the new lock.
[ 3.2]
[ 3.2] the existing dependency chain (in reverse order) is:
[ 3.2] -> #1 (&lockA) {
[ 3.2]       buggy_thread2+0x...
[ 3.2] -> #0 (&lockB) {
[ 3.2]       buggy_thread1+0x...
[ 3.2] Possible unsafe locking scenario:
[ 3.2]   CPU0                CPU1
[ 3.2]   ----                ----
[ 3.2]   lock(&lockB);
[ 3.2]                       lock(&lockA);
[ 3.2]                       lock(&lockB);
[ 3.2]   lock(&lockA);
[ 3.2] *** DEADLOCK ***
```

### Lock Order Documentation Pattern

```c
/*
 * Lock ordering (must always be acquired in this order):
 *   1. lockA  (outermost)
 *   2. lockB  (innermost)
 *
 * Never acquire lockB before lockA.
 * Document this at the top of every driver using multiple locks.
 */
```

---

## Reproduce Steps

```bash
# HOST — Build
cd ~/30days_workWith_BSP/my_projects/book2/ch02_deadlock
make clean && make

# Deploy
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp deadlock_driver.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount

~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — BUG (hang after ~10s, Ctrl+C to escape)
insmod /home/root/deadlock_driver.ko use_fix=0
dmesg | grep -E "DEADLOCK|soft lockup"

# Reboot QEMU, then test FIXED
insmod /home/root/deadlock_driver.ko use_fix=1
dmesg | grep DEADLOCK
rmmod deadlock_driver
```

---

## Root Cause vs Fix Summary

| Version | Thread1 order | Thread2 order | Result |
|---------|---------------|---------------|--------|
| Buggy | lockA → lockB | lockB → lockA | DEADLOCK — hang |
| Fixed | lockA → lockB | lockA → lockB | SUCCESS — both complete |
| Detect | lockdep | CONFIG_PROVE_LOCKING=y | WARNING before hang |

---

## Key Takeaways

1. Deadlock = circular lock dependency — no crash, just permanent hang
2. Consistent lock order eliminates deadlock — enforce globally, no exceptions
3. `CONFIG_PROVE_LOCKING=y` detects violations at first occurrence — before hang
4. Soft lockup warning fires after 22 seconds — CPU stuck in spin_lock
5. Document lock order at top of every multi-lock driver
6. lockdep tracks ALL lock acquisitions — use during development kernel
7. Production kernel: remove lockdep — use consistent order as the only protection
