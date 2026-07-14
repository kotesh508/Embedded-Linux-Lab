# Ch02 Exercise 3 – DTS Mismatch: Complete Fix Verified in QEMU ARM64

---

## 📋 Category
`04_Char_Driver_Issues`

---

## Objective

Complete the DTS mismatch fix by verifying `probe()` is called on QEMU ARM64
with a matching DTS node. This exercise ties together all 3 exercises into
one complete story — from silent failure to working driver.

---

## 📖 Ch02 Complete Story (All 3 Exercises)

```
Exercise 1 — BROKE IT
  Compatible string: "kotesh,sensor-deviceX"  ← typo X
  Host kernel (x86):  probe() silent — no error
  QEMU ARM64:         probe() silent — no error
  Symptom: module loaded, driver registered, probe NEVER called

Exercise 2 — FIXED STRING, WRONG PLATFORM
  Compatible string: "kotesh,sensor-device"   ← fixed
  Host kernel (x86):  probe() still silent
  Reason: ThinkPad uses ACPI not DTS
          /proc/device-tree/ does not exist on x86
          of_match_table has nothing to match against

Exercise 3 — FIXED STRING + CORRECT PLATFORM + DTS NODE
  Compatible string: "kotesh,sensor-device"   ← fixed
  QEMU ARM64 + DTS node added:                ← correct platform
  probe() CALLED! ✅
  Device bound! ✅
```

---

## 🔴 Symptom (Exercise 1 — Starting Point)

```bash
# On host — module loaded, complete silence
$ sudo insmod sensor_driver_dts.ko
$ dmesg | grep "Sensor DTS"
# (no output)
$ ls /sys/bus/platform/drivers/sensor_dts/
bind  module  uevent  unbind   ← no device symlink
```

---

## ✅ What Was Fixed — Step by Step

### Fix 1 — Compatible String (Exercise 1 → 2)
```c
/* BEFORE — typo */
{ .compatible = "kotesh,sensor-deviceX" },

/* AFTER — correct */
{ .compatible = "kotesh,sensor-device" },
```

### Fix 2 — Added DTS Node in QEMU (Exercise 2 → 3)
```dts
/* Added to ~/dtstest/qemu-virt.dts */
kotesh-sensor@20010000 {
    compatible = "kotesh,sensor-device";   /* matches driver exactly */
    reg = <0x0 0x20010000 0x0 0x1000>;
    status = "okay";
};
```

### Fix 3 — Rebuilt DTB
```bash
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
# DTB rebuilt: 0
```

### Fix 4 — Cross-compiled for ARM64
```bash
# Install aarch64 cross compiler
sudo apt install gcc-aarch64-linux-gnu -y

# Makefile updated:
ARCH := arm64
CROSS_COMPILE := aarch64-linux-gnu-
KDIR := ~/yocto/poky/build/tmp/work/qemuarm64-poky-linux/linux-yocto/\
5.15.194+gitAUTOINC+578937826f_431a37a229-r0/linux-qemuarm64-standard-build

make clean && make
# Built sensor_driver_dts.ko for ARM64
```

### Fix 5 — Copied .ko into QEMU rootfs
```bash
sudo mount -o loop ~/yocto/poky/build/tmp/deploy/images/qemuarm64/\
core-image-minimal-qemuarm64.ext4 /tmp/qemu-mount

sudo cp sensor_driver_dts.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
```

---

## 📊 Real Test Results — QEMU ARM64

```bash
root@qemuarm64:~# insmod /home/root/sensor_driver_dts.ko
[  151.902598] Sensor DTS [PROBE]: probe() called!
[  151.903745] Sensor DTS [PROBE]: Ready, threshold=100
```

```bash
=== Probe called ===
[  151.902598] Sensor DTS [PROBE]: probe() called!      ✅
[  151.903745] Sensor DTS [PROBE]: Ready, threshold=100 ✅

=== Device bound ===
20010000.kotesh-sensor  bind  module  uevent  unbind    ✅
# Device symlink EXISTS — driver bound to device

=== DTS node visible ===
kotesh-sensor@20010000                                  ✅
# Node visible in /proc/device-tree/

=== Device in platform bus ===
20010000.kotesh-sensor                                  ✅
# Device registered at address 0x20010000

=== Clean remove ===
[  324.107859] Sensor DTS [PROBE]: remove() called!     ✅
# remove() called on rmmod — clean teardown
```

---

## 🔍 Stage Identification

Platform driver complete lifecycle — all stages verified:

1. `module_init()` → driver registered ✅
2. Kernel scans DTS nodes ✅
3. Compatible string match → `kotesh,sensor-device` == `kotesh,sensor-device` ✅
4. `probe()` called ✅
5. `devm_kzalloc()` → memory allocated ✅
6. `platform_set_drvdata()` → data stored ✅
7. `rmmod` → `remove()` called ✅

---

## 🔎 What I Checked

```bash
# Inside QEMU — full verification

# 1. Module loaded and probe called
insmod /home/root/sensor_driver_dts.ko
dmesg | grep "Sensor DTS" | tail -5
# [151.902598] Sensor DTS [PROBE]: probe() called!
# [151.903745] Sensor DTS [PROBE]: Ready, threshold=100

# 2. Device symlink exists in driver directory
ls /sys/bus/platform/drivers/sensor_dts/
# 20010000.kotesh-sensor  bind  module  uevent  unbind
# ^^^^^^^^^^^^^^^^^^^^ device symlink = bound!

# 3. DTS node registered
ls /proc/device-tree/ | grep sensor
# kotesh-sensor@20010000

# 4. Device in platform bus
ls /sys/bus/platform/devices/ | grep sensor
# 20010000.kotesh-sensor

# 5. Clean unload
rmmod sensor_driver_dts
dmesg | grep "Sensor DTS" | tail -3
# probe() called → Ready → remove() called
```

