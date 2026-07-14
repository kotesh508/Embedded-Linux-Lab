# Issue 07 — Ex4: dump_stack() + Stack Depth Reporter

## Chapter
Ch07 — Stack Overflow

## Exercise
Ex4 — Use `dump_stack()` and `current_stack_pointer` to measure remaining
stack at runtime and print the full kernel call trace from a driver.

---

## Theory Background

### dump_stack() — What It Does

```c
dump_stack();
```
Prints the current CPU call trace to the kernel log — same format as a panic
backtrace but without crashing. Used by BSP engineers to:
- Understand which path led to a driver function
- Debug unexpected probe() call sequences
- Verify IRQ context vs process context
- Document call depth in bug reports

### current_stack_pointer — Measuring Stack Usage

```c
unsigned long sp = current_stack_pointer;         // current SP register
unsigned long base = task_stack_page(current);     // bottom of stack
unsigned long remaining = sp - base;               // bytes left
```

```
Stack layout (arm64):
  High address: stack top   (0xc024000)
                ┌──────────┐
                │ used area │  ← grows downward
                ├──────────┤  ← current SP
                │ free area │  remaining = SP - base
                └──────────┘
  Low address:  stack base  (0xc020000)  ← task_stack_page()

THREAD_SIZE = 16384 bytes (16KB)
```

### Why Compiler Inlines Small Functions

In Ex4, level1/level2/level3 all show the same remaining stack value.
This is because GCC inlines small functions — no separate stack frame
is created. To force separate frames, use `noinline`:

```c
static noinline void level3(void) { ... }
static noinline void level2(void) { ... }
```

---

## Environment

| Item | Value |
|------|-------|
| Board | QEMU qemuarm64 |
| Kernel | 5.15.194-yocto-standard |
| Driver | sensor_driver_stack_ex4.ko |
| Stack size | 16384 bytes (16KB) |

---

## Reproduce Steps

### Step 1 — Create driver

```bash
cd ~/30days_workWith_BSP/my_projects/ch07_stackoverflow

cat > sensor_driver_stack_ex4.c << 'EOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/slab.h>

#define THREAD_SIZE_BYTES  16384

static const struct of_device_id sensor_stack_ids[] = {
    { .compatible = "kotesh,sensor-chardev" }, { }
};
MODULE_DEVICE_TABLE(of, sensor_stack_ids);

static unsigned long stack_remaining(void)
{
    unsigned long sp   = current_stack_pointer;
    unsigned long base = (unsigned long)task_stack_page(current);
    return (sp > base) ? sp - base : 0;
}

static void level3(void)
{
    pr_info("Sensor Stack [DEPTH-3]: remaining stack = %lu bytes (%lu KB)\n",
            stack_remaining(), stack_remaining() / 1024);
    dump_stack();
}
static void level2(void) {
    pr_info("Sensor Stack [DEPTH-2]: remaining stack = %lu bytes\n", stack_remaining());
    level3();
}
static void level1(void) {
    pr_info("Sensor Stack [DEPTH-1]: remaining stack = %lu bytes\n", stack_remaining());
    level2();
}

static int sensor_probe(struct platform_device *pdev)
{
    unsigned long rem = stack_remaining();
    pr_info("Sensor Stack [PROBE]: probe() called!\n");
    pr_info("Sensor Stack [PROBE]: stack total=%d bytes, remaining=%lu bytes (%lu%%)\n",
            THREAD_SIZE_BYTES, rem, (rem * 100) / THREAD_SIZE_BYTES);
    level1();
    pr_info("Sensor Stack [PROBE]: Ready — dump_stack() demonstrated\n");
    return 0;
}

static int sensor_remove(struct platform_device *pdev) {
    pr_info("Sensor Stack [PROBE]: remove() called!\n");
    return 0;
}

static struct platform_driver sensor_stack_ex4_driver = {
    .probe = sensor_probe, .remove = sensor_remove,
    .driver = { .name = "sensor_stack",
                .of_match_table = of_match_ptr(sensor_stack_ids) },
};
module_platform_driver(sensor_stack_ex4_driver);
MODULE_LICENSE("GPL"); MODULE_AUTHOR("Kotesh S");
MODULE_DESCRIPTION("Ch07 Ex4 - dump_stack() + stack depth reporter");
EOF

# Update Makefile
sed -i 's/sensor_driver_stack.o/sensor_driver_stack_ex4.o/' Makefile
make clean && make
echo "Build: $?"
```

### Step 2 — Deploy

```bash
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 /tmp/qemu-mount
sudo cp sensor_driver_stack_ex4.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh
```

### Step 3 — Test in QEMU

```bash
insmod /home/root/sensor_driver_stack_ex4.ko
dmesg | grep -E "Sensor Stack|Call trace" | tail -10
dmesg | grep -A 20 "DEPTH-3" | tail -25
rmmod sensor_driver_stack_ex4
dmesg | grep "Sensor Stack" | tail -3
```

