# Issue 06 — Ex4: devm_ Double Free

## Chapter
Ch06 — Memory Leak / Slab Allocator

## Exercise
Ex4 — Mixing `devm_kzalloc()` with manual `kfree()` causes double free detected by kmemleak

---

## Theory Background

### The devm_ Allocator Family

`devm_` (device-managed) functions automatically tie memory to a device's lifetime:

```
devm_kzalloc(&pdev->dev, size, GFP_KERNEL)
  └── kmalloc internally
        └── registers pointer in device's devres list

device_remove() called
  └── kernel iterates devres list
        └── kfree() called automatically for each registered entry
```

**Rule:** If you use `devm_kzalloc()`, you MUST NOT call `kfree()` manually on that pointer.

### Double Free — What Happens

```
probe():   buf = devm_kzalloc()   → SLUB marks slot ALLOCATED, devres records ptr
remove():  kfree(buf)             → SLUB marks slot FREE  (1st free)
           devres cleanup runs    → kfree(buf) AGAIN      (2nd free — BUG!)

SLUB reaction:
  "This slot is already FREE — something freed it twice!"
  → kmemleak: Found object by alias
  → kernel logs full backtrace
```

### Contrast: devm_ vs Manual

| Pattern | Allocated with | Free in remove() | Safe? |
|---------|---------------|-------------------|-------|
| Manual | `kmalloc()` | `kfree()` | ✅ |
| devm_ | `devm_kzalloc()` | nothing (auto) | ✅ |
| Mixed | `devm_kzalloc()` | `kfree()` | ❌ double free |
| Mixed | `kmalloc()` | nothing | ❌ memory leak |

---

## Bug Description

**File:** `sensor_driver_memleak_ex4.c`  
**Root Cause:** `devm_kzalloc()` used in `probe()` but `kfree()` called manually in `remove()`. When `rmmod` runs, `kfree()` frees the buffer first, then the devres cleanup system frees it again — double free.

---

## Environment

| Item | Value |
|------|-------|
| Board | QEMU qemuarm64 |
| Kernel | 5.15.194-yocto-standard |
| Distro | Poky 4.0.32 |
| Driver | sensor_driver_memleak_ex4.ko |
| Config | CONFIG_DEBUG_KMEMLEAK=y |

---

## Reproduce Steps

### Step 1 — Create buggy driver

```bash
cd ~/30days_workWith_BSP/my_projects/ch06_memleak

cat > sensor_driver_memleak_ex4.c << 'EOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/slab.h>

#define LEAK_SIZE  64

struct sensor_dev {
    int value;
    int threshold;
    char *buf;
};

static const struct of_device_id sensor_memleak_ids[] = {
    { .compatible = "kotesh,sensor-chardev" },
    { }
};
MODULE_DEVICE_TABLE(of, sensor_memleak_ids);

static int sensor_probe(struct platform_device *pdev)
{
    struct sensor_dev *sdev;
    sdev = devm_kzalloc(&pdev->dev, sizeof(*sdev), GFP_KERNEL);
    if (!sdev) return -ENOMEM;

    /* BUG: devm_kzalloc — devres will auto-free on remove */
    sdev->buf = devm_kzalloc(&pdev->dev, LEAK_SIZE, GFP_KERNEL);
    if (!sdev->buf) return -ENOMEM;

    sdev->value = 42;
    sdev->threshold = 100;
    snprintf(sdev->buf, LEAK_SIZE, "sensor_data_value=%d", sdev->value);
    platform_set_drvdata(pdev, sdev);
    pr_info("Sensor MemLeak Ex4 [PROBE]: Ready, buf=%p\n", sdev->buf);
    return 0;
}

static int sensor_remove(struct platform_device *pdev)
{
    struct sensor_dev *dev = platform_get_drvdata(pdev);
    /* BUG: manual kfree on devm_ pointer — double free! */
    pr_info("Sensor MemLeak Ex4 [BUG]: kfree(devm_ ptr) — double free!\n");
    kfree(dev->buf);  /* devres will ALSO free this */
    pr_info("Sensor MemLeak Ex4 [PROBE]: remove() called!\n");
    return 0;
}

static struct platform_driver sensor_memleak_ex4_driver = {
    .probe  = sensor_probe,
    .remove = sensor_remove,
    .driver = {
        .name           = "sensor_memleak",
        .of_match_table = of_match_ptr(sensor_memleak_ids),
    },
};
module_platform_driver(sensor_memleak_ex4_driver);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Kotesh S");
MODULE_DESCRIPTION("Ch06 Ex4 MemLeak - BUGGY devm_ double free");
EOF
```

### Step 2 — Fix Makefile and build

```bash
sed -i 's/sensor_driver_memleak_ex3.o/sensor_driver_memleak_ex4.o/' Makefile
make clean && make
echo "Build: $?"
```

### Step 3 — Deploy to rootfs

```bash
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 /tmp/qemu-mount
sudo cp ~/30days_workWith_BSP/my_projects/ch06_memleak/sensor_driver_memleak_ex4.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
```

### Step 4 — Boot QEMU and reproduce

```bash
~/BSP-Lab/boot_qemu.sh
```

Inside QEMU:
```bash
insmod /home/root/sensor_driver_memleak_ex4.ko
dmesg | grep "Ex4" | tail -5
rmmod sensor_driver_memleak_ex4
dmesg | grep -E "Ex4|kmemleak|double free" | tail -30
```

