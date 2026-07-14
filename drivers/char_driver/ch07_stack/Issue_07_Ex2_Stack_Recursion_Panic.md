# Issue 07 — Ex2: Deep Recursion Causes Kernel Stack Overflow + Panic

## Chapter
Ch07 — Stack Overflow

## Exercise
Ex2 — Recursive function with 8KB local array per frame. depth=2 creates
3 frames × 8208 bytes = 24KB > 16KB kernel stack → kernel panic.

---

## Theory Background

### Stack Frame Growth with Recursion

```
Each recursive call pushes a NEW frame onto the stack:

  probe() calls recursive_fill(2):
  ┌─────────────────────────┐ sp = 0xc23920  (stack top area)
  │ probe() frame ~200B      │
  ├─────────────────────────┤
  │ recursive_fill(2)        │
  │   char buf[8192]         │ sp -= 8208 → 0xc21910
  ├─────────────────────────┤
  │ recursive_fill(1)        │
  │   char buf[8192]         │ sp -= 8208 → 0xc1f700  ← BELOW stack bottom!
  ├─────────────────────────┤  Stack bottom = 0xc20000
  │ [OVERFLOW TERRITORY]     │  sp is now 0x1300 bytes PAST bottom
  └─────────────────────────┘
         ↑
    arm64 overflow stack catches here
    "Insufficient stack space to handle exception!"
    "Kernel panic - not syncing: kernel stack overflow"
```

### arm64 Stack Layout at Panic

```
Task stack:     [0xffffffc009c20000..0xffffffc009c24000]  ← 16KB window
IRQ stack:      [0xffffffc008000000..0xffffffc008004000]  ← separate 16KB
Overflow stack: [0xffffff803fdc22c0..0xffffff803fdc32c0]  ← 4KB catch region

sp at depth=2:  0xffffffc009c21918  ← still inside task stack (OK)
sp at depth=1:  0xffffffc009c1f8c0  ← BELOW 0xc20000 by 0x1340 (4928 bytes!)
                                       overflow stack activated → panic
```

---

## Bug Description

**File:** `sensor_driver_stack.c` (recursive version)
**Root Cause:** `recursive_fill()` declares `char local_buf[8192]` as a local
variable AND calls itself recursively. Each recursion level consumes 8208 bytes
of kernel stack. depth=2 means 3 total frames × 8208 = 24624 bytes > 16384
bytes (16KB kernel stack) → overflow stack hit → kernel panic.

---

## Environment

| Item | Value |
|------|-------|
| Board | QEMU qemuarm64 |
| Kernel | 5.15.194-yocto-standard |
| Driver | sensor_driver_stack.ko (recursive version) |
| Stack size | 16KB = `[0xc020000..0xc024000]` |
| Overflow stack | 4KB at `0xffffff803fdc22c0` |

---

## Reproduce Steps

### Step 1 — Create recursive buggy driver

```bash
cd ~/30days_workWith_BSP/my_projects/ch07_stackoverflow

cat > sensor_driver_stack.c << 'EOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/slab.h>

#define STACK_BUF_SIZE  8192

static const struct of_device_id sensor_stack_ids[] = {
    { .compatible = "kotesh,sensor-chardev" }, { }
};
MODULE_DEVICE_TABLE(of, sensor_stack_ids);

/* BUG: recursive function — each call adds 8KB to stack */
static int recursive_fill(int depth, char *marker)
{
    char local_buf[STACK_BUF_SIZE];   /* 8KB per frame */
    memset(local_buf, 0xAB, sizeof(local_buf));
    pr_info("Sensor Stack [RECURSE]: depth=%d sp=%px\n", depth, &local_buf);
    if (depth > 0)
        return recursive_fill(depth - 1, local_buf);
    return 0;
}

static int sensor_probe(struct platform_device *pdev)
{
    pr_info("Sensor Stack [PROBE]: probe() called!\n");
    pr_info("Sensor Stack [BUG]: starting recursion — each frame = %d bytes!\n",
            STACK_BUF_SIZE);
    /* depth=2 → 3 frames × 8KB = 24KB > 16KB kernel stack */
    recursive_fill(2, NULL);
    pr_info("Sensor Stack [PROBE]: Ready\n");
    return 0;
}

static int sensor_remove(struct platform_device *pdev) {
    pr_info("Sensor Stack [PROBE]: remove() called!\n");
    return 0;
}

static struct platform_driver sensor_stack_driver = {
    .probe = sensor_probe, .remove = sensor_remove,
    .driver = { .name = "sensor_stack",
                .of_match_table = of_match_ptr(sensor_stack_ids) },
};
module_platform_driver(sensor_stack_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Ch07 Stack - BUGGY deep recursion overflow");
EOF

make clean && make
echo "Build: $?"
```

### Step 2 — Deploy

```bash
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 /tmp/qemu-mount
sudo cp sensor_driver_stack.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh
```

### Step 3 — Trigger panic in QEMU

```bash
insmod /home/root/sensor_driver_stack.ko
# QEMU will freeze — kernel panic, no recovery
# Press Ctrl+A then X to kill QEMU
```

