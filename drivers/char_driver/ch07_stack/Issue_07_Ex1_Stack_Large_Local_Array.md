# Issue 07 — Ex1: Large Local Array on Kernel Stack

## Chapter
Ch07 — Stack Overflow

## Exercise
Ex1 — Large local array `char buf[8192]` allocated on kernel stack triggers
`-Wframe-larger-than=` compiler warning and dangerous stack exhaustion.

---

## Theory Background

### Kernel Stack vs Userspace Stack

```
Userspace stack:
  - Grows dynamically on demand
  - Default 8MB, expandable with ulimit -s unlimited
  - OS maps new pages on page fault (guard page mechanism)
  - Overflow → SIGSEGV, process dies cleanly

Kernel stack (arm64):
  - FIXED SIZE: 16KB = 4 pages (THREAD_SIZE = 0x4000)
  - NO dynamic expansion — no guard page growth
  - Overflow → corrupts adjacent kernel memory
  - Result → silent corruption OR kernel panic
  - arm64 has overflow stack (4KB) to catch and panic cleanly
```

### What Lives on the Kernel Stack

```
High address (stack top)
  ┌──────────────────────┐
  │  task_struct + thread │  ← kernel creates this at task creation
  │  info at stack bottom │
  ├──────────────────────┤
  │  sensor_probe() frame │  ← return addr, saved regs (~200 bytes)
  ├──────────────────────┤
  │  char local_buf[8192] │  ← BUG: 8KB local array here!
  ├──────────────────────┤
  │  ... other calls ...  │
  └──────────────────────┘
Low address (stack bottom = 0xxxxxxxc009c20000)
  ← sp goes here → OVERFLOW if below bottom
```

### Stack Frame Size Rule

```
Linux kernel enforces: -Wframe-larger-than=2048
Any function with local variables > 2048 bytes triggers warning.

Why 2KB limit?
  16KB total stack
  Typical call depth: ~8-10 frames
  16KB / 8 frames = 2KB per frame maximum safe budget
```

### arm64 Stack Overflow Detection

```
arm64 has a dedicated "overflow stack" (4KB) mapped separately.
When sp goes below task stack bottom:
  1. CPU takes a stack fault exception
  2. Switches to overflow stack
  3. Kernel prints: "Insufficient stack space to handle exception!"
  4. Prints full register dump + stack ranges
  5. Panics: "kernel stack overflow"
```

---

## Bug Description

**File:** `sensor_driver_stack.c`
**Root Cause:** `char local_buf[8192]` declared as a local variable inside
`sensor_probe()`. This allocates 8192 bytes on the kernel stack at function
entry, consuming 50% of the 16KB stack in a single frame.

---

## Environment

| Item | Value |
|------|-------|
| Board | QEMU qemuarm64 |
| Kernel | 5.15.194-yocto-standard |
| Distro | Poky 4.0.32 |
| Driver | sensor_driver_stack.ko |
| Stack size | 16KB (THREAD_SIZE = 0x4000) |

---

## Reproduce Steps

### Step 1 — Create buggy driver

```bash
cd ~/30days_workWith_BSP/my_projects/ch07_stackoverflow

cat > sensor_driver_stack.c << 'EOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/slab.h>

#define STACK_BUF_SIZE  8192   /* BUG: 8KB on 16KB kernel stack */

static const struct of_device_id sensor_stack_ids[] = {
    { .compatible = "kotesh,sensor-chardev" }, { }
};
MODULE_DEVICE_TABLE(of, sensor_stack_ids);

static int sensor_probe(struct platform_device *pdev)
{
    char local_buf[STACK_BUF_SIZE];   /* BUG: 8192 bytes on stack! */

    pr_info("Sensor Stack [PROBE]: probe() called!\n");
    pr_info("Sensor Stack [BUG]: local_buf[%d] on kernel stack!\n", STACK_BUF_SIZE);
    memset(local_buf, 0xAB, STACK_BUF_SIZE);
    snprintf(local_buf, STACK_BUF_SIZE, "sensor_stack_test");
    pr_info("Sensor Stack [BUG]: survived — but stack is dangerously full!\n");
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
MODULE_DESCRIPTION("Ch07 Stack - BUGGY large stack allocation");
EOF
```

### Step 2 — Build (compiler warning is the first evidence)

```bash
make clean && make
echo "Build: $?"
```

### Step 3 — Deploy and test in QEMU

```bash
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 /tmp/qemu-mount
sudo cp sensor_driver_stack.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh
```

Inside QEMU:
```bash
insmod /home/root/sensor_driver_stack.ko
dmesg | grep "Sensor Stack" | tail -10
dmesg | grep -E "stack overflow|frame size|Insufficient" | tail -5
rmmod sensor_driver_stack
```

---

## Actual Output (Buggy)

### Compiler warning (build time):
```
sensor_driver_stack.c:30:1: warning: the frame size of 8208 bytes is larger
than 2048 bytes [-Wframe-larger-than=]
```

### Runtime (driver survives single frame but stack is 50% consumed):
```
[  279.251446] Sensor Stack [PROBE]: probe() called!
[  279.252795] Sensor Stack [BUG]: local_buf[8192] on kernel stack!
[  279.253367] Sensor Stack [BUG]: survived — but stack is dangerously full!
[  279.253969] Sensor Stack [PROBE]: Ready
```

### Stack analysis:
```
KernelStack before load:  968 kB  (normal baseline)
local_buf[8192] consumes: 8208 bytes = 50% of 16KB stack in ONE frame
Remaining for all other calls: ~7KB — any nested call risks overflow
```

---

## Root Cause Analysis

```
sensor_probe() entry:
  sp = 0xxxxxxxc009c23xxx  (near stack top)

  char local_buf[8192] allocated:
  sp -= 8208  → sp = 0xxxxxxxc009c21xxx  (8KB consumed!)

  Stack window: [0xc020000 .. 0xc024000] = 16KB
  Used after probe entry: 8208 / 16384 = 50%

  Any nested call from here (pr_info, memset, snprintf):
  each adds ~200-500 bytes more → approaches overflow
```

---

## Fix Preview (Ex2)

Move large buffer to heap using `kmalloc()`:

```c
/* FIXED */
char *buf = kmalloc(STACK_BUF_SIZE, GFP_KERNEL);
if (!buf) return -ENOMEM;
/* ... use buf ... */
kfree(buf);
```

Compiler confirms fix — no `-Wframe-larger-than` warning on fixed driver.

---

## Key Takeaways

1. **Never** declare large local arrays in kernel functions — use `kmalloc()`
2. **`-Wframe-larger-than=2048`** is a build-time safety net — treat it as an error
3. **Kernel stack = 16KB fixed** on arm64 — no expansion possible
4. **50% stack usage in one frame** leaves no room for nested calls, IRQ handlers
5. **arm64 overflow stack** catches the panic cleanly but system still crashes
