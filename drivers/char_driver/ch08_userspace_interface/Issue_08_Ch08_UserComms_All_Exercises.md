# Issue 08 — Ch08: User Space Communications (All 4 Exercises)

## Chapter
Ch08 — User Space Communications via procfs, sysfs, debugfs

---

## Theory Background

### Three Kernel→Userspace Communication Interfaces

```
┌─────────────────────────────────────────────────────────────┐
│  Interface   │ Mount Point           │ Use Case              │
├─────────────────────────────────────────────────────────────┤
│  procfs      │ /proc/               │ Process/driver data    │
│  sysfs       │ /sys/                │ Device attributes      │
│  debugfs     │ /sys/kernel/debug/   │ Debug info (dev only)  │
└─────────────────────────────────────────────────────────────┘

procfs:
  - Legacy interface, still widely used
  - proc_ops (kernel 5.6+) replaced file_operations
  - Created with proc_create(), removed with proc_remove()
  - Permissions set at create time: 0444=ro, 0644=rw

sysfs:
  - Tied to device model (struct device)
  - DEVICE_ATTR_RW() macro creates show+store pair
  - Lives at /sys/bus/platform/devices/<device>/
  - sysfs_emit() is the correct write function (replaces sprintf)

debugfs:
  - Not for production — CONFIG_DEBUG_FS only
  - Simplest API: debugfs_create_u32/x32/bool etc.
  - No boilerplate needed for simple integer values
  - Lives at /sys/kernel/debug/<dir>/
  - debugfs_remove_recursive() cleans entire dir tree
```

### proc_ops vs file_operations (kernel 5.6+ change)

```c
/* BEFORE kernel 5.6 — WRONG for 5.6+ (compile error): */
static const struct file_operations fops = {
    .owner = THIS_MODULE,
    .read  = my_read,
};
proc_create("name", 0444, NULL, &fops);  /* ERROR in 5.6+ */

/* AFTER kernel 5.6 — CORRECT: */
static const struct proc_ops pops = {
    .proc_read  = my_read,
    .proc_write = my_write,
};
proc_create("name", 0644, NULL, &pops);  /* OK */
```

---

## Ex1 — procfs BUG: Read-Only, No Write Handler

### Bug Description
- Permission `0444` = read-only, write returns I/O error
- No `.proc_write` in `proc_ops` — writes silently rejected
- Using `file_operations` with `proc_create` on kernel 5.6+ = compile error

### Reproduce Steps

```bash
# Host: build
cd ~/30days_workWith_BSP/my_projects/ch08_usercomms
# Makefile: obj-m += sensor_driver_proc_ex1.o
make clean && make
echo "Build: $?"

# Deploy
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 /tmp/qemu-mount
sudo cp sensor_driver_proc_ex1.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# QEMU
insmod /home/root/sensor_driver_proc_ex1.ko
ls -la /proc/sensor_data
cat /proc/sensor_data
echo "99" > /proc/sensor_data
echo "write exit: $?"
dmesg | grep "Sensor Proc" | tail -5
rmmod sensor_driver_proc_ex1
```

### Actual Output (Buggy)

```
[  226.658430] Sensor Proc [PROBE]: probe() called!
[  226.659540] Sensor Proc [BUG]: /proc/sensor_data created 0444 read-only
[  226.664623] Sensor Proc [BUG]: no .proc_write handler — writes will fail!
[  226.665362] Sensor Proc [PROBE]: Ready

-r--r--r--    1 root     root    0 Mar 24 18:39 /proc/sensor_data

[READ]: sent 16 bytes
sensor_value=42

sh: write error: Input/output error
write exit: 1
```

### Root Cause

```
proc_create(PROC_NAME, 0444, NULL, &sensor_proc_ops)
                        ^^^^
                        0444 = r--r--r-- (no write bit)
                        + no .proc_write in proc_ops
                        → any write returns EIO
```

### Fix (see Ex2)

```c
/* Change 1: set 0644 permissions */
proc_create(PROC_NAME, 0644, NULL, &sensor_proc_ops);

/* Change 2: add .proc_write handler */
static const struct proc_ops sensor_proc_ops = {
    .proc_read  = sensor_proc_read,
    .proc_write = sensor_proc_write,   /* ADD THIS */
};
```

```bash
# sed fix commands:
sed -i 's/0444/0644/' sensor_driver_proc_ex1.c
# Add write handler function and .proc_write = sensor_proc_write to proc_ops
```

---

## Ex2 — procfs FIXED: proc_ops with Read + Write

### Fix Description
- Permission `0644` = read+write
- `.proc_write` handler added using `copy_from_user()` + `kstrtoint()`
- Uses `proc_ops` (correct for kernel 5.6+)

### Actual Output (Fixed)

```
[  227.378725] Sensor Proc: Created /proc/sensor_data

$ cat /proc/sensor_data
42

$ echo "99" > /proc/sensor_data
[  227.470869] Sensor Proc: Updated value to 99

$ cat /proc/sensor_data
99

[  227.868197] Sensor Proc: Removed /proc/sensor_data
```

---

## Ex3 — sysfs: DEVICE_ATTR_RW Attributes

### Description
- `DEVICE_ATTR_RW(value)` creates `value_show()` + `value_store()` pair
- `sysfs_create_groups()` registers all attributes at probe
- Lives at `/sys/bus/platform/devices/20014000.kotesh-sensor-chardev/`
- `sysfs_emit()` is the correct buffer write function

### Reproduce Steps (QEMU)

