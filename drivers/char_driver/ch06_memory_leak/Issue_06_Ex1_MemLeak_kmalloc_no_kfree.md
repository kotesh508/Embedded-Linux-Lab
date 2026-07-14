# Ch06 Exercise 1 – Memory Leak: kmalloc Without kfree

## Objective
Demonstrate a kernel memory leak caused by `kmalloc()` in `probe()` without a
corresponding `kfree()` in `remove()`. Detect the leak using `kmemleak` which
reports the exact leaked address, content, size, and backtrace to the leaking
`kmalloc()` call.

---

## Core Theory — Linux Kernel Memory Allocators

### Memory Allocator Stack

```
Physical Memory (RAM)
        │
        ▼
┌─────────────────────────────────────────┐
│          Buddy Allocator                 │
│  alloc_pages() / __get_free_pages()     │
│  Unit: pages (4KB minimum)              │
│  Allocates: 1,2,4,8,16... pages         │
│  Best for: large, page-aligned buffers  │
└─────────────────────────────────────────┘
        │ feeds slabs from page pool
        ▼
┌─────────────────────────────────────────┐
│       Slab Allocator (SLUB in 5.x)      │
│  kmalloc() / kzalloc()                  │
│  Unit: bytes (8,16,32,64,128...bytes)   │
│  Allocates from pre-sized caches        │
│  Best for: small kernel objects         │
│  kfree() to release                     │
└─────────────────────────────────────────┘
        │ both feed virtual address space
        ▼
┌─────────────────────────────────────────┐
│            vmalloc                       │
│  Virtually contiguous, not physical     │
│  Best for: large (>128KB) allocations   │
│  vfree() to release                     │
└─────────────────────────────────────────┘
```

### Quick Decision Guide

```
Size < 4KB, physically contiguous needed?  → kmalloc()
Size < 4KB, zeroed memory needed?          → kzalloc()
Size > 128KB, contiguous not required?     → vmalloc()
In probe(), auto-free on remove needed?    → devm_kzalloc()
Need raw pages?                            → alloc_pages()
```

### How kmalloc Works Internally (SLUB)

```
kmalloc(64, GFP_KERNEL)
  └── SLUB finds "kmalloc-64" cache
        └── gets object from slab page
              └── marks slot as ALLOCATED
                    └── returns pointer

kfree(ptr)
  └── SLUB finds slab page for ptr
        └── marks slot as FREE
              └── available for next kmalloc

Missing kfree()
  └── slot stays ALLOCATED forever
        └── memory never returned to system
              └── leak grows with each load/unload cycle
```

### kmemleak — How It Works

```
kmalloc() called
  └── kmemleak records: {address, size, backtrace}
        └── adds to "allocated objects" list

kfree() called
  └── kmemleak removes entry from list

echo scan > /sys/kernel/debug/kmemleak
  └── kmemleak scans all memory for pointers
        └── any allocated object with NO pointer
              referencing it = unreferenced = LEAK
                    └── reported in kmemleak file

Output shows:
  - address of leaked object
  - size
  - hex dump of content
  - full backtrace to kmalloc call site
```

---

## Environment

| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| Module | sensor_driver_memleak.ko |
| DTS node | kotesh-sensor-chardev@20014000 (reused) |
| Leak size | 64 bytes (kmalloc-128 slab cache) |
| Detector | kmemleak (`CONFIG_DEBUG_KMEMLEAK=y`) |

---

## Symptom (Log Snippet)

