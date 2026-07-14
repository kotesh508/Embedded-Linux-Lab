# Ch04 Exercise 3 – IRQ: Shared IRQ and Missing IRQF_SHARED

## Objective
Demonstrate that two drivers cannot share the same IRQ line unless **both** register
with `IRQF_SHARED`. When one driver is missing it, the second driver's `request_irq()`
returns `-EBUSY` (-16) and probe fails. Fix both drivers to use `IRQF_SHARED` and
verify both appear on the same IRQ line in `/proc/interrupts`.

---

## Environment
| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| Shared IRQ | 37 (GIC SPI 72, Edge) |
| Driver 1 | sensor_driver_irq.ko — kotesh-sensor-irq@20012000 |
| Driver 2 | sensor_driver_irq2.ko — kotesh-sensor-irq2@20013000 |
| Test method | Load driver1 → load driver2 → check /proc/interrupts |

---

## Symptom (Log Snippet — BUGGY)

```
root@qemuarm64:~# insmod /home/root/sensor_driver_irq.ko
[  157.738180] Sensor IRQ [FIXED]: registered with IRQF_TRIGGER_RISING
[  157.738627] Sensor IRQ [PROBE]: Ready, irq=37, simulating every 500ms

root@qemuarm64:~# insmod /home/root/sensor_driver_irq2.ko
[  158.070116] Sensor IRQ2 [PROBE]: probe() called!
[  158.070757] Sensor IRQ2: got irq 37
[  158.072512] genirq: Flags mismatch irq 37. 00000001 (kotesh-sensor-irq2) vs. 00000001 (kotesh-sensor-irq)
[  158.073358] Sensor IRQ2 [BUG]: request_irq failed -16 — missing IRQF_SHARED!
[  158.073845] sensor_irq2: probe of 20013000.kotesh-sensor-irq2 failed with error -16

root@qemuarm64:~# cat /proc/interrupts | grep kotesh
 37:          0     GIC-0  72 Edge      kotesh-sensor-irq
```

**Key observations:**
- `genirq: Flags mismatch irq 37` — kernel detected flag incompatibility
- `request_irq failed -16` = `-EBUSY` — IRQ sharing rejected
- Only `kotesh-sensor-irq` in `/proc/interrupts` — driver2 never registered
- `probe failed with error -16` — driver2 device not bound

---

## Stage Identification

```
insmod sensor_driver_irq.ko
  └── devm_request_irq(37, IRQF_TRIGGER_RISING)
        └── registered OK — but WITHOUT IRQF_SHARED
              └── IRQ 37 marked as "non-shared"

insmod sensor_driver_irq2.ko
  └── devm_request_irq(37, IRQF_TRIGGER_RISING)
        └── kernel checks: existing owner has no IRQF_SHARED
              └── genirq: Flags mismatch → returns -EBUSY
                    └── probe() returns -16 → device not bound
```

---

## Root Cause

```c
/* DRIVER 1 — BUGGY */
ret = devm_request_irq(&pdev->dev, irq, sensor_irq_handler,
                       IRQF_TRIGGER_RISING,        /* missing IRQF_SHARED */
                       "kotesh-sensor-irq", pdev);

/* DRIVER 2 — BUGGY */
ret = devm_request_irq(&pdev->dev, irq, sensor_irq2_handler,
                       IRQF_TRIGGER_RISING,        /* missing IRQF_SHARED */
                       "kotesh-sensor-irq2", pdev);
```

Linux IRQ sharing rules:
```
Rule 1: If IRQ is already registered WITHOUT IRQF_SHARED
        → any new request_irq() on same IRQ returns -EBUSY

Rule 2: If IRQ is registered WITH IRQF_SHARED
        → other drivers CAN share it IF they also use IRQF_SHARED

Rule 3: BOTH drivers must use IRQF_SHARED — one is not enough
```

The `genirq: Flags mismatch` message means:
```
Existing:  IRQF_TRIGGER_RISING (0x00000001) — no IRQF_SHARED (0x80000000)
New:       IRQF_TRIGGER_RISING (0x00000001) — no IRQF_SHARED
Result:    Neither has IRQF_SHARED → mismatch → -EBUSY
```

---

## Fix

```c
/* DRIVER 1 — FIXED */
ret = devm_request_irq(&pdev->dev, irq, sensor_irq_handler,
                       IRQF_TRIGGER_RISING | IRQF_SHARED,  /* FIXED */
                       "kotesh-sensor-irq", pdev);

/* DRIVER 2 — FIXED */
ret = devm_request_irq(&pdev->dev, irq, sensor_irq2_handler,
                       IRQF_TRIGGER_RISING | IRQF_SHARED,  /* FIXED */
                       "kotesh-sensor-irq2", pdev);
```

---

## sed -i Fix Commands

```bash
# Fix driver1 — add IRQF_SHARED
sed -i 's/IRQF_TRIGGER_RISING,/IRQF_TRIGGER_RISING | IRQF_SHARED,/' \
    sensor_driver_irq.c

# Fix driver2 — add IRQF_SHARED
sed -i 's/IRQF_TRIGGER_RISING,.*\/\* no IRQF_SHARED \*\//IRQF_TRIGGER_RISING | IRQF_SHARED, \/* FIXED *\//' \
    sensor_driver_irq2.c

# Fix driver2 comment
sed -i '32s/.*/    \/* FIXED: IRQF_SHARED allows both drivers to share IRQ 37 *\//' \
    sensor_driver_irq2.c

# Fix driver2 error log
sed -i '37s/.*/        pr_err("Sensor IRQ2 [BUG]: request_irq failed %d — add IRQF_SHARED to both drivers!\\n", ret);/' \
    sensor_driver_irq2.c

# Fix driver2 description
sed -i 's/BUGGY missing IRQF_SHARED/FIXED with IRQF_SHARED/' sensor_driver_irq2.c

# Verify both
grep -n "IRQF\|BUG\|FIXED" sensor_driver_irq.c
grep -n "IRQF\|BUG\|FIXED" sensor_driver_irq2.c
```