```bash
insmod /home/root/sensor_driver_sysfs.ko
SYSFS_PATH=/sys/bus/platform/devices/20014000.kotesh-sensor-chardev

cat $SYSFS_PATH/value          # read
echo "250" > $SYSFS_PATH/value # write
cat $SYSFS_PATH/value          # verify

cat $SYSFS_PATH/threshold
echo "500" > $SYSFS_PATH/threshold
cat $SYSFS_PATH/threshold
dmesg | grep "Sensor Sysfs" | tail -5
rmmod sensor_driver_sysfs
```

### Actual Output

```
[  227.978418] Sensor Sysfs [PROBE]: probe() called!
[  227.979102] Sensor Sysfs [FIXED]: sysfs attrs created
[  227.979549] Sensor Sysfs [FIXED]: cat /sys/bus/platform/devices/20014000.kotesh-sensor-chardev/value
[  227.982398] Sensor Sysfs [PROBE]: Ready

$ cat $SYSFS_PATH/value
[  228.068637] Sensor Sysfs [SHOW]: value=42
42

$ echo "250" > $SYSFS_PATH/value
[  228.092342] Sensor Sysfs [STORE]: value set to 250

$ cat $SYSFS_PATH/value
[  228.156130] Sensor Sysfs [SHOW]: value=250
250

$ echo "500" > $SYSFS_PATH/threshold
[  228.240672] Sensor Sysfs [STORE]: threshold set to 500

$ cat $SYSFS_PATH/threshold
500
```

### Key sysfs API Pattern

```c
/* show = read, store = write */
static ssize_t value_show(struct device *dev,
                          struct device_attribute *attr, char *buf)
{
    return sysfs_emit(buf, "%d\n", sensor_value);  /* NOT sprintf! */
}
static ssize_t value_store(struct device *dev,
                           struct device_attribute *attr,
                           const char *buf, size_t count)
{
    int val;
    kstrtoint(buf, 10, &val);
    sensor_value = val;
    return count;
}
static DEVICE_ATTR_RW(value);   /* creates dev_attr_value */

/* Register at probe: */
sysfs_create_groups(&pdev->dev.kobj, sensor_groups);

/* Remove at remove(): */
sysfs_remove_groups(&pdev->dev.kobj, sensor_groups);
```

---

## Ex4 — debugfs: Integer + Hex Attributes

### Description
- `debugfs_create_dir()` creates `/sys/kernel/debug/kotesh_sensor/`
- `debugfs_create_u32()` = decimal read/write, no boilerplate
- `debugfs_create_x32()` = hex read-only register dump
- `debugfs_remove_recursive()` cleans entire directory tree

### Reproduce Steps (QEMU)

```bash
insmod /home/root/sensor_driver_debugfs.ko
ls /sys/kernel/debug/kotesh_sensor/
cat /sys/kernel/debug/kotesh_sensor/value
echo "999" > /sys/kernel/debug/kotesh_sensor/value
cat /sys/kernel/debug/kotesh_sensor/value
cat /sys/kernel/debug/kotesh_sensor/reg_dump
dmesg | grep "Sensor Debugfs" | tail -5
rmmod sensor_driver_debugfs
```

### Actual Output

```
[  228.723457] Sensor Debugfs [PROBE]: probe() called!
[  228.724795] Sensor Debugfs [FIXED]: /sys/kernel/debug/kotesh_sensor/ created
[  228.725401] Sensor Debugfs [FIXED]:   value     (rw) = 42
[  228.725868] Sensor Debugfs [FIXED]:   threshold (rw) = 100
[  228.726281] Sensor Debugfs [FIXED]:   reg_dump  (ro) = 0xDEADBEEF
[  228.726737] Sensor Debugfs [PROBE]: Ready

$ ls /sys/kernel/debug/kotesh_sensor/
reg_dump   threshold  value

$ cat /sys/kernel/debug/kotesh_sensor/value
42

$ echo "999" > /sys/kernel/debug/kotesh_sensor/value
$ cat /sys/kernel/debug/kotesh_sensor/value
999

$ cat /sys/kernel/debug/kotesh_sensor/reg_dump
0xdeadbeef

[  232.567574] Sensor Debugfs [PROBE]: remove() called!
```

### Key debugfs API Pattern

```c
/* Create directory */
dbg_dir = debugfs_create_dir("kotesh_sensor", NULL);

/* Create files — no read/write handlers needed for primitives */
debugfs_create_u32("value",     0644, dbg_dir, &sensor_value);
debugfs_create_u32("threshold", 0644, dbg_dir, &sensor_threshold);
debugfs_create_x32("reg_dump",  0444, dbg_dir, &dbg_reg_dump);

/* Remove entire tree at once */
debugfs_remove_recursive(dbg_dir);
```

---

## Interface Comparison Summary

| Feature | procfs | sysfs | debugfs |
|---------|--------|-------|---------|
| Mount | /proc/ | /sys/ | /sys/kernel/debug/ |
| API | proc_ops (5.6+) | DEVICE_ATTR_RW | debugfs_create_u32 |
| Tied to device | No | Yes | No |
| Production use | Yes | Yes | No (debug only) |
| Permissions | Set at create | Set in ATTR macro | Set at create |
| Cleanup | proc_remove() | sysfs_remove_groups() | debugfs_remove_recursive() |
| Best for | Global driver data | Per-device attributes | Debug registers/counters |

---

## Key Takeaways

1. **proc_ops** replaced `file_operations` for procfs in kernel 5.6 — compile error if wrong
2. **0444** = read-only — writes fail with EIO even if write handler exists
3. **sysfs_emit()** not `sprintf()` — prevents buffer overflow in sysfs show()
4. **DEVICE_ATTR_RW(name)** auto-generates `name_show` + `name_store` signatures
5. **debugfs_create_u32()** — zero boilerplate for integer debug values
6. **debugfs_remove_recursive()** — removes entire directory tree in one call
7. **procfs** = global data, **sysfs** = per-device, **debugfs** = development only