```
root@qemuarm64:~# insmod /home/root/sensor_driver_memleak.ko
[  271.024334] Sensor MemLeak [PROBE]: probe() called!
[  271.024914] Sensor MemLeak [BUG]: kmalloc(64) at (____ptrval____) — no kfree in remove!
[  271.029953] Sensor MemLeak [PROBE]: Ready

root@qemuarm64:~# rmmod sensor_driver_memleak
[  276.481951] Sensor MemLeak [PROBE]: remove() called! buf NOT freed!

root@qemuarm64:~# grep MemFree /proc/meminfo
MemFree: 948460 kB    ← same before and after unload — 64 bytes never returned

root@qemuarm64:~# cat /sys/kernel/debug/kmemleak
unreferenced object 0xffffff8004a9ce80 (size 128):
  comm "insmod", pid 283, jiffies 4294936003 (age 101.456s)
  hex dump (first 32 bytes):
    73 65 6e 73 6f 72 5f 64 61 74 61 5f 76 61 6c 75  sensor_data_valu
    65 3d 34 32 00 00 00 00 00 00 00 00 00 00 00 00  e=42............
  backtrace:
    [<(____ptrval____)>] kmem_cache_alloc_trace+0x3e8/0x680
    [<(____ptrval____)>] sensor_probe+0x60/0xc0 [sensor_driver_memleak]
    [<(____ptrval____)>] platform_probe+0x70/0xf0
    [<(____ptrval____)>] really_probe.part.0+0x94/0x310
    [<(____ptrval____)>] do_one_initcall+0x68/0x2c0
    [<(____ptrval____)>] load_module+0x22b4/0x29f0
```

**Key observations:**
- `unreferenced object` — pointer to buf lost after module unloaded
- `size 128` — SLUB rounds 64→128 (next power-of-2 cache size)
- hex dump shows `sensor_data_valu e=42` — actual content of leaked buffer
- `sensor_probe+0x60` — exact offset in probe() where kmalloc was called
- `1 new suspected memory leaks` — kmemleak detected it immediately

---

## Stage Identification

```
insmod sensor_driver_memleak.ko
  └── sensor_probe() called
        ├── devm_kzalloc(sizeof(*sdev))   → auto-managed    ✔
        ├── kmalloc(64, GFP_KERNEL)       → sdev->buf       ✔ allocated
        │     └── kmemleak records: {0xffffff8004a9ce80, 128, backtrace}
        └── probe returns 0

rmmod sensor_driver_memleak
  └── sensor_remove() called
        ├── pr_info "buf NOT freed!"
        └── returns 0  ← sdev->buf NEVER freed
              └── devm cleanup frees sdev (struct)
                    └── BUT sdev->buf pointer is GONE
                          └── 64 bytes unreachable forever
                                └── kmemleak: LEAK DETECTED
```

---

## Buggy Code

```c
static int sensor_probe(struct platform_device *pdev)
{
    struct sensor_dev *sdev;

    sdev = devm_kzalloc(&pdev->dev, sizeof(*sdev), GFP_KERNEL);

    /* BUG: kmalloc — never freed in remove() */
    sdev->buf = kmalloc(LEAK_SIZE, GFP_KERNEL);
    snprintf(sdev->buf, LEAK_SIZE, "sensor_data_value=%d", sdev->value);

    platform_set_drvdata(pdev, sdev);
    return 0;
}

static int sensor_remove(struct platform_device *pdev)
{
    /* BUG: sdev->buf never freed here */
    pr_info("Sensor MemLeak [PROBE]: remove() called! buf NOT freed!\n");
    return 0;
}
```

---

## Fix (Applied in Ex2)

```c
static int sensor_remove(struct platform_device *pdev)
{
    struct sensor_dev *dev = platform_get_drvdata(pdev);
    kfree(dev->buf);        /* FIXED: free kmalloc buffer */
    dev->buf = NULL;        /* prevent use-after-free */
    pr_info("Sensor MemLeak [FIXED]: buf freed in remove()\n");
    return 0;
}
```

**Or better — use devm_ from the start:**
```c
/* In probe() — auto-freed on remove, no kfree needed */
sdev->buf = devm_kzalloc(&pdev->dev, LEAK_SIZE, GFP_KERNEL);
```

---

## Reproduction Steps

