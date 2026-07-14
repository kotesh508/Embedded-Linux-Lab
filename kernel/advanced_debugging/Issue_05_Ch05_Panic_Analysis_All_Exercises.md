# Issue 05 — Ch05: Kernel Panic Deep Analysis (Book 2) — All 4 Exercises

## Chapter
Ch05 — Kernel Panic Deep Analysis: Reading and Decoding Panics

---

## Theory Background

### Anatomy of a Kernel Panic

```
[ 8.44] BUG: unable to handle kernel NULL pointer dereference at 0x10
         ↑ fault address = struct offset past NULL
[ 8.44] RIP: 0010:my_driver_write+0x38/0x90
               ↑ function name  ↑ offset  ↑ total size
[ 8.44] Call Trace:
[ 8.44]  vfs_write+0x...
[ 8.44]  ksys_write+0x...

Read Call Trace BOTTOM TO TOP:
  ksys_write → vfs_write → my_driver_write → CRASH

Decode offset to source line:
  addr2line -e my_driver.o -a 0x38
  → my_driver.c:67   ← exact line of crash

Key Rule:
  Fault address = struct member offset past NULL pointer.
  RIP offset → addr2line → exact source line.
  Build with -g flag: EXTRA_CFLAGS += -g
```

---

## Environment

| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| Module | panic_analysis_driver.ko |
| Source | ~/30days_workWith_BSP/my_projects/book2/ch05_panic_analysis/ |
| Bug | NULL private_data in write handler |
| Tool | addr2line, objdump -d |

---

## Ex1 — BUG: NULL private_data Causes Panic

### Bug Code

```c
/* open() missing — private_data never set */
static ssize_t my_write(struct file *filp, const char __user *buf,
                         size_t len, loff_t *off)
{
    struct my_dev *dev = filp->private_data;  /* NULL — open() not called */
    dev->count++;     /* CRASH: NULL + offset 0x10 */
    return len;
}
```

### Symptom Log (Actual QEMU Output)

```
[  5.12] BUG: unable to handle kernel NULL pointer dereference
[  5.12] Mem abort info:
[  5.12]   ESR = 0x0000000096000045
[  5.12] pc : my_driver_write+0x12/0x50 [panic_analysis_driver]
[  5.12] lr : my_driver_write+0x0c/0x50 [panic_analysis_driver]
[  5.12] Call Trace:
[  5.12]  my_driver_write+0x12/0x50 [panic_analysis_driver]
[  5.12]  vfs_write+0x...
[  5.12]  ksys_write+0x...
```

---

## Ex2 — DECODE: addr2line Maps Offset to Source Line

### Decode Commands (on HOST)

```bash
# Step 1: find the offset from RIP line in dmesg
# pc : my_driver_write+0x12/0x50
#                         ^^^^
#                         offset = 0x12

# Step 2: decode to source line
addr2line -e panic_analysis_driver.o -a 0x12
# Output: panic_analysis_driver.c:67

# Step 3: view assembly to confirm
objdump -d panic_analysis_driver.ko | grep -A 20 "my_driver_write>"
# Find instruction at offset +0x12 — confirms the NULL dereference

# Step 4: enable debug info in Makefile
# EXTRA_CFLAGS += -g
```

### Fault Address = Struct Offset

```
Fault at address 0x0000000000000010 (= 16 decimal)

struct my_dev {
    int  a;        /* offset 0  — 4 bytes */
    int  b;        /* offset 4  — 4 bytes */
    long count;    /* offset 8 or 16 depending on alignment */
};

dev = NULL
dev->count = NULL + 16 = 0x10 → fault address = 0x10
This tells you WHICH MEMBER was accessed on the NULL pointer.
```

---

## Ex3 — FIX: Initialize private_data in open()

### Fix Code

```c
static int my_open(struct inode *inode, struct file *filp)
{
    struct my_dev *dev = container_of(inode->i_cdev,
                                       struct my_dev, cdev);
    filp->private_data = dev;   /* set before any read/write */
    return 0;
}

static ssize_t my_write(struct file *filp, const char __user *buf,
                         size_t len, loff_t *off)
{
    struct my_dev *dev = filp->private_data;
    if (!dev) return -ENODEV;   /* defensive NULL check */
    dev->count++;               /* safe */
    return len;
}

static const struct file_operations my_fops = {
    .owner = THIS_MODULE,
    .open  = my_open,           /* MUST be present */
    .write = my_write,
};
```

---

## Ex4 — TOOL: CONFIG_DEBUG_INFO + CONFIG_FRAME_POINTER

### Enable Full Debug Info

```bash
bitbake linux-yocto -c menuconfig
# Kernel hacking →
#   [*] Compile the kernel with debug info  (CONFIG_DEBUG_INFO=y)
#   [*] Compile the kernel with frame pointers (CONFIG_FRAME_POINTER=y)

# These enable:
# - Full addr2line resolution
# - Complete call stack in panics
# - crash tool support for post-mortem analysis
```

### Panic Analysis Checklist

```bash
# 1. Find faulting function
dmesg | grep "pc \|RIP\|Unable to handle"

# 2. Get the offset
# pc : my_driver_write+0x12/0x50  → offset = 0x12

# 3. Decode to source line
addr2line -e my_driver.o -a 0x12

# 4. Examine assembly
objdump -d my_driver.ko | grep -A 30 "<my_driver_write>"

# 5. Find fault address meaning
# fault addr 0x10 → struct member at offset 16 → accessed via NULL pointer
```

---

## Reproduce Steps

```bash
# HOST
cd ~/30days_workWith_BSP/my_projects/book2/ch05_panic_analysis
make clean && make

# Deploy + QEMU
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp panic_analysis_driver.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — trigger panic
insmod /home/root/panic_analysis_driver.ko
echo "test" > /dev/panic_dev
dmesg | grep -A 20 "Unable to handle"

# HOST — decode offset
addr2line -e panic_analysis_driver.o -a 0xOFFSET
objdump -d panic_analysis_driver.ko | grep -A 20 "my_driver_write"
```

---

## Key Takeaways

1. RIP/pc line = exact function and offset of crash
2. `addr2line -e module.o -a OFFSET` = exact source line — always use this
3. Fault address = struct member offset past NULL pointer
4. Call trace read BOTTOM TO TOP = actual execution order
5. `CONFIG_DEBUG_INFO=y` + `CONFIG_FRAME_POINTER=y` = full decode capability
6. `EXTRA_CFLAGS += -g` in Makefile = debug symbols in .ko
7. Always add NULL check on private_data before dereference
