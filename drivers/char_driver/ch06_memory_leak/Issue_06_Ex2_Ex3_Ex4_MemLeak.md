# Ch06 Exercise 2 – Memory Leak: Fix with kfree in remove()

## Objective
Fix the Ex1 memory leak by adding `kfree(dev->buf)` in `sensor_remove()`.
Verify using kmemleak that no leaks are detected after load/unload cycle.

---

## Core Theory — kfree and SLUB Lifecycle

```
kmalloc(64, GFP_KERNEL)
  └── SLUB allocates from kmalloc-128 cache
        └── slot marked ALLOCATED
              └── kmemleak records {addr, size, backtrace}

kfree(ptr)   ← correct original pointer
  └── SLUB finds slab page for ptr
        └── slot marked FREE
              └── kmemleak removes entry
                    └── no leak reported ✔

Missing kfree() or kfree(wrong_ptr)
  └── slot stays ALLOCATED
        └── kmemleak entry stays
              └── scan reports LEAK ✗
```

---

## Fix Applied

```c
/* BEFORE — BUGGY (Ex1) */
static int sensor_remove(struct platform_device *pdev)
{
    /* sdev->buf never freed — memory leak */
    pr_info("Sensor MemLeak [PROBE]: remove() called! buf NOT freed!\n");
    return 0;
}

/* AFTER — FIXED (Ex2) */
static int sensor_remove(struct platform_device *pdev)
{
    struct sensor_dev *dev = platform_get_drvdata(pdev);
    kfree(dev->buf);        /* FIXED: free kmalloc buffer */
    dev->buf = NULL;        /* prevent use-after-free */
    pr_info("Sensor MemLeak [FIXED]: buf freed in remove()\n");
    return 0;
}
```

### sed -i Fix Commands

```bash
# Fix remove() to add kfree
# In sensor_remove(), replace the buggy body:
sed -i 's/buf NOT freed!/buf freed in remove()/' sensor_driver_memleak.c
# Add kfree line manually in vim or use:
# sed -i '/sensor_remove/,/return 0/{s/return 0/kfree(dev->buf);\n    dev->buf = NULL;\n    return 0/}' sensor_driver_memleak.c

# Fix comments
sed -i 's\/\* BUG: kmalloc buf.*\*\/\/\/* FIXED: kmalloc buf — freed in remove() *\//'\
    sensor_driver_memleak.c
sed -i 's/BUGGY kfree in remove/FIXED kfree in remove/' sensor_driver_memleak.c

# Verify
grep -n "kfree\|FIXED\|BUG\|DESCRIPTION" sensor_driver_memleak.c
```

---

## Verified Output (Fixed)

```
root@qemuarm64:~# echo clear > /sys/kernel/debug/kmemleak

root@qemuarm64:~# insmod /home/root/sensor_driver_memleak.ko
[  274.115213] Sensor MemLeak [PROBE]: probe() called!
[  274.115987] Sensor MemLeak [FIXED]: kmalloc(64) — will be freed in remove
[  274.116433] Sensor MemLeak [PROBE]: Ready

root@qemuarm64:~# echo scan > /sys/kernel/debug/kmemleak
root@qemuarm64:~# sleep 2
root@qemuarm64:~# cat /sys/kernel/debug/kmemleak
(empty — no leaks detected)

root@qemuarm64:~# grep MemFree /proc/meminfo
MemFree: 948712 kB

root@qemuarm64:~# rmmod sensor_driver_memleak
[  279.071544] Sensor MemLeak [FIXED]: buf freed in remove()

root@qemuarm64:~# grep MemFree /proc/meminfo
MemFree: 948712 kB    ← same — memory properly returned

root@qemuarm64:~# cat /sys/kernel/debug/kmemleak
(empty — confirmed clean)
```

---

## What I Checked ✔

```
✔ kmemleak empty after scan — no leaks
✔ [FIXED]: buf freed in remove() — kfree called correctly
✔ MemFree same before/after unload — memory returned to SLUB
✔ kmemleak clean after rmmod — confirmed no orphaned allocations
```

