# Ch02 Exercise 1 – DTS Mismatch: Compatible String Typo (Observe Silence)

---

## 📋 Category
`04_Char_Driver_Issues`

---

## Objective

Reproduce and analyze silent probe failure caused by a compatible string mismatch
between the driver's `of_match_table` and the DTS node.

This demonstrates the most common and hardest-to-debug driver issue —
**no error, no warning, complete silence.**

---

## 🔴 Symptom

Module loads successfully. Driver registers. But **probe() is never called.**
No error in dmesg. No warning. Complete silence.

```bash
$ sudo insmod sensor_driver_dts.ko
$ dmesg | grep "Sensor DTS\|PROBE"
# (no output — probe never called)

$ ls /sys/bus/platform/drivers/sensor_dts/
bind  module  uevent  unbind
# No device symlink = driver never bound to any device
```

---

## 🔍 Stage Identification

Platform driver lifecycle stages:

1. `module_init()` called → driver registers with kernel
2. Kernel scans all platform devices
3. Kernel compares DTS `compatible` with driver `of_match_table`
4. **MATCH?** → `probe()` called
5. **NO MATCH?** → silently skipped — no error

Failure occurred at:

👉 **Stage 3 — compatible string comparison failed**

Driver string: `kotesh,sensor-deviceX`
No DTS node has this string → kernel silently skips → probe never called.

---

## 🔎 What I Checked

```bash
# 1. Confirm module loaded
lsmod | grep sensor_driver_dts
# sensor_driver_dts      16384  0  ← loaded, refcount=0 (no device using it)

# 2. Confirm driver registered
ls /sys/bus/platform/drivers/ | grep sensor
# sensor_dts  ← driver registered

# 3. Confirm probe never called
dmesg | grep "Sensor DTS\|PROBE" | tail -5
# (no output) ← probe() was NEVER called

# 4. Confirm no device bound
ls /sys/bus/platform/drivers/sensor_dts/
# bind  module  uevent  unbind
# No device symlink = not bound to any device

# 5. Confirm what compatible string driver expects
modinfo sensor_driver_dts.ko | grep alias
# alias: of:N*T*Ckotesh,sensor-deviceX
# alias: of:N*T*Ckotesh,sensor-deviceXC*
```

✔ Module loaded — `lsmod` confirms `sensor_driver_dts` present

✔ Driver registered — `/sys/bus/platform/drivers/sensor_dts/` exists

✔ Probe never called — zero dmesg output from driver

✔ No device bound — only `bind module uevent unbind` in driver directory

✔ Compatible string confirmed — `kotesh,sensor-deviceX` ← has typo `X`

---

## 🔍 Root Cause

```c
/* BUGGY — compatible string has extra 'X' at end */
static const struct of_device_id sensor_of_ids[] = {
    { .compatible = "kotesh,sensor-deviceX" },  /* BUG: extra X */
    { }
};

/* DTS node would have: */
/* compatible = "kotesh,sensor-device";  ← no X */

/* Comparison:
   Driver:  kotesh,sensor-deviceX
   DTS:     kotesh,sensor-device
                              ^
                              X missing in DTS — NO MATCH
   Result:  probe() silently never called */
```

**Why this is dangerous:**
- No error message — kernel does not complain
- No warning — system boots normally
- Driver loads — `lsmod` shows it present
- Everything looks fine — but device never works

**On real hardware this wastes hours of debugging time.**

---

## ✅ Fix

```c
/* FIXED — exact match with DTS compatible string */
static const struct of_device_id sensor_of_ids[] = {
    { .compatible = "kotesh,sensor-device" },  /* removed X */
    { }
};
```

After fix — with matching DTS node:
```
[x.xxxxxx] Sensor DTS [PROBE]: probe() called!
[x.xxxxxx] Sensor DTS [PROBE]: Ready, threshold=100
```

---

## 🧠 Interview Explanation

A compatible string mismatch is the most silent failure in Linux driver development — the module loads, the driver registers, but probe() is never called and no error is printed. The kernel simply skips any device whose DTS compatible string does not exactly match the driver's of_match_table entry, character by character. Diagnosis: check `/sys/bus/platform/drivers/<driver>/` for a device symlink — if only bind/unbind/uevent/module are present, the driver is unbound. Fix: compare the compatible strings character by character and ensure exact match.

---

## 📁 Related Files

| File | Path |
|---|---|
| Buggy driver | `~/30days_workWith_BSP/my_projects/ch02_dts_mismatch/sensor_driver_dts.c` |
| Makefile | `~/30days_workWith_BSP/my_projects/ch02_dts_mismatch/Makefile` |

---

## 🧪 How to Reproduce

```bash
# Step 1 — Build
cd ~/30days_workWith_BSP/my_projects/ch02_dts_mismatch
make clean && make

# Step 2 — Load driver
sudo insmod sensor_driver_dts.ko

# Step 3 — Observe silence
dmesg | grep "Sensor DTS\|PROBE"
# Expected: no output

# Step 4 — Confirm driver registered but unbound
ls /sys/bus/platform/drivers/sensor_dts/
# Expected: bind  module  uevent  unbind  (no device symlink)

# Step 5 — Confirm compatible string
modinfo sensor_driver_dts.ko | grep alias
# Expected: alias: of:N*T*Ckotesh,sensor-deviceX

# Step 6 — Unload
sudo rmmod sensor_driver_dts
```

---

## ✅ Key Diagnostic Commands

```bash
# Most important — check if device symlink exists in driver dir
ls /sys/bus/platform/drivers/<driver>/
# Device symlink present = bound ✅
# Only bind/unbind/uevent/module = NOT bound ❌

# Check what compatible string driver expects
modinfo <module>.ko | grep alias

# Check what DTS says (inside QEMU/board)
cat /proc/device-tree/<node>/compatible

# Compare both — must be EXACTLY the same
# Even one character difference = silent failure
```

---

## 📌 Key Learning

- Compatible string mismatch = **completely silent** — no error, no warning
- `lsmod` showing module loaded does NOT mean probe() was called
- Always check `/sys/bus/platform/drivers/<drv>/` for device symlink
- `modinfo <module>.ko | grep alias` shows expected compatible string
- On real board: `cat /proc/device-tree/<node>/compatible` shows DTS string
- Compare strings **character by character** — case sensitive
- `MODULE_DEVICE_TABLE(of, ids)` exports compatible strings to `modinfo`

---

*Kotesh S — BSP Lab — Ch02 Exercise 1 — March 2026*