---

## Actual Output (Buggy)

```
[  237.417820] Sensor MemLeak Ex4 [PROBE]: probe() called!
[  237.421627] Sensor MemLeak Ex4 [PROBE]: Ready, buf=(____ptrval____)
[  237.937543] Sensor MemLeak Ex4 [BUG]: kfree(devm_ ptr) — double free!
[  237.938642] kmemleak: Found object by alias at 0xffffff80049b5e80
[  237.939448] CPU: 0 PID: 287 Comm: rmmod Tainted: G      D    O      5.15.194-yocto-standard #1
[  237.940802] Call trace:
[  237.941097]  dump_backtrace+0x0/0x1a0
[  237.944230]  kfree+0x130/0x520
[  237.944951]  sensor_remove+0x34/0x54 [sensor_driver_memleak_ex4]
[  237.945461]  platform_remove+0x5c/0x80
...
[  237.951601] kmemleak: Object 0xffffff80049b5e00 (size 256):
[  237.952102] kmemleak:   comm "insmod", pid 283
[  237.954652]      devm_kmalloc+0x58/0x120
[  237.955644]      sensor_probe+0x5c/0xac [sensor_driver_memleak_ex4]
[  237.970589] Sensor MemLeak Ex4 [PROBE]: remove() called!
```

### What kmemleak Detected

| Field | Value | Meaning |
|-------|-------|---------|
| Object | `0xffffff80049b5e00` (size 256) | devm_ allocated buffer |
| Alias | `0xffffff80049b5e80` | kfree passed +0x80 offset |
| Allocated at | `sensor_probe+0x5c` | devm_kzalloc call |
| Freed at | `sensor_remove+0x34` | manual kfree — wrong! |

**kmemleak reports "Found object by alias"** — kfree received a pointer that is not at the start of the allocated object (SLUB tracks object start addresses, not offsets).

---

## Root Cause Analysis

```
probe():
  sdev->buf = devm_kzalloc(&pdev->dev, LEAK_SIZE)
              └── internally calls kmalloc + registers in devres list
                  Object start: 0xffffff80049b5e00

remove():
  kfree(dev->buf)   ← dev->buf is devm_ pointer
  └── SLUB: marks slot FREE at 0xffffff80049b5e00 (1st free)
  └── kmemleak: "Found object by alias" — warns about wrong free

  devres cleanup (after remove() returns):
  └── kfree(devm_ ptr) AGAIN
  └── SLUB: slot already FREE → double free corruption
```

---

## Fix — Remove Manual kfree

```bash
# On host — fix sensor_remove(): remove the kfree line
sed -i '/kfree(dev->buf)/d' sensor_driver_memleak_ex4.c
sed -i 's/\[BUG\]: kfree(devm_ ptr) — double free!/[FIXED]: devm_ ptr — devres will auto-free/' sensor_driver_memleak_ex4.c
sed -i 's/BUGGY devm_ double free/FIXED devm_ auto-free/' sensor_driver_memleak_ex4.c
grep -n "kfree\|BUG\|FIXED" sensor_driver_memleak_ex4.c
```

**Fixed remove():**
```c
static int sensor_remove(struct platform_device *pdev)
{
    /* FIXED: no kfree needed — devm_ auto-frees on device removal */
    pr_info("Sensor MemLeak Ex4 [FIXED]: devm_ auto-free on remove\n");
    pr_info("Sensor MemLeak Ex4 [PROBE]: remove() called!\n");
    return 0;
}
```

---

## Verified Output (Fixed)

```
[  274.115213] Sensor MemLeak Ex4 [PROBE]: probe() called!
[  274.115987] Sensor MemLeak Ex4 [FIXED]: devm_ ptr — devres will auto-free
[  274.116433] Sensor MemLeak Ex4 [PROBE]: Ready
[  279.071544] Sensor MemLeak Ex4 [FIXED]: devm_ auto-free on remove
[  279.073001] Sensor MemLeak Ex4 [PROBE]: remove() called!
```

kmemleak scan after fix:
```
root@qemuarm64:~# cat /sys/kernel/debug/kmemleak
root@qemuarm64:~#   ← empty = no leaks ✅
```

---

## Summary Table — All Ch06 Memory Patterns

| Ex | Bug | Allocator | Detection | Fix |
|----|-----|-----------|-----------|-----|
| Ex1 | kmalloc, no kfree | SLUB slab | kmemleak backtrace | kfree in remove() |
| Ex2 | Fixed Ex1 | SLUB slab | kmemleak empty | ✅ |
| Ex3 | kfree(ptr+8) | SLUB slab | kmemleak alias | kfree(original ptr) |
| Ex4 | devm_ + kfree | devres+SLUB | kmemleak alias | remove manual kfree |

---

## Key Takeaways

1. **Never mix** `devm_` allocations with manual `kfree()` — devres handles cleanup automatically
2. **devm_ lifetime** = device lifetime; freed when driver unbinds or device is removed
3. **kmemleak "alias"** = kfree received a pointer that is not the start of an allocated object
4. **Rule of thumb:** if you see `devm_` in probe, there should be NO matching `kfree` in remove for that pointer
5. **kmemleak backtrace** always shows both: where memory was allocated AND where it was wrongly freed
