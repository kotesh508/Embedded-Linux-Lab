# Ch05 Exercise 1 – CharDev: Wrong Hardcoded Major Number

## Objective
Demonstrate that using a hardcoded major number (major=1) conflicts with existing
kernel devices and causes `register_chrdev_region()` to return `-EBUSY`. No `/dev/sensor`
is created. Fix is to use `alloc_chrdev_region()` for dynamic major allocation.

---

## Environment
| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| Module | sensor_driver_chardev.ko |
| DTS node | kotesh-sensor-chardev@20014000 |
| Bug | `MKDEV(1, 0)` — major 1 already used by `mem` |

---

## Symptom (Log Snippet)

```
root@qemuarm64:~# insmod /home/root/sensor_driver_chardev.ko
[  191.264934] Sensor CharDev [PROBE]: probe() called!
[  191.266149] Sensor CharDev [BUG]: register_chrdev_region failed -16
[  191.269848] Sensor CharDev [BUG]: major 1 already in use!
[  191.272427] sensor_chardev: probe of 20014000.kotesh-sensor-chardev failed with error -16

root@qemuarm64:~# cat /proc/devices | grep "^  1"
  1 mem

root@qemuarm64:~# ls /dev/sensor 2>/dev/null || echo "no /dev/sensor — as expected"
no /dev/sensor — as expected
```

---

## Root Cause

```c
/* BUGGY CODE */
#define WRONG_MAJOR  1
sdev->devno = MKDEV(WRONG_MAJOR, 0);
ret = register_chrdev_region(sdev->devno, 1, DEVICE_NAME);
/* returns -EBUSY (-16) — major 1 owned by mem */
```

Major 1 is reserved for memory devices (`/dev/mem`, `/dev/null`, `/dev/zero`).
`register_chrdev_region()` with a taken major returns `-EBUSY`.

---

## Fix (Applied in Ex2)

```c
/* FIXED CODE */
ret = alloc_chrdev_region(&sdev->devno, 0, 1, DEVICE_NAME);
/* kernel picks a free major — no conflict possible */
```

---

## What I Checked ✔

```
✔ cat /proc/devices | grep "^  1"
  → 1 mem — major 1 already taken

✔ dmesg | grep "Sensor CharDev"
  → [BUG]: register_chrdev_region failed -16
  → [BUG]: major 1 already in use!

✔ ls /dev/sensor
  → no /dev/sensor — device never created

✔ ls /sys/bus/platform/drivers/sensor_chardev/
  → bind module uevent unbind — no device symlink, probe failed
```

---

## Key Learning

- Never hardcode major numbers — always use `alloc_chrdev_region()`
- Major 1 = mem devices, Major 4 = tty, Major 5 = console — all reserved
- `register_chrdev_region()` = static (you choose major) — conflicts possible
- `alloc_chrdev_region()` = dynamic (kernel chooses) — always safe
- `-EBUSY` (-16) from `register_chrdev_region` = major already taken
- Check `/proc/devices` to see all registered majors

---

## Interview Explanation

> "The driver used `MKDEV(1, 0)` to hardcode major number 1, but major 1 is already
> reserved for memory devices like `/dev/mem`. `register_chrdev_region()` returned
> `-EBUSY` and probe failed. The fix is `alloc_chrdev_region()` which lets the kernel
> assign a free major number dynamically — guaranteed no conflict."