---

## Key Learning

- Every `kmalloc()` in `probe()` needs matching `kfree()` in `remove()`
- Set pointer to NULL after `kfree()` — prevents use-after-free bugs
- Use `platform_get_drvdata()` in `remove()` to get the device struct back
- Better alternative: use `devm_kzalloc()` — auto-freed, no manual kfree needed
- kmemleak empty = clean — no unreferenced objects remain

---
---

# Ch06 Exercise 3 – Memory Leak: kfree Wrong Pointer (Slab Corruption)

## Objective
Demonstrate that calling `kfree()` with an offset pointer (`buf+8` instead of `buf`)
causes kmemleak to detect a wrong-pointer free via "Found object by alias" — the
original allocation is never properly freed, leaving a leak AND corrupting slab
bookkeeping. Understand how SLUB and kmemleak handle offset pointer frees.

---

## Core Theory — Slab Corruption via Wrong Pointer

```
kmalloc(64) returns ptr = 0xffffff8004a9cf00
                               ↑
                       SLUB object start

kfree(ptr)         ← CORRECT — frees at object start
kfree(ptr + 8)     ← WRONG  — 0xffffff8004a9cf08
                                         ↑
                              8 bytes INTO the object
                              NOT at object start

SLUB checks:
  ptr+8 → is this the start of a slab object?
         → NO → not a valid free pointer
         → SLUB/kmemleak: "Found object by alias"
         → original object at ptr NOT freed → LEAK

kmemleak behavior:
  kfree(ptr+8) called
    └── kmemleak_free(ptr+8) called internally
          └── lookup_object(ptr+8) — finds containing object
                └── "Found object by alias at ptr+8"
                      └── prints full backtrace
                            └── object NOT removed from kmemleak list
                                  └── reported as leak on next scan
```

### Why This Is Dangerous on Real Hardware

```
Correct slab object layout (kmalloc-128):
  [0x00-0x7F] = your 64-byte buffer (padded to 128)
  SLUB metadata stored separately in slab page header

kfree(ptr+8):
  SLUB tries to find slab metadata for ptr+8
  On some kernel versions/configs:
    → general protection fault (GPF)
    → kernel BUG()
    → silent corruption of adjacent object
  On this kernel with kmemleak enabled:
    → kmemleak intercepts and reports alias
    → original object leaks
    → driver continues running (no immediate crash)
    → but system integrity is compromised
```

---

## Environment

| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| Module | sensor_driver_memleak_ex3.ko |
| Bug | `kfree(dev->buf + 8)` — 8-byte offset from allocation start |
| Detector | kmemleak "Found object by alias" |

---

## Symptom (Log Snippet)

```
root@qemuarm64:~# insmod /home/root/sensor_driver_memleak_ex3.ko
[  188.930339] Sensor MemLeak Ex3 [PROBE]: probe() called!
[  188.930967] Sensor MemLeak Ex3 [PROBE]: Ready, buf=(____ptrval____)

root@qemuarm64:~# rmmod sensor_driver_memleak_ex3
[  189.176017] Sensor MemLeak Ex3 [BUG]: kfree(buf+8) — wrong pointer!
[  189.176553] kmemleak: Found object by alias at 0xffffff8004a9cf08
[  189.177473] Hardware name: linux,dummy-virt (DT)
[  189.177743] Call trace:
[  189.179592]  sensor_remove+0x38/0x58 [sensor_driver_memleak_ex3]
...
[  189.183678] kmemleak: Object 0xffffff8004a9cf00 (size 128):
[  189.185569]      sensor_probe+0x60/0xb0 [sensor_driver_memleak_ex3]
```

**Key observations:**
- `Found object by alias at 0xffffff8004a9cf08` — passed ptr+8
- `Object 0xffffff8004a9cf00` — real object starts 8 bytes earlier
- `sensor_remove+0x38` — exact location of wrong kfree
- `sensor_probe+0x60` — where original kmalloc was called
- Driver doesn't crash — kmemleak intercepts and reports