---

## Verified Output (Fixed)

```
root@qemuarm64:~# insmod /home/root/sensor_driver_irq.ko
[  180.060464] Sensor IRQ [FIXED]: registered with IRQF_TRIGGER_RISING
[  180.061003] Sensor IRQ [PROBE]: Ready, irq=37, simulating every 500ms

root@qemuarm64:~# insmod /home/root/sensor_driver_irq2.ko
[  180.335626] Sensor IRQ2 [FIXED]: registered with IRQF_SHARED, sharing irq 37
[  180.336052] Sensor IRQ2 [PROBE]: Ready, irq=37

root@qemuarm64:~# cat /proc/interrupts | grep kotesh
 37:          0     GIC-0  72 Edge      kotesh-sensor-irq, kotesh-sensor-irq2

root@qemuarm64:~# rmmod sensor_driver_irq2
[  180.704602] Sensor IRQ2 [PROBE]: remove() called!

root@qemuarm64:~# rmmod sensor_driver_irq
[  180.773045] Sensor IRQ [PROBE]: remove() called! total_count=1
```

**Key proof:**
```
37: 0  GIC-0  72 Edge  kotesh-sensor-irq, kotesh-sensor-irq2
                        ↑ driver1              ↑ driver2
Both on same IRQ line — sharing confirmed ✅
```

---

## Reproduction Steps

```bash
# HOST — Build both drivers
cd ~/30days_workWith_BSP/my_projects/ch04_irq
make clean && make
echo "Build: $?"
ls *.ko

# Deploy both to rootfs
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp sensor_driver_irq.ko /tmp/qemu-mount/home/root/
sudo cp sensor_driver_irq2.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount

~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — BUGGY test (revert to IRQF_TRIGGER_NONE first to reproduce)
# Or just observe the [BUG] log from when driver2 probe fails

# FIXED test
insmod /home/root/sensor_driver_irq.ko
dmesg | grep "Sensor IRQ" | tail -3

insmod /home/root/sensor_driver_irq2.ko
dmesg | grep "Sensor IRQ2" | tail -4

# KEY CHECK — both on same IRQ line
cat /proc/interrupts | grep kotesh
# Expected: 37: 0  GIC-0  72 Edge  kotesh-sensor-irq, kotesh-sensor-irq2

# Unload in reverse order
rmmod sensor_driver_irq2
rmmod sensor_driver_irq
dmesg | grep "remove\|total_count" | tail -4
```

---

## What I Checked ✔

```
✔ genirq: Flags mismatch irq 37 (buggy)
  → kernel detected missing IRQF_SHARED on existing owner
  → new request_irq() returned -EBUSY (-16)

✔ probe of 20013000.kotesh-sensor-irq2 failed with error -16 (buggy)
  → driver2 device never bound

✔ cat /proc/interrupts | grep kotesh (fixed)
  → 37: 0  GIC-0  72 Edge  kotesh-sensor-irq, kotesh-sensor-irq2
  → BOTH drivers on same line — sharing confirmed ✅

✔ rmmod sensor_driver_irq2 → remove() called (fixed)
  → clean unload, devm auto-releases IRQ share

✔ rmmod sensor_driver_irq → total_count=1 (fixed)
  → driver1 also unloads cleanly
```

---

## Interview Explanation

> "Two drivers tried to share IRQ 37 but driver1 registered without `IRQF_SHARED`.
> When driver2 tried to register the same IRQ, the kernel printed
> `genirq: Flags mismatch` and returned `-EBUSY`. The fix requires BOTH drivers to
> use `IRQF_TRIGGER_RISING | IRQF_SHARED`. After the fix, `/proc/interrupts` showed
> both `kotesh-sensor-irq` and `kotesh-sensor-irq2` on the same IRQ 37 line,
> confirming successful sharing. The key rule is: all drivers sharing an IRQ must
> ALL register with `IRQF_SHARED` — one driver having it is not enough."

---

## Key Learning

- `IRQF_SHARED` must be set by **ALL** drivers sharing an IRQ — not just one
- Missing `IRQF_SHARED` on either driver → `-EBUSY` on second `request_irq()`
- `genirq: Flags mismatch` = shared IRQ flag mismatch — always check this line
- `-EBUSY` (-16) from `request_irq()` = IRQ already owned without sharing
- `/proc/interrupts` shows comma-separated handlers when IRQ is shared
- `devm_request_irq()` auto-releases on remove for each driver independently
- Unload order matters: unload drivers in reverse load order for shared IRQs
- On real hardware: shared IRQs common on legacy PCI devices, rare on modern SoCs

## Ch04 Complete Summary

| Exercise | Topic | Key Error | Fix |
|---|---|---|---|
| Ex1 | `IRQF_TRIGGER_NONE` | Handler never fires, count=0 | Use `IRQF_TRIGGER_RISING` |
| Ex2 | Fix + irq_work simulation | — | `IRQF_TRIGGER_RISING` + hrtimer |
| Ex3 | Missing `IRQF_SHARED` | `genirq: Flags mismatch`, -EBUSY | Add `IRQF_SHARED` to both drivers |
