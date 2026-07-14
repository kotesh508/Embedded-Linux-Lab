# Issue 05 — Ch05: Kernel Panic Deep Analysis (Book 2)

## Chapter
Ch05 — Kernel Panic: NULL Pointer via Missing open() in file_operations

---

## Environment

| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194-yocto-standard |
| Module | panic_analysis_driver.ko |
| Source | ~/30days_workWith_BSP/my_projects/book2/ch05_panic_analysis/ |
| Device | /dev/panic_dev |
| Bug | filp->private_data = NULL — open() never called to set it |

---

## Theory Background

### How to Read a Kernel Panic

```
Key lines in panic output:

pc : buggy_write+0x40/0x60 [panic_analysis_driver]
      ↑ function    ↑ offset ↑ total size

Fault address: 0x0000000000000000
  → code accessed memory at address 0x0 = NULL dereference

Call trace (read BOTTOM TO TOP):
  el0t_64_sync
  el0_svc
  invoke_syscall
  __arm64_sys_write
  ksys_write
  vfs_write
  buggy_write   ← YOUR DRIVER — crash happened here

Decode offset to source line (HOST only):
  aarch64-linux-gnu-addr2line -e panic_analysis_driver.o -a 0x40
  → panic_analysis_driver.c:49   (exact line of dev->count++)
```

### Why private_data Is NULL

```
file_operations without .open:
  User calls: open("/dev/panic_dev", O_WRONLY)
  Kernel:     no .open in fops → default open() → private_data stays NULL
  User calls: write("/dev/panic_dev", "test", 4)
  Kernel:     buggy_write() called
              dev = filp->private_data   ← NULL
              dev->count++               ← dereference NULL → PANIC

Fix:
  Add .open = my_open to file_operations
  In my_open(): filp->private_data = dev   ← set BEFORE any write
  In write():   if (!dev) return -ENODEV   ← defensive check
```

---

## Ex1 — BUG: Missing .open — private_data Never Set

### Bug Code

```c
/* BUGGY: no .open in file_operations */
static const struct file_operations buggy_fops = {
    .owner = THIS_MODULE,
    /* NO .open — private_data never initialized */
    .write = buggy_write,
    .read  = common_read,
};

static ssize_t buggy_write(struct file *filp, const char __user *buf,
                            size_t len, loff_t *off)
{
    struct panic_dev *dev = filp->private_data;  /* NULL */

    pr_info("PANIC [BUG]: write called, private_data = %p\n", dev);
    pr_info("PANIC [BUG]: about to dereference NULL pointer...\n");

    dev->count++;   /* CRASH: NULL + offsetof(count) = address 0x0 */
    return len;
}
```

### Actual QEMU Output — BUG Mode

```
root@qemuarm64:~# insmod /home/root/panic_analysis_driver.ko use_fix=0
[  759.312052] PANIC [INIT]: mode=BUG
[  759.312585] PANIC [INIT]: BUG mode — write to /dev/panic_dev will crash!
[  759.317896] PANIC [INIT]: /dev/panic_dev created (major=249)

root@qemuarm64:~# echo "test" > /dev/panic_dev
[  759.346630] PANIC [BUG]: write called, private_data = 0000000000000000
[  759.347614] PANIC [BUG]: about to dereference NULL pointer...
[  759.348409] Unable to handle kernel NULL pointer dereference at virtual address 0000000000000000
[  759.351396] Mem abort info:
[  759.351778]   ESR = 0x0000000096000005
[  759.352220]   EC = 0x25: DABT (current EL), IL = 32 bits
[  759.364407] [0000000000000000] pgd=0000000000000000
[  759.368236] Internal error: Oops: 0000000096000005 [#2] PREEMPT SMP
[  759.375303] pstate: 60000005 (nZCv daif -PAN -UAO -TCO -DIT -SSBS BTYPE=--)
[  759.375885] pc : buggy_write+0x40/0x60 [panic_analysis_driver]
[  759.376386] lr : buggy_write+0x40/0x60 [panic_analysis_driver]
[  759.383515] Call trace:
[  759.383515]  buggy_write+0x40/0x60 [panic_analysis_driver]
[  759.384152]  vfs_write+0xf8/0x2a0
[  759.384555]  ksys_write+0x74/0x110
[  759.384950]  __arm64_sys_write+0x24/0x30
[  759.385416]  invoke_syscall+0x5c/0x130
[  759.386353]  do_el0_svc+0x4c/0xc0
[  759.386749]  el0_svc+0x28/0x80
[  759.388315] Code: 95fe5cc4 b0000000 9100c000 95fe5cc1 (b9400261)
[  759.389150] ---[ end trace 3f966d2c259239cd ]---
Segmentation fault
```

### Panic Decoded

```
pc : buggy_write+0x40/0x60
     ↑ offset 0x40 inside function, total size 0x60 bytes

Fault: virtual address 0x0000000000000000
       = NULL pointer dereference
       = dev->count where dev = NULL

ESR = 0x96000005
  EC = 0x25 = Data Abort (EL0 access in EL1 context)
  WnR = 0   = Read fault (loading count value from NULL)

Code: (b9400261) = LDR instruction = load from [x1+0] where x1=0 = CRASH
```

### addr2line Decode (HOST)

