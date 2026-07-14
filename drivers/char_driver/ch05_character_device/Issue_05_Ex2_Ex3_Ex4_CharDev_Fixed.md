# Ch05 Exercise 2 – CharDev: Fix with alloc_chrdev_region + /dev/sensor

## Objective
Fix Ex1 by using `alloc_chrdev_region()` for dynamic major allocation. Add
`class_create()` and `device_create()` so udev automatically creates `/dev/sensor`.
Verify `open()` and `release()` work — `cat /dev/sensor` shows `Invalid argument`
because `read()` is not yet implemented (that's Ex3).

---

## Verified Output

```
root@qemuarm64:~# insmod /home/root/sensor_driver_chardev.ko
[  235.757621] Sensor CharDev [FIXED]: got major=249 minor=0
[  235.769724] Sensor CharDev [FIXED]: /dev/sensor created, major=249

root@qemuarm64:~# ls -la /dev/sensor
crw-------  1 root  root  249, 0  Mar 23 09:13 /dev/sensor

root@qemuarm64:~# cat /proc/devices | grep sensor
249 sensor

root@qemuarm64:~# cat /dev/sensor
[  236.651682] Sensor CharDev [OPEN]: device opened
cat: read error: Invalid argument       ← no read() yet — Ex3 adds it
[  236.665412] Sensor CharDev [RELEASE]: device closed

root@qemuarm64:~# rmmod sensor_driver_chardev
[  236.780712] Sensor CharDev [PROBE]: remove() called!

root@qemuarm64:~# ls /dev/sensor 2>/dev/null || echo "/dev/sensor removed"
/dev/sensor removed                     ← device_destroy() cleaned up
```

---

## Fix Applied

```c
/* FIXED: dynamic major */
ret = alloc_chrdev_region(&sdev->devno, 0, 1, DEVICE_NAME);

/* Create /dev/sensor via udev */
sensor_class  = class_create(THIS_MODULE, CLASS_NAME);
sensor_device = device_create(sensor_class, NULL, sdev->devno, NULL, DEVICE_NAME);
```

Cleanup in `remove()`:
```c
device_destroy(sensor_class, dev->devno);
class_destroy(sensor_class);
cdev_del(&dev->cdev);
unregister_chrdev_region(dev->devno, 1);
```

---

## What I Checked ✔

```
✔ dmesg — got major=249 (dynamic, no conflict)
✔ ls -la /dev/sensor — crw------- 249,0 created by udev
✔ cat /proc/devices | grep sensor — 249 sensor registered
✔ cat /dev/sensor — OPEN + RELEASE called, Invalid argument (no read yet)
✔ rmmod — /dev/sensor removed, device_destroy() worked
```

---

## Key Learning

- `alloc_chrdev_region()` = kernel picks free major — always use this
- `class_create()` + `device_create()` = udev creates `/dev/node` automatically
- `device_destroy()` + `class_destroy()` = cleanup in remove()
- Without `device_create()`, `/dev/sensor` must be created manually with `mknod`
- `Invalid argument` on `cat /dev/sensor` = `read()` not implemented in fops

---

---

# Ch05 Exercise 3 – CharDev: read() with copy_to_user

## Objective
Implement `read()` in the char device using `copy_to_user()` to send sensor data
to userspace. Verify `cat /dev/sensor` returns `value=42 threshold=100`.

---

## Verified Output

```
root@qemuarm64:~# cat /dev/sensor
[  335.469656] Sensor CharDev [READ]: sent 23 bytes: value=42 threshold=100
value=42 threshold=100

root@qemuarm64:~# cat /dev/sensor    ← second read also works (new open/close)
value=42 threshold=100
```

---

## Key Code

```c
static ssize_t sensor_read(struct file *file, char __user *buf,
                           size_t count, loff_t *ppos)
{
    char tmp[32];
    int len;

    if (*ppos > 0)
        return 0;  /* EOF — already read */

    len = snprintf(tmp, sizeof(tmp), "value=%d threshold=%d\n",
                   sdev->value, sdev->threshold);

    if (copy_to_user(buf, tmp, len))
        return -EFAULT;

    *ppos = len;
    pr_info("Sensor CharDev [READ]: sent %d bytes: %s", len, tmp);
    return len;
}

/* Add to fops */
static const struct file_operations sensor_fops = {
    .owner   = THIS_MODULE,
    .open    = sensor_open,
    .release = sensor_release,
    .read    = sensor_read,    /* ← added */
};
```

---

## What I Checked ✔

```
✔ cat /dev/sensor → value=42 threshold=100
✔ dmesg: [READ]: sent 23 bytes
✔ exit: 0 — no error
✔ *ppos prevents infinite loop on repeated reads within same open()
```

---

## Key Learning

- `copy_to_user(dst_user, src_kernel, len)` — copies kernel buffer to userspace
- Returns 0 on success, non-zero bytes NOT copied on failure → return `-EFAULT`
- `*ppos` tracks read position — set to len after read, return 0 on next call = EOF
- `char __user *buf` — `__user` annotation marks userspace pointer
- Never dereference userspace pointers directly — always use `copy_to_user()`
- `snprintf` into kernel buffer first, then `copy_to_user` — never format directly to userspace

---

---

# Ch05 Exercise 4 – CharDev: write() with copy_from_user

## Objective
Implement `write()` using `copy_from_user()` to receive data from userspace and
update the sensor threshold. Verify `echo "250" > /dev/sensor` updates threshold
and subsequent `cat /dev/sensor` shows new value. Test invalid input handling.

---

## Verified Output

```
# Default values
root@qemuarm64:~# cat /dev/sensor
value=42 threshold=100

# Write new threshold
root@qemuarm64:~# echo "250" > /dev/sensor
[  871.478402] Sensor CharDev [WRITE]: threshold set to 250

# Read back — threshold updated
root@qemuarm64:~# cat /dev/sensor
value=42 threshold=250

# Invalid value — error handling
root@qemuarm64:~# echo "abc" > /dev/sensor
[  871.950774] Sensor CharDev: invalid value written
sh: write error: Invalid argument
root@qemuarm64:~# echo "write exit: $?"
write exit: 1
```

---

## Key Code

```c
static ssize_t sensor_write(struct file *file, const char __user *buf,
                            size_t count, loff_t *ppos)
{
    char tmp[32];
    int val;

    if (count >= sizeof(tmp))
        return -EINVAL;

    if (copy_from_user(tmp, buf, count))
        return -EFAULT;

    tmp[count] = '\0';

    if (kstrtoint(tmp, 10, &val)) {
        pr_err("Sensor CharDev: invalid value written\n");
        return -EINVAL;
    }

    sdev->threshold = val;
    pr_info("Sensor CharDev [WRITE]: threshold set to %d\n", sdev->threshold);
    return count;
}

/* Add to fops */
static const struct file_operations sensor_fops = {
    .owner   = THIS_MODULE,
    .open    = sensor_open,
    .release = sensor_release,
    .read    = sensor_read,
    .write   = sensor_write,   /* ← added */
};
```

---

## What I Checked ✔

```
✔ echo "250" > /dev/sensor → [WRITE]: threshold set to 250
✔ cat /dev/sensor → value=42 threshold=250 (updated)
✔ echo "abc" > /dev/sensor → invalid value written → -EINVAL
✔ write exit: 1 — error returned to userspace correctly
✔ rmmod → remove() called, clean exit
```

---

## Key Learning

- `copy_from_user(dst_kernel, src_user, len)` — copies userspace data to kernel
- Returns 0 on success, non-zero bytes NOT copied on failure → return `-EFAULT`
- `const char __user *buf` — `__user` marks userspace pointer, `const` = read-only
- `kstrtoint(str, base, &val)` — safe string to int conversion in kernel
- Always null-terminate after `copy_from_user`: `tmp[count] = '\0'`
- Always check count against buffer size to prevent overflow
- Return `count` on success — tells VFS how many bytes were consumed

---

## Ch05 Complete Summary

| Exercise | Topic | Key Function | Verified |
|---|---|---|---|
| Ex1 | Wrong hardcoded major | `register_chrdev_region(MKDEV(1,0))` | `-EBUSY`, no `/dev/sensor` |
| Ex2 | Dynamic major + `/dev/sensor` | `alloc_chrdev_region()` + `device_create()` | `crw--- 249,0` created |
| Ex3 | Read from device | `copy_to_user()` | `cat /dev/sensor` = `value=42 threshold=100` |
| Ex4 | Write to device | `copy_from_user()` | `echo 250 > /dev/sensor` updates threshold |
