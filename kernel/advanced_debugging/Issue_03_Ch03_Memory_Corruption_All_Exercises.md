# Issue 03 — Ch03: Memory Corruption (Book 2) — All 3 Exercises

## Chapter
Ch03 — Memory Corruption: Silent System Failure

---

## Theory Background

### Why Kernel Memory Corruption Is Dangerous

```
kmalloc(10) allocates 10 bytes:
  [ buf[0] .. buf[9] ][ adjacent kernel struct ]
                       ↑
  buf[20] = 0xDEAD → writes HERE (10 bytes past end)
  Corrupts: spinlock, task_struct, work_struct, etc.

Crash happens LATER at unrelated location.
Call trace is MISLEADING — points to victim, not culprit.

User space: MMU catches out-of-bounds → SIGSEGV → only process dies
Kernel space: no safety net → corrupts shared memory → panic anywhere

Key Rule:
  ALWAYS validate user-supplied length before copy_from_user().
  ALWAYS use min(len, sizeof(buf)) to clamp size.
  Enable CONFIG_KASAN=y during development to catch overflows instantly.
```

---

## Environment

| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| Module | memory_corruption_driver.ko |
| Source | ~/30days_workWith_BSP/my_projects/book2/ch03_memory_corruption/ |
| Bug | copy_from_user without bounds check → buffer overflow |
| Detect | CONFIG_KASAN=y → reports exact write location |

---

## Ex1 — BUG: copy_from_user Without Bounds Check

### Bug Code

```c
static ssize_t my_write(struct file *f, const char __user *buf,
                        size_t len, loff_t *off)
{
    char kernel_buf[10];                    /* fixed 10-byte buffer */
    copy_from_user(kernel_buf, buf, len);   /* len from user — could be 1000! */
    pr_info("received %zu bytes\n", len);
    return len;
}
```

### Symptom Log

```
# Without KASAN — crash at random unrelated location:
[  45.2] BUG: unable to handle kernel NULL pointer dereference
[  45.2] IP: schedule+0x14/0x300   ← completely unrelated to the overflow!

# With KASAN enabled:
[  3.12] BUG: KASAN: slab-out-of-bounds in my_write+0x38/0x80
[  3.12] Write of size 1 at addr ffffffc009ab1234 by task sh/234
[  3.12] kasan_report+0xe0/0x...
[  3.12] my_write+0x38/0x80 [memory_corruption_driver]
```

### Root Cause

```c
char kernel_buf[10];
copy_from_user(kernel_buf, buf, len);  /* len=100 → writes 90 bytes PAST end */
/* overwrites adjacent kernel memory — corrupts random structures */
```

---

## Ex2 — FIX: Bounds Check Before copy_from_user

### Fix Code

```c
static ssize_t my_write(struct file *f, const char __user *buf,
                        size_t len, loff_t *off)
{
    char kernel_buf[10];

    if (len > sizeof(kernel_buf))      /* BOUNDS CHECK */
        len = sizeof(kernel_buf);      /* clamp to buffer size */

    if (copy_from_user(kernel_buf, buf, len))
        return -EFAULT;

    pr_info("FIXED: received %zu bytes safely\n", len);
    return len;
}
```

### Fix Pattern — Always Use This

```c
/* Pattern: clamp + check return value */
if (len > sizeof(buf)) len = sizeof(buf);   /* never trust user len */
if (copy_from_user(buf, ubuf, len)) return -EFAULT;

/* Or reject oversized input: */
if (len > sizeof(buf)) return -EINVAL;      /* tell user: too large */
```

---

## Ex3 — DETECT: KASAN (Kernel Address Sanitizer)

### Enable KASAN in Yocto

```bash
bitbake linux-yocto -c menuconfig
# Kernel hacking → Memory Debugging →
#   [*] KASAN: runtime memory debugger
#   (X) Stack instrumentation
# CONFIG_KASAN=y
# CONFIG_KASAN_INLINE=y

bitbake linux-yocto -c compile -f && bitbake core-image-minimal
```

### Verify KASAN Running

```bash
# In QEMU:
zcat /proc/config.gz | grep KASAN
# Expected: CONFIG_KASAN=y

# Trigger bug:
insmod memory_corruption_driver.ko
echo "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" > /dev/mem_corrupt
dmesg | grep KASAN
```

### make C=1 — Compile Time Check

```bash
# On host — sparse static analysis catches __user pointer misuse:
make C=1 KBUILD_CFLAGS+="-Wsparse-error"
# Reports: warning: incorrect type in argument (different address spaces)
```

---

## Reproduce Steps

```bash
# HOST
cd ~/30days_workWith_BSP/my_projects/book2/ch03_memory_corruption
make clean && make
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp memory_corruption_driver.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — BUG
insmod /home/root/memory_corruption_driver.ko
echo "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" > /dev/mem_corrupt
dmesg | grep -E "KASAN|BUG|corruption"

# FIXED
insmod /home/root/memory_corruption_driver_fixed.ko
echo "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" > /dev/mem_corrupt
dmesg | grep "FIXED"
rmmod memory_corruption_driver_fixed
```

---

## Key Takeaways

1. Buffer overflow in kernel corrupts adjacent memory — crash at unrelated location
2. ALWAYS bounds-check user-supplied length: `if (len > sizeof(buf)) len = sizeof(buf)`
3. `CONFIG_KASAN=y` catches overflow at exact write location — use in dev kernel
4. `make C=1` (sparse) catches `__user` pointer misuse at compile time
5. Crash trace after corruption is MISLEADING — enable KASAN to find real source
6. Never trust user-space supplied lengths, offsets, or sizes without validation
