# Issue 01 — Ch01: Race Condition (Book 2) — All 4 Exercises

## Chapter
Ch01 — Race Condition: Hidden Data Corruption

---

## Theory Background

### Why counter++ Is NOT Safe

```
counter++ compiles to THREE CPU instructions:
  1. READ   — load counter into register
  2. MODIFY — increment register
  3. WRITE  — store register back to memory

Thread A reads counter = 5
Thread B reads counter = 5    ← SAME value (race!)
Thread A writes counter = 6
Thread B writes counter = 6   ← should be 7, lost one increment

100 threads doing counter++ on initial value 0:
  Without lock → result = 1 to 100 (random, wrong)
  With spinlock → result = 100 (always correct)
  With atomic_t → result = 100 (always correct, faster)

Key Rule:
  Any variable accessed by 2+ execution contexts MUST be protected.
  Assume races exist until proven otherwise with a lock or atomic op.
```

### Fix Options

```
Option 1: spinlock
  Use when protecting MULTIPLE variables together
  or compound read-modify-write operations

Option 2: atomic_t
  Use for a SINGLE integer counter or flag
  Hardware atomic instruction — no lock overhead
  Simpler code, better performance on counters

Option 3: CONFIG_KCSAN=y
  Kernel Concurrency Sanitizer — detects races at runtime
  Reports exact file, line, thread — use during development
```

---

## Environment

| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| Module | race_counter_driver.ko |
| Source | ~/30days_workWith_BSP/my_projects/book2/ch01_race_condition/ |
| Threads | 2 kernel threads per test |
| Target | 1000 increments per thread = expected 2000 |
| Test method | insmod → dmesg → compare buggy vs fixed counter |

---

## Ex1 — BUG: No Lock, Shared Counter Corrupted

### Bug Code

```c
static int buggy_counter = 0;

static int buggy_thread(void *arg)
{
    int i, local;
    for (i = 0; i < TARGET; i++) {
        local = buggy_counter;      /* STEP 1: READ */
        schedule();                  /* yield — other thread runs HERE */
        buggy_counter = local + 1;  /* STEP 2+3: MODIFY+WRITE old value */
    }
    return 0;
}
```

### Symptom Log (Actual QEMU Output)

```
[  225.177424] RACE [INIT]: starting — expected result = 2000
[  225.191202] RACE [ThreadA]: done
[  225.195063] RACE [ThreadB]: done
[  225.705679] RACE [BUG]  counter = 1282 (expected 2000) — WRONG!
```

### Stage Identification

```
ThreadA reads buggy_counter = 0
  schedule() → ThreadB runs
ThreadB reads buggy_counter = 0   ← SAME value ThreadA already read
  schedule() → ThreadA runs
ThreadA writes buggy_counter = 1  ← correct
  schedule() → ThreadB runs
ThreadB writes buggy_counter = 1  ← BUG: should be 2, writes 1
                                     one increment LOST every cycle
```

### Root Cause

```c
/* BUGGY */
local = buggy_counter;      /* READ old value */
schedule();                  /* context switch — race window open */
buggy_counter = local + 1;  /* WRITE old value + 1 — loses concurrent write */
```

### What I Checked

```
✔ dmesg | grep RACE
  → BUG counter = 1282 — race confirmed on single-core QEMU
  → schedule() forces context switch between READ and WRITE
  → 718 increments lost out of 2000 expected
```

---

## Ex2 — FIX: spinlock Protects Critical Section

### Fix Code

```c
static DEFINE_SPINLOCK(counter_lock);
static int spinlock_counter = 0;

static int spinlock_thread(void *arg)
{
    int i;
    for (i = 0; i < TARGET; i++) {
        spin_lock(&counter_lock);
        spinlock_counter++;         /* protected: only one thread at a time */
        spin_unlock(&counter_lock);
    }
    return 0;
}
```

### When to Use spinlock