```bash
# Run on HOST — decode offset 0x40 to source line:
aarch64-linux-gnu-addr2line -e panic_analysis_driver.o -a 0x40

# Output:
0x0000000000000040
panic_analysis_driver.c:49    ← dev->count++ line

# Also check assembly:
aarch64-linux-gnu-objdump -d panic_analysis_driver.ko | grep -A 20 "<buggy_write>"
# Offset +0x40: ldr instruction loading from NULL pointer
```

### Stage Identification

```
User: echo "test" > /dev/panic_dev
         ↓
Kernel: sys_write() → vfs_write() → buggy_write()
         ↓
buggy_write():
  dev = filp->private_data    ← NULL (no open() was called)
  pr_info(...)                ← printed to dmesg
  dev->count++                ← CRASH at offset 0x40
         ↓
MMU fault at address 0x0000000000000000
         ↓
Oops: pc = buggy_write+0x40
         ↓
System continues (Oops, not panic) but process gets SIGSEGV
```

---

## Ex2 — FIX: Add .open — Sets private_data Before Write

### Fix Code

```c
/* FIXED: open() sets private_data */
static int fixed_open(struct inode *inode, struct file *filp)
{
    struct panic_dev *dev = container_of(inode->i_cdev,
                                          struct panic_dev, cdev);
    filp->private_data = dev;   /* set BEFORE any read/write */
    pr_info("PANIC [FIXED]: open() set private_data = %p\n", dev);
    return 0;
}

static ssize_t fixed_write(struct file *filp, const char __user *buf,
                            size_t len, loff_t *off)
{
    struct panic_dev *dev = filp->private_data;

    if (!dev) {                  /* defensive NULL check */
        pr_err("PANIC [FIXED]: private_data NULL — ENODEV\n");
        return -ENODEV;
    }

    dev->count++;
    pr_info("PANIC [FIXED]: write OK, count = %d\n", dev->count);
    return len;
}

static const struct file_operations fixed_fops = {
    .owner = THIS_MODULE,
    .open  = fixed_open,         /* MUST be present */
    .write = fixed_write,
    .read  = common_read,
};
```

### Actual QEMU Output — FIXED Mode

```
root@qemuarm64:~# insmod /home/root/panic_analysis_driver.ko use_fix=1
[ 1404.083721] PANIC [INIT]: mode=FIXED
[ 1404.088427] PANIC [INIT]: /dev/panic_dev created (major=249)

root@qemuarm64:~# echo "test" > /dev/panic_dev
[ 1404.116475] PANIC [FIXED]: open() set private_data = (____ptrval____)
[ 1404.118500] PANIC [FIXED]: write OK, count = 1

root@qemuarm64:~# cat /dev/panic_dev
[ 1404.585751] PANIC [FIXED]: open() set private_data = (____ptrval____)
count=1

root@qemuarm64:~# rmmod panic_analysis_driver
[ 1410.116366] PANIC [EXIT]: removed
```

---

## What I Checked

```
✔ BUG: private_data = 0000000000000000 in dmesg
  → confirms NULL pointer before crash

✔ pc : buggy_write+0x40/0x60
  → offset 0x40 = exact instruction that crashed

✔ Fault at virtual address 0x0000000000000000
  → confirms NULL dereference (not bad pointer, exact NULL)

✔ addr2line -e panic_analysis_driver.o -a 0x40
  → maps offset to exact source line (dev->count++)

✔ FIXED: open() sets private_data before write
  → no crash, count increments correctly

✔ FIXED: cat /dev/panic_dev shows count=1
  → read handler works, full chardev functional
```

---

## Reproduce Steps

```bash
# HOST — Build
cd ~/30days_workWith_BSP/my_projects/book2/ch05_panic_analysis
make clean && make

# Deploy
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp panic_analysis_driver.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount

~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — BUG (crashes process, system survives)
insmod /home/root/panic_analysis_driver.ko use_fix=0
echo "test" > /dev/panic_dev
dmesg | grep -A 20 "Unable to handle"

# HOST — decode crash offset
aarch64-linux-gnu-addr2line -e panic_analysis_driver.o -a 0x40

# INSIDE QEMU — FIXED
rmmod panic_analysis_driver 2>/dev/null || true
insmod /home/root/panic_analysis_driver.ko use_fix=1
echo "test" > /dev/panic_dev
cat /dev/panic_dev
dmesg | grep PANIC
rmmod panic_analysis_driver
```

---

## Root Cause vs Fix

| | BUG | FIXED |
|--|-----|-------|
| file_operations | no .open | .open = fixed_open |
| private_data | NULL (never set) | dev pointer (set in open) |
| write result | Oops at offset 0x40 | count = 1, no crash |
| addr2line 0x40 | panic_analysis_driver.c:49 | N/A |

---

## Key Takeaways

1. `filp->private_data` must be set in `.open` — not in probe or init
2. Missing `.open` in `file_operations` = default open() = `private_data` stays NULL
3. `pc : function+0xOFFSET` in dmesg → `addr2line` → exact source line
4. Call trace reads **bottom to top** = actual execution order
5. Fault address `0x0000000000000000` = NULL dereference (struct offset 0)
6. Fault address `0x0000000000000010` = struct member at offset 16 past NULL
7. Always add NULL check on `private_data` before dereferencing
8. `EXTRA_CFLAGS += -g` in Makefile needed for full addr2line resolution