---

## Actual Panic Output

```
[  208.722962] Sensor Stack [PROBE]: probe() called!
[  208.723684] Sensor Stack [BUG]: starting recursion — each frame = 8192 bytes!
[  208.724202] Sensor Stack [RECURSE]: depth=2 sp=ffffffc009c21918
[  208.725239] Insufficient stack space to handle exception!
[  208.725438] ESR: 0x0000000096000047 -- DABT (current EL)
[  208.725513] FAR: 0xffffffc009c1f8c0
[  208.725564] Task stack:     [0xffffffc009c20000..0xffffffc009c24000]
[  208.725587] IRQ stack:      [0xffffffc008000000..0xffffffc008004000]
[  208.725609] Overflow stack: [0xffffff803fdc22c0..0xffffff803fdc32c0]
[  208.725725] pc : recursive_fill.constprop.0.isra.0+0x1c/0x98 [sensor_driver_stack]
[  208.725816] sp : ffffffc009c1f8c0
[  208.726670] Kernel panic - not syncing: kernel stack overflow
[  208.727340] Memory Limit: none
[  208.735439] ---[ end Kernel panic - not syncing: kernel stack overflow ]---
```

### Stack Math

| Point | Stack Pointer | Status |
|-------|--------------|--------|
| Stack bottom | `0xffffffc009c20000` | boundary |
| Stack top | `0xffffffc009c24000` | +16KB |
| sp at depth=2 | `0xffffffc009c21918` | inside — OK |
| sp at depth=1 | `0xffffffc009c1f8c0` | **4928 bytes BELOW bottom** |
| Overflow stack | `0xffffff803fdc22c0` | caught here → panic |

---

## Fix — Use kmalloc for Large Buffers

```bash
# Fix: replace local array with heap allocation
cat > sensor_driver_stack.c << 'EOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/slab.h>

#define STACK_BUF_SIZE  8192

static const struct of_device_id sensor_stack_ids[] = {
    { .compatible = "kotesh,sensor-chardev" }, { }
};
MODULE_DEVICE_TABLE(of, sensor_stack_ids);

static int sensor_probe(struct platform_device *pdev)
{
    char *buf;   /* FIXED: pointer on stack (8 bytes), buffer on heap */

    pr_info("Sensor Stack [PROBE]: probe() called!\n");

    buf = kmalloc(STACK_BUF_SIZE, GFP_KERNEL);
    if (!buf) {
        pr_err("Sensor Stack: kmalloc failed\n");
        return -ENOMEM;
    }

    memset(buf, 0xAB, STACK_BUF_SIZE);
    snprintf(buf, STACK_BUF_SIZE, "sensor_stack_test");

    pr_info("Sensor Stack [FIXED]: %d bytes on heap (kmalloc) not stack\n",
            STACK_BUF_SIZE);
    pr_info("Sensor Stack [PROBE]: Ready\n");

    kfree(buf);
    return 0;
}

static int sensor_remove(struct platform_device *pdev) {
    pr_info("Sensor Stack [PROBE]: remove() called!\n");
    return 0;
}

static struct platform_driver sensor_stack_driver = {
    .probe = sensor_probe, .remove = sensor_remove,
    .driver = { .name = "sensor_stack",
                .of_match_table = of_match_ptr(sensor_stack_ids) },
};
module_platform_driver(sensor_stack_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Ch07 Stack - FIXED kmalloc instead of stack");
EOF

make clean && make
echo "Build: $?"
# No -Wframe-larger-than warning = fix confirmed at compile time
```

---

## Verified Output (Fixed)

```
[  148.877951] Sensor Stack [PROBE]: probe() called!
[  148.878723] Sensor Stack [FIXED]: 8192 bytes on heap (kmalloc) not stack
[  148.879150] Sensor Stack [PROBE]: Ready
[  149.491049] Sensor Stack [PROBE]: remove() called!
```

```
KernelStack: 968 kB   ← normal, no stack pressure
No -Wframe-larger-than warning at build time ✅
No stack overflow at runtime ✅
```

---

## Summary: Stack Allocation Rules

| Location | Allocator | Max safe size | Use case |
|----------|-----------|---------------|----------|
| Stack | local var | < 256 bytes | small integers, pointers |
| Heap | kmalloc() | < 4MB | buffers, arrays, structs |
| Heap | vmalloc() | large | non-contiguous, > 1MB |
| Device heap | devm_kzalloc() | any | auto-freed on remove |

---

## Key Takeaways

1. **Kernel stack = 16KB fixed** — no expansion, no guard pages
2. **Recursion multiplies** stack usage — each frame adds its local variables
3. **arm64 overflow stack** (4KB) catches overflow and panics cleanly
4. **Rule:** local variables > 256 bytes → use `kmalloc()` instead
5. **Compile-time check:** `-Wframe-larger-than=2048` warns before runtime crash
6. **Fix pattern:** `char buf[N]` → `char *buf = kmalloc(N, GFP_KERNEL)`