```
spinlock:
  ✔ Protecting MULTIPLE variables updated together
  ✔ Compound operations (check + modify + write)
  ✔ IRQ handler protection (use spin_lock_irqsave)
  ✗ Single counter — use atomic_t instead (simpler)
  ✗ Code that needs to sleep — use mutex instead
```

---

## Ex3 — FIX: atomic_t — Simplest Solution

### Fix Code

```c
static atomic_t fixed_counter = ATOMIC_INIT(0);

static int fixed_thread(void *arg)
{
    int i;
    for (i = 0; i < TARGET; i++) {
        atomic_inc(&fixed_counter);  /* single hardware instruction — always safe */
    }
    return 0;
}
```

### Verified Output (Actual QEMU Output)

```
[  225.720829] RACE [FixedA]: done
[  225.723961] RACE [FixedB]: done
[  226.249470] RACE [FIXED] counter = 2000 (expected 2000) — CORRECT!
```

### atomic_t API Reference

```c
atomic_t counter = ATOMIC_INIT(0);  /* declare and init */

atomic_inc(&counter);               /* counter++ */
atomic_dec(&counter);               /* counter-- */
atomic_add(5, &counter);            /* counter += 5 */
atomic_sub(3, &counter);            /* counter -= 3 */
int val = atomic_read(&counter);    /* read value */
atomic_set(&counter, 0);            /* set value */

/* Compound operations */
atomic_inc_and_test(&counter);      /* returns true if result == 0 */
atomic_dec_and_test(&counter);      /* returns true if result == 0 */
```

---

## Ex4 — DETECT: KCSAN Race Detector

### Enable in Yocto Kernel

```bash
bitbake linux-yocto -c menuconfig
# Navigate:
# Kernel hacking →
#   Memory Debugging →
#     [*] Kernel Concurrency Sanitizer (KCSAN)

# Rebuild
bitbake linux-yocto -c compile -f
bitbake core-image-minimal
```

### Expected KCSAN Output (with CONFIG_KCSAN=y)

```
[ 3.4] KCSAN: data-race in buggy_thread / buggy_thread
[ 3.4] Write of size 4 at 0xffffffc009ab1234 by task race_thread_b/234
[ 3.4] Read  of size 4 at 0xffffffc009ab1234 by task race_thread_a/233
[ 3.4]  race_counter_driver+0x2c/0x80 [race_counter_driver]
```

### Verify Config

```bash
# In QEMU:
zcat /proc/config.gz | grep KCSAN
# Expected: CONFIG_KCSAN=y

# Run with KCSAN kernel:
insmod race_counter_driver.ko
dmesg | grep KCSAN
```

---

## Reproduce Steps

```bash
# HOST — Build
cd ~/30days_workWith_BSP/my_projects/book2/ch01_race_condition
make clean && make

# Deploy to rootfs
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp race_counter_driver.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount

# Boot QEMU
~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU
insmod /home/root/race_counter_driver.ko
dmesg | grep RACE
rmmod race_counter_driver
```

---

## Root Cause vs Fix Summary

| Version | Code | Result | Notes |
|---------|------|--------|-------|
| Buggy | `counter++` with `schedule()` | 1282/2000 WRONG | race on every iteration |
| Fix 1 | `spin_lock` + `counter++` + `spin_unlock` | 2000 CORRECT | good for compound ops |
| Fix 2 | `atomic_inc(&counter)` | 2000 CORRECT | best for single counter |
| Detect | `CONFIG_KCSAN=y` | reports data race | use during development |

---

## Key Takeaways

1. `counter++` = 3 CPU instructions — NOT atomic, NOT safe without lock
2. Any shared variable accessed by 2+ threads MUST be protected
3. `atomic_t` = best for single integer counters — no lock overhead
4. `spinlock` = use when protecting multiple variables together
5. `schedule()` forces race on single-core — same effect as real SMP
6. `CONFIG_KCSAN=y` detects races automatically — use in development kernel
7. Bug is SILENT — no crash, no dmesg error — only wrong final value
