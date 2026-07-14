# Ch02 Exercise 2 – DTS Mismatch: Fix Compatible String + Host vs QEMU Difference

---

## 📋 Category
`04_Char_Driver_Issues`

---

## Objective

Fix the compatible string typo from Exercise 1 and understand a critical difference:
**platform drivers with DTS matching cannot be tested on host x86 kernel —
they require QEMU ARM64 or real embedded hardware with Device Tree.**

---

## 🔴 Symptom (Before Fix — from Exercise 1)

```bash
# Driver loaded but probe never called
dmesg | grep "Sensor DTS"
# (no output)

ls /sys/bus/platform/drivers/sensor_dts/
# bind  module  uevent  unbind  ← no device symlink
```

---

## ✅ Fix Applied

```c
/* BEFORE — typo in compatible string */
{ .compatible = "kotesh,sensor-deviceX" },  /* extra X */

/* AFTER — correct string */
{ .compatible = "kotesh,sensor-device" },   /* matches DTS node */
```

---

## 📊 Real Test Results After Fix

```bash
=== Compatible string ===
alias: of:N*T*Ckotesh,sensor-deviceC*
alias: of:N*T*Ckotesh,sensor-device       ← X removed, correct now

=== Host kernel DTS ===
No device tree — ACPI based host          ← ThinkPad uses ACPI not DTS

=== Driver registered ===
bind  module  uevent  unbind              ← still no device symlink

=== Probe status ===
(no output)                               ← probe still not called
```

---

## 🔍 Stage Identification

Fix applied correctly — but probe still not called. Why?

👉 **Host kernel (ThinkPad T460s) is ACPI based — not DTS based.**

```
ThinkPad T460s:
  Architecture: x86_64
  Boot firmware: UEFI + ACPI
  Platform devices: ACPI0003, coretemp, i8042, intel_pmc_core...
  /proc/device-tree/ → does NOT exist
  → of_match_table has NO devices to match against
  → probe() can NEVER be called on host kernel

QEMU ARM64:
  Architecture: ARM64
  Boot: U-Boot + DTB
  Platform devices: from DTS file (qemu-virt.dts)
  /proc/device-tree/ → EXISTS
  → of_match_table matches against DTS nodes
  → probe() WILL be called when compatible matches
```

---

## 🔎 What I Checked

```bash
# 1. Verify compatible string fixed
modinfo sensor_driver_dts.ko | grep alias
# alias: of:N*T*Ckotesh,sensor-device  ← correct, no X

# 2. Check if host has device tree
ls /proc/device-tree/ 2>/dev/null || echo "No device tree — ACPI based host"
# No device tree — ACPI based host  ← confirmed x86 ACPI

# 3. Check platform devices on host
ls /sys/bus/platform/devices/ | head -10
# ACPI0003:00, coretemp.0, i8042, intel_pmc_core.0...
# All ACPI devices — none match DTS compatible strings

# 4. Driver still registered
ls /sys/bus/platform/drivers/sensor_dts/
# bind  module  uevent  unbind  ← registered but no DTS devices to bind

# 5. Probe still not called — expected on host
dmesg | grep "Sensor DTS" | tail -5
# (no output) ← correct behavior on ACPI host
```

✔ Compatible string fixed — `kotesh,sensor-device` correct

✔ `modinfo` alias confirms correct string exported

✔ Host confirmed ACPI based — `/proc/device-tree/` does not exist

✔ No probe on host — **expected and correct behavior**

✔ To test probe() — need QEMU ARM64 with matching DTS node

---

## 🔍 Root Cause — Host vs QEMU Difference

```
HOST KERNEL (x86 ThinkPad)          QEMU ARM64
────────────────────────────         ──────────────────────────
Firmware: UEFI + ACPI                Firmware: U-Boot + DTB
Platform devices from: ACPI tables   Platform devices from: DTS file
/proc/device-tree/: NOT present      /proc/device-tree/: PRESENT
of_match_table: nothing to match     of_match_table: matches DTS nodes
probe(): NEVER called                probe(): called when compatible matches
Use for: char drivers, misc drivers  Use for: platform_driver with DTS
```

---

## ✅ Complete Fix — What's Needed for probe() to be Called

**Step 1 — Fix compatible string (done):**
```c
{ .compatible = "kotesh,sensor-device" },
```

**Step 2 — Add matching DTS node in QEMU (needed for Ex3):**
```dts
/* In ~/dtstest/qemu-virt.dts */
kotesh-sensor@20010000 {
    compatible = "kotesh,sensor-device";
    reg = <0x0 0x20010000 0x0 0x1000>;
    status = "okay";
};
```

**Step 3 — Boot QEMU with updated DTB — probe() will be called:**
```
[x.xxxxxx] Sensor DTS [PROBE]: probe() called!
[x.xxxxxx] Sensor DTS [PROBE]: Ready, threshold=100
```

---

## 📁 Related Files

| File | Path |
|---|---|
| Fixed driver | `~/30days_workWith_BSP/my_projects/ch02_dts_mismatch/sensor_driver_dts.c` |
| DTS file | `~/dtstest/qemu-virt.dts` |
| Makefile | `~/30days_workWith_BSP/my_projects/ch02_dts_mismatch/Makefile` |

---

## 🧪 How to Reproduce

```bash
# Build fixed driver
cd ~/30days_workWith_BSP/my_projects/ch02_dts_mismatch
make clean && make

# Load on host — verify string fixed but probe not called (expected)
sudo insmod sensor_driver_dts.ko
modinfo sensor_driver_dts.ko | grep alias
ls /proc/device-tree/ 2>/dev/null || echo "No DTS on host — use QEMU"
dmesg | grep "Sensor DTS"   # empty — expected on host

# Unload
sudo rmmod sensor_driver_dts
```

---

## ✅ Key Diagnostic Commands

```bash
# Check compatible string in driver
modinfo <module>.ko | grep alias

# Check if system has device tree
ls /proc/device-tree/ 2>/dev/null || echo "ACPI based — no DTS"

# Check platform devices (ACPI vs DTS)
ls /sys/bus/platform/devices/ | head -20

# On QEMU/board — check DTS node compatible
cat /proc/device-tree/<node>/compatible
```

---

## 📌 Key Learning

- Fixing compatible string is necessary but not sufficient on x86 host
- x86 systems use **ACPI** — `of_match_table` has nothing to match
- ARM64 systems use **DTS** — `of_match_table` matches DTS nodes
- `/proc/device-tree/` present = DTS system, absent = ACPI system
- Platform drivers with DTS **must be tested on QEMU ARM64 or real board**
- Ex3 will complete the test by adding DTS node in QEMU

---

*Kotesh S — BSP Lab — Ch02 Exercise 2 — March 2026*