---

## Actual Output

```
[ 1015.999743] Sensor Stack [PROBE]: probe() called!
[ 1016.000820] Sensor Stack [PROBE]: stack total=16384 bytes, remaining=14608 bytes (89%)
[ 1016.001466] Sensor Stack [DEPTH-1]: remaining stack = 14608 bytes
[ 1016.001839] Sensor Stack [DEPTH-2]: remaining stack = 14608 bytes
[ 1016.002194] Sensor Stack [DEPTH-3]: remaining stack = 14608 bytes (14 KB)
[ 1016.002775] CPU: 0 PID: 285 Comm: insmod Tainted: G      D    O      5.15.194-yocto-standard #1
[ 1016.004120] Call trace:
[ 1016.004262]  dump_backtrace+0x0/0x1a0
[ 1016.004509]  show_stack+0x20/0x30
[ 1016.004716]  dump_stack_lvl+0x7c/0xa0
[ 1016.004944]  dump_stack+0x18/0x34
[ 1016.005169]  sensor_probe+0xb0/0xd0 [sensor_driver_stack_ex4]
[ 1016.005510]  platform_probe+0x70/0xf0
[ 1016.005728]  really_probe.part.0+0x94/0x310
[ 1016.005973]  __driver_probe_device+0xa0/0x180
[ 1016.006219]  driver_probe_device+0x4c/0x130
[ 1016.006458]  __driver_attach+0x9c/0x1a0
[ 1016.006682]  bus_for_each_dev+0x7c/0xe0
[ 1016.006902]  driver_attach+0x2c/0x40
[ 1016.007111]  bus_add_driver+0x114/0x210
[ 1016.007325]  driver_register+0x80/0x140
[ 1016.007551]  __platform_driver_register+0x2c/0x40
[ 1016.007814]  sensor_stack_ex4_driver_init+0x28/0x1000 [sensor_driver_stack_ex4]
[ 1016.008216]  do_one_initcall+0x68/0x2c0
[ 1016.008438]  do_init_module+0x50/0x260
[ 1016.008666]  load_module+0x22b4/0x29f0
[ 1016.018697] Sensor Stack [PROBE]: Ready — dump_stack() demonstrated
[ 1016.779778] Sensor Stack [PROBE]: remove() called!
```

---

## Analysis

### Stack Usage at probe() entry

```
Total stack:      16384 bytes (16KB)
Remaining:        14608 bytes (89%)
Used by chain:     1776 bytes = insmod → finit_module → load_module
                               → do_init_module → do_one_initcall
                               → platform_probe → sensor_probe
```

### Why All Depths Show Same Value

```
level1/level2/level3 all show 14608 bytes — same as probe().
Reason: GCC inlined these small functions — no separate stack frame.
Compiler optimization: functions with no loops/complex logic get inlined.

To force separate frames (for demonstration):
  static noinline void level3(void) { ... }
  static noinline void level2(void) { ... }
  → Each would then consume ~80-100 bytes for saved registers
```

### Call Trace Reading Guide

```
dump_stack+0x18          ← where dump_stack() was called from
sensor_probe+0xb0        ← offset 0xb0 inside sensor_probe = line ~35
platform_probe+0x70      ← kernel calls probe() via function pointer
really_probe.part.0      ← core driver probe logic
__driver_probe_device    ← driver core: device matched to driver
driver_probe_device      ← called per device during bind
__driver_attach          ← iterates all devices for this driver
bus_for_each_dev         ← walks platform bus device list
driver_attach            ← entry: attach driver to all matching devices
bus_add_driver           ← called when driver module loads
driver_register          ← module_platform_driver() calls this
sensor_stack_ex4_init    ← module_init() entry point
do_one_initcall          ← kernel calls each module's init
do_init_module           ← module loader calls init functions
load_module              ← insmod syscall handler
```

---

## Key Takeaways

1. **`dump_stack()`** = non-fatal call trace — use it to understand probe() call path
2. **`current_stack_pointer`** = read SP register — measure remaining stack at any point
3. **`task_stack_page(current)`** = stack base address for current task
4. **89% remaining** at probe entry = 1776 bytes consumed by kernel driver framework
5. **GCC inlines** small functions — use `noinline` to force separate frames for testing
6. **Call trace format:** function+offset/total_size — offset tells you exact instruction

---

## Ch07 Complete Summary

| Ex | Bug/Feature | Key Evidence | Fix/Tool |
|----|-------------|--------------|----------|
| Ex1 | `char buf[8192]` on stack | `-Wframe-larger-than=8208` | `kmalloc()` |
| Ex2 | Recursion 3×8KB=24KB | `kernel stack overflow` panic | Avoid deep recursion |
| Ex3 | Fix with `kmalloc()` | No warning, no panic | heap allocation |
| Ex4 | Stack measurement tool | `remaining=14608 (89%)` + call trace | `dump_stack()` |