---

## Stage Identification

```
probe() called
  └── kmalloc(64) → returns 0xffffff8004a9cf00
        └── kmemleak records: {0xcf00, 128, sensor_probe+0x60}

remove() called
  └── kfree(dev->buf + 8) → passes 0xffffff8004a9cf08
        └── kmemleak_free(0xcf08) called internally
              └── lookup_object(0xcf08)
                    └── finds object at 0xcf00 containing 0xcf08
                          └── "Found object by alias"
                                └── prints backtrace
                                      └── object at 0xcf00 NOT freed
                                            └── LEAK remains
```

---

## Buggy Code

```c
static int sensor_remove(struct platform_device *pdev)
{
    struct sensor_dev *dev = platform_get_drvdata(pdev);

    /* BUG: offset pointer — not original kmalloc address */
    kfree(dev->buf + 8);   /* ← wrong: 8 bytes past start */
    return 0;
}
```

---

## Fix

```c
static int sensor_remove(struct platform_device *pdev)
{
    struct sensor_dev *dev = platform_get_drvdata(pdev);

    /* FIXED: always free original pointer */
    kfree(dev->buf);       /* ← correct: original kmalloc address */
    dev->buf = NULL;
    return 0;
}
```

### sed -i Fix Command

```bash
# Fix wrong pointer offset
sed -i 's/kfree(dev->buf + 8)/kfree(dev->buf)/' sensor_driver_memleak_ex3.c

# Add NULL assignment after kfree
# (add manually or use awk)

# Verify
grep -n "kfree" sensor_driver_memleak_ex3.c
```

---

## Reproduction Steps

```bash
# HOST
cd ~/30days_workWith_BSP/my_projects/ch06_memleak
make clean && make

sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp sensor_driver_memleak_ex3.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount

~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU
echo clear > /sys/kernel/debug/kmemleak

insmod /home/root/sensor_driver_memleak_ex3.ko
dmesg | grep "Ex3" | tail -3

# Unload — triggers kfree(buf+8)
rmmod sensor_driver_memleak_ex3
dmesg | grep "Ex3\|alias\|Object" | tail -20

# Check kmemleak
echo scan > /sys/kernel/debug/kmemleak
sleep 2
cat /sys/kernel/debug/kmemleak
```

---

## What I Checked ✔

```
✔ kmemleak: Found object by alias at 0xffffff8004a9cf08
  → kmemleak detected offset 8 bytes from real object start

✔ kmemleak: Object 0xffffff8004a9cf00 (size 128)
  → real allocation starts at cf00, passed cf08 (wrong)

✔ sensor_remove+0x38 in call trace
  → exact location of wrong kfree in driver

✔ sensor_probe+0x60 in kmemleak backtrace
  → where original kmalloc was called

✔ kmemleak still reports leak after rmmod
  → object at cf00 never properly freed
```

---

## Interview Explanation

> "The driver called `kfree(dev->buf + 8)` instead of `kfree(dev->buf)`. The pointer
> arithmetic moved 8 bytes past the start of the allocated object. kmemleak detected
> this as 'Found object by alias' — it found the real object at `buf` that contains
> the passed address `buf+8`. The original 128 bytes were never freed, causing a leak.
> On production kernels without kmemleak, this could cause silent slab corruption or
> a general protection fault. The fix is always to free the original pointer returned
> by kmalloc — never offset it."

---

## Key Learning

- Always `kfree()` the **exact pointer returned by kmalloc** — never offset it
- `kfree(ptr+N)` = "Found object by alias" — kmemleak catches this
- Pointer arithmetic before `kfree` is always wrong — save original pointer
- If you need to advance through a buffer, use a separate pointer:
  ```c
  char *buf = kmalloc(64);   /* save original */
  char *p = buf;             /* use p for traversal */
  p += 8;                    /* advance copy */
  kfree(buf);                /* free original — correct */
  ```
- On kernels without kmemleak, wrong-pointer kfree can cause GPF or silent corruption
- `dev->buf = NULL` after kfree prevents accidental double-free