✔ `probe()` called — confirmed in dmesg

✔ Device symlink `20010000.kotesh-sensor` in driver directory

✔ DTS node `kotesh-sensor@20010000` in `/proc/device-tree/`

✔ Device `20010000.kotesh-sensor` in platform bus

✔ `remove()` called on rmmod — clean lifecycle

---

## 🔍 Root Cause Summary — Why 3 Exercises Were Needed

```
Problem 1: Compatible string typo
  "kotesh,sensor-deviceX" ≠ "kotesh,sensor-device"
  Fix: remove the X

Problem 2: Wrong platform for testing
  x86 ThinkPad = ACPI based
  No /proc/device-tree/ → of_match_table has nothing to compare
  Fix: use QEMU ARM64 which is DTS based

Problem 3: Architecture mismatch
  .ko compiled for x86_64 (ELF header: 62)
  QEMU runs ARM64 — cannot load x86 module
  Fix: cross-compile with aarch64-linux-gnu-

Problem 4: No matching DTS node
  Driver looks for "kotesh,sensor-device" in DTS
  DTS file had no such node → still no probe
  Fix: add kotesh-sensor@20010000 node to qemu-virt.dts
```

---

## ✅ Complete Fix Code

### Driver (sensor_driver_dts.c)
```c
static const struct of_device_id sensor_of_ids[] = {
    { .compatible = "kotesh,sensor-device" },  /* exact match */
    { }
};
MODULE_DEVICE_TABLE(of, sensor_of_ids);

static int sensor_probe(struct platform_device *pdev)
{
    struct sensor_data *dev;

    pr_info("Sensor DTS [PROBE]: probe() called!\n");

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    dev->value = 0;
    dev->threshold = 100;
    platform_set_drvdata(pdev, dev);

    pr_info("Sensor DTS [PROBE]: Ready, threshold=%d\n", dev->threshold);
    return 0;
}

static int sensor_remove(struct platform_device *pdev)
{
    pr_info("Sensor DTS [PROBE]: remove() called!\n");
    return 0;
}
```

### DTS Node (qemu-virt.dts)
```dts
kotesh-sensor@20010000 {
    compatible = "kotesh,sensor-device";
    reg = <0x0 0x20010000 0x0 0x1000>;
    status = "okay";
};
```

### Makefile
```makefile
ARCH := arm64
CROSS_COMPILE := aarch64-linux-gnu-
KDIR := /home/kotesh/yocto/poky/build/tmp/work/qemuarm64-poky-linux/\
linux-yocto/5.15.194+gitAUTOINC+578937826f_431a37a229-r0/\
linux-qemuarm64-standard-build
```

---

## 📁 Related Files

| File | Path |
|---|---|
| Driver | `~/30days_workWith_BSP/my_projects/ch02_dts_mismatch/sensor_driver_dts.c` |
| DTS | `~/dtstest/qemu-virt.dts` |
| DTB | `~/dtstest/kotesh-test.dtb` |
| Makefile | `~/30days_workWith_BSP/my_projects/ch02_dts_mismatch/Makefile` |

---

## 🧪 How to Reproduce

```bash
# Host — build ARM64 module
cd ~/30days_workWith_BSP/my_projects/ch02_dts_mismatch
make clean && make

# Host — copy to QEMU rootfs
sudo mount -o loop ~/yocto/poky/build/tmp/deploy/images/qemuarm64/\
core-image-minimal-qemuarm64.ext4 /tmp/qemu-mount
sudo cp sensor_driver_dts.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount

# Host — boot QEMU
~/BSP-Lab/boot_qemu.sh

# Inside QEMU
insmod /home/root/sensor_driver_dts.ko
dmesg | grep "Sensor DTS"
ls /sys/bus/platform/drivers/sensor_dts/
rmmod sensor_driver_dts
```

---

## ✅ Key Diagnostic Commands

```bash
# Verify probe called
dmesg | grep "probe\|PROBE"

# Verify device bound — look for device symlink
ls /sys/bus/platform/drivers/<driver>/
# device symlink present = bound ✅
# only bind/unbind/uevent/module = NOT bound ❌

# Verify DTS node exists
ls /proc/device-tree/ | grep <node>

# Verify device registered
ls /sys/bus/platform/devices/ | grep <device>

# Check module architecture before loading
file sensor_driver_dts.ko
# ARM aarch64 = correct for QEMU
# x86-64 = wrong — will fail with "Invalid architecture"
```

---

## 📌 Key Learning

- Compatible string must match **exactly** — one character difference = silent failure
- x86 host uses ACPI — `of_match_table` never matches on x86
- Always test platform drivers on ARM64 QEMU or real embedded board
- Cross-compile with `ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-`
- `file <module>.ko` shows architecture — verify before copying to target
- Device symlink in `/sys/bus/platform/drivers/<drv>/` = bound ✅
- `devm_kzalloc` auto-freed on remove — no manual kfree needed
- `platform_set_drvdata` / `platform_get_drvdata` = store/retrieve driver data

---

## 📌 Ch02 Complete Summary

```
Exercise 1: Compatible mismatch observed    → silent failure documented
Exercise 2: String fixed, host tested       → ACPI vs DTS difference learned
Exercise 3: QEMU + DTS node + ARM64 build   → probe() called ✅

Full fix required:
  □ Correct compatible string in of_match_table
  □ Matching DTS node in qemu-virt.dts
  □ DTB rebuilt with dtc
  □ Cross-compiled for ARM64
  □ Copied .ko to QEMU rootfs
  □ Verified probe() + remove() lifecycle
```

---

*Kotesh S — BSP Lab — Ch02 Exercise 3 — March 2026*
