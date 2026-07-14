# Issue 08 --- Ex1: User Space Communication (Device Creation + Read Path Debug)

## Chapter

Ch08 --- User Space Communication

## Exercise

Ex1 --- Character driver read() path + device node creation issue

------------------------------------------------------------------------

## 1. Objective

Understand complete flow: User → Device Node → VFS → Driver →
copy_to_user()

And debug failure when device node is missing.

------------------------------------------------------------------------

## 2. Concept --- End-to-End Data Flow

User Space: cat /dev/sensor_dev ↓ Device Node (/dev) ↓ VFS
(file_operations) ↓ sensor_read() ↓ copy_to_user() ↓ User receives data

------------------------------------------------------------------------

## 3. Environment

  Item       Value
  ---------- ------------------------
  Platform   QEMU qemuarm64
  Kernel     5.15.194
  Driver     sensor_driver_usercomm
  Major      249

------------------------------------------------------------------------

## 4. Step-by-Step Debugging

### Step 1 --- Load Driver

Command: insmod sensor_driver_usercomm.ko

Observed: \[ 261.507262\] Sensor \[INIT\]: major=249

Analysis: - Driver loaded successfully - Major number allocated
dynamically

------------------------------------------------------------------------

### Step 2 --- Attempt Device Creation (FAILED)

Command: mknod /dev/sensor_dev c `<major>`{=html} 0

Observed Error: -sh: can't open major: no such file

------------------------------------------------------------------------

## 5. Root Cause Analysis

Problem: - `<major>` is placeholder, NOT shell variable - Shell
interprets `< >` as input redirection

Impact: - Device node NOT created - No connection between user space and
driver

------------------------------------------------------------------------

### Step 3 --- Verify Failure

Command: cat /dev/sensor_dev

Observed: No such file or directory

Conclusion: - read() NOT triggered - Driver path not reached

------------------------------------------------------------------------

### Step 4 --- Fix Device Creation

Command: mknod /dev/sensor_dev c 249 0

Verification: ls -l /dev/sensor_dev

Expected: crw-r--r-- 1 root root 249, 0

------------------------------------------------------------------------

### Step 5 --- Trigger read()

Command: cat /dev/sensor_dev

Observed Output:

\[ 419.839901\] Sensor \[READ\]: called sensor_value=42 \[ 419.841317\]
Sensor \[READ\]: called

------------------------------------------------------------------------

## 6. Deep Observation

### Why read() called twice?

cat internally does:

while (read() \> 0)

Sequence: 1. First read → returns data 2. Second read → returns 0 (EOF
check)

Conclusion: - This is expected VFS behavior - NOT a bug

------------------------------------------------------------------------

## 7. Data Flow Verification

Kernel: kernel_buffer = "sensor_value=42"

Flow: kernel_buffer → copy_to_user → user buffer

Output: sensor_value=42

✔ Data integrity confirmed

------------------------------------------------------------------------

## 8. Debug Checklist

  Check                   Status
  ----------------------- --------
  Driver loaded           ✅
  Major number captured   ✅
  Device node created     ✅
  read() triggered        ✅
  Data correct            ✅

------------------------------------------------------------------------

## 9. Key Learnings

1.  Device node is mandatory for user ↔ kernel communication
2.  Major number must be taken from dmesg
3.  Shell placeholders are not variables
4.  read() can be invoked multiple times
5.  copy_to_user safely transfers data

------------------------------------------------------------------------

## 10. Real-World Insight

This issue represents a common scenario:

Driver works correctly\
But user-space interface fails due to missing device node

------------------------------------------------------------------------

## 11. Next Step

Proceed to Ex2: User pointer misuse (copy_from_user bug)