---
---

# Ch06 Exercise 4 – Memory Leak: devm_ vs Manual kfree (Double Free)

## Objective
Demonstrate that mixing `devm_kzalloc()` with manual `kfree()` causes a double-free
when the driver is removed — `devm` cleanup and manual `kfree` both try to free the
same pointer. Understand the `devm_` resource management system and why mixing
manual and managed allocations causes BUG/corruption.

---

## Core Theory — devm_ Resource Management

```
devm_kzalloc(&pdev->dev, size, GFP_KERNEL)
  └── internally calls kmalloc(size)
        └── registers ptr in device's devres list:
              devres_list → [entry: {ptr, kfree_fn}]

device remove triggered (rmmod)
  └── kernel calls device_release()
        └── iterates devres_list
              └── for each entry: calls kfree_fn(ptr)
                    └── memory freed automatically ✔

If you ALSO call kfree(ptr) manually in remove():
  └── manual kfree() → ptr freed (slot marked FREE in SLUB)
        └── devres cleanup → kfree(same ptr) AGAIN
              └── SLUB: double free detected
                    └── BUG: kernel trying to free already-free object
                          → panic or silent corruption
```

### devm_ Rule

```
devm_kzalloc()  → NEVER call kfree() manually
                  devm handles cleanup automatically

kmalloc()       → ALWAYS call kfree() in remove()
                  no automatic cleanup

Mixing them:
  devm_kzalloc() + kfree() = DOUBLE FREE → BUG
  kmalloc()     + no kfree = LEAK
```

---

## Buggy Code

```c
static int sensor_probe(struct platform_device *pdev)
{
    /* devm_ allocation — auto-freed on remove */
    sdev->buf = devm_kzalloc(&pdev->dev, LEAK_SIZE, GFP_KERNEL);
    ...
}

static int sensor_remove(struct platform_device *pdev)
{
    struct sensor_dev *dev = platform_get_drvdata(pdev);
    /* BUG: manual kfree of devm_ allocation → double free */
    kfree(dev->buf);
    ...
}
```

---

## Fix

```c
static int sensor_remove(struct platform_device *pdev)
{
    /* FIXED: remove manual kfree — devm handles it */
    /* kfree(dev->buf);  ← DELETE this line */
    pr_info("Sensor MemLeak [FIXED]: devm handles buf cleanup\n");
    return 0;
}
```

### sed -i Fix Command

```bash
# Remove the wrong manual kfree of devm allocation
sed -i '/kfree(dev->buf)/d' sensor_driver_memleak_ex4.c

# Verify no manual kfree remains
grep -n "kfree" sensor_driver_memleak_ex4.c
# Expected: no output — devm handles everything
```

---

## Ch06 Complete Summary

| Exercise | Bug Type | Allocator | Detector | Key Error |
|---|---|---|---|---|
| Ex1 | kmalloc no kfree | SLUB | kmemleak | `unreferenced object` with backtrace |
| Ex2 | Fix: add kfree | SLUB | kmemleak clean | No leaks after fix |
| Ex3 | kfree wrong ptr | SLUB | kmemleak | `Found object by alias` |
| Ex4 | devm_ + kfree | devm/SLUB | BUG/panic | Double free on remove |

---

## Memory Debugging Tools Reference

```bash
# kmemleak commands
echo clear > /sys/kernel/debug/kmemleak    # clear previous records
echo scan  > /sys/kernel/debug/kmemleak    # trigger manual scan
cat /sys/kernel/debug/kmemleak             # view leaks with backtrace
echo off   > /sys/kernel/debug/kmemleak    # disable kmemleak

# Memory info
cat /proc/meminfo                           # overall memory stats
cat /proc/slabinfo                          # per-cache slab stats
grep kmalloc /proc/slabinfo                 # kmalloc cache stats

# SLUB debug (if CONFIG_SLUB_DEBUG=y)
cat /sys/kernel/slab/kmalloc-128/alloc_calls
cat /sys/kernel/slab/kmalloc-128/free_calls
```