```bash
# HOST — Build driver
cd ~/30days_workWith_BSP/my_projects/ch06_memleak
make clean && make

# Deploy
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp sensor_driver_memleak.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount

~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU

# Step 1 — clear kmemleak baseline
echo clear > /sys/kernel/debug/kmemleak

# Step 2 — load driver (triggers kmalloc)
insmod /home/root/sensor_driver_memleak.ko
dmesg | grep "Sensor MemLeak" | tail -5

# Step 3 — scan WHILE module loaded
echo scan > /sys/kernel/debug/kmemleak
sleep 3
echo scan > /sys/kernel/debug/kmemleak

# Step 4 — check leak BEFORE unload
cat /sys/kernel/debug/kmemleak
# Expected: unreferenced object with sensor_probe backtrace

# Step 5 — check memory
grep MemFree /proc/meminfo

# Step 6 — unload
rmmod sensor_driver_memleak
dmesg | grep "Sensor MemLeak" | tail -3

# Step 7 — check memory after unload
grep MemFree /proc/meminfo
# Expected: same value — 64 bytes never returned

# Step 8 — scan after unload
echo scan > /sys/kernel/debug/kmemleak
sleep 2
cat /sys/kernel/debug/kmemleak
# Expected: still shows leak — object unreachable
```

---

## What I Checked ✔

```
✔ kmemleak: 1 new suspected memory leaks
  → detected immediately after first scan

✔ unreferenced object 0xffffff8004a9ce80 (size 128)
  → SLUB rounded 64→128 (kmalloc-128 cache)

✔ hex dump: "sensor_data_valu e=42"
  → actual leaked buffer content visible

✔ backtrace: sensor_probe+0x60
  → exact location of kmalloc call in driver

✔ grep MemFree /proc/meminfo
  → same before and after rmmod
  → 64 bytes permanently leaked

✔ kmemleak persists after rmmod
  → object still unreachable even after module removed
```

---

## kmemleak Commands Reference

```bash
# Enable kmemleak (already on if CONFIG_DEBUG_KMEMLEAK=y)
ls /sys/kernel/debug/kmemleak

# Clear all previous leak records
echo clear > /sys/kernel/debug/kmemleak

# Trigger manual scan
echo scan > /sys/kernel/debug/kmemleak

# View detected leaks
cat /sys/kernel/debug/kmemleak

# Dump all objects (including non-leaked)
echo dump=0xADDRESS > /sys/kernel/debug/kmemleak

# Disable kmemleak temporarily
echo off > /sys/kernel/debug/kmemleak
```

---

## Interview Explanation

> "The driver allocated a 64-byte buffer with `kmalloc()` in `probe()` but never
> called `kfree()` in `remove()`. I detected this using `kmemleak` — after loading
> and unloading the driver, `cat /sys/kernel/debug/kmemleak` showed an unreferenced
> object with a backtrace pointing to `sensor_probe+0x60`. The hex dump even showed
> the actual leaked content `sensor_data_value=42`. SLUB rounded the 64-byte request
> to the `kmalloc-128` cache, so 128 bytes were actually leaked. The fix is either
> adding `kfree(dev->buf)` in `remove()`, or better, using `devm_kzalloc()` which
> auto-frees on device removal."

---

## Key Learning

- Every `kmalloc()` in `probe()` needs a matching `kfree()` in `remove()`
- SLUB rounds allocation sizes to power-of-2 cache sizes (64→128, 100→128)
- `kmemleak` shows: address, size, hex dump, and exact backtrace to leaking call
- Scan kmemleak WHILE module is loaded — after rmmod backtrace loses symbol names
- `devm_kzalloc()` is preferred — auto-freed on remove, no manual kfree needed
- Memory leak doesn't crash — it silently exhausts RAM over time
- In production drivers, repeated load/unload cycles accumulate leaks
- `CONFIG_DEBUG_KMEMLEAK=y` must be enabled in kernel config
