# Ch04 Exercise 1 – IRQ: Wrong Trigger Flag (IRQF_TRIGGER_NONE)

## Objective
Demonstrate that registering an IRQ handler with `IRQF_TRIGGER_NONE` causes the handler
to **never fire** — no error at registration, no crash, but the interrupt is silently
never delivered. Verify using `/proc/interrupts` count staying at 0.

---

## Environment
| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| IRQ | 37 (GIC SPI 72, Edge) |
| Module | sensor_driver_irq.ko |
| DTS node | kotesh-sensor-irq@20012000 |
| Test method | insmod → /proc/interrupts → sleep → count stays 0 |

---

## Symptom (Log Snippet)

```
root@qemuarm64:~# insmod /home/root/sensor_driver_irq.ko
[  187.363457] Sensor IRQ [PROBE]: probe() called!
[  187.364287] Sensor IRQ: got irq 37
[  187.364835] Sensor IRQ [BUG]: registered with IRQF_TRIGGER_NONE — will never fire!
[  187.365319] Sensor IRQ [PROBE]: Ready, irq=37

root@qemuarm64:~# cat /proc/interrupts | grep kotesh
 37:          0     GIC-0  72 Edge      kotesh-sensor-irq

root@qemuarm64:~# sleep 3
root@qemuarm64:~# cat /proc/interrupts | grep kotesh
 37:          0     GIC-0  72 Edge      kotesh-sensor-irq

root@qemuarm64:~# dmesg | grep "HANDLER"
(no output)

root@qemuarm64:~# rmmod sensor_driver_irq
[  326.617233] Sensor IRQ [PROBE]: remove() called! total_count=0
```

**Key observations:**
- `devm_request_irq()` succeeded — no error returned
- `/proc/interrupts` count stays **0** after 3 seconds
- No `[HANDLER]` line in dmesg — handler never called
- `total_count=0` on remove — confirmed zero firings
- Silent bug — driver loads and runs but interrupt never works

---

## Stage Identification

```
insmod sensor_driver_irq.ko
  └── sensor_probe() called
        ├── platform_get_irq()     → returns 37          ✔
        ├── devm_request_irq(37, handler, IRQF_TRIGGER_NONE)
        │     └── registered OK — no error               ✔ (misleading)
        │     └── BUT: IRQF_TRIGGER_NONE = no edge/level trigger configured
        │           → GIC never delivers interrupt to handler
        └── probe returns 0

Hardware raises interrupt signal
  └── GIC checks trigger configuration
        └── IRQF_TRIGGER_NONE = no trigger type set
              → interrupt not delivered to handler
              → /proc/interrupts count stays 0
              → handler never called
```

---

## Reproduction Steps

```bash
# HOST — Build buggy driver
cd ~/30days_workWith_BSP/my_projects/ch04_irq

# Create buggy version with IRQF_TRIGGER_NONE
# Key bug line in sensor_probe():
#   ret = devm_request_irq(&pdev->dev, irq, sensor_irq_handler,
#                          IRQF_TRIGGER_NONE,       ← BUG
#                          "kotesh-sensor-irq", pdev);

make clean && make

# Copy to rootfs
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp sensor_driver_irq.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount

# Boot QEMU
~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU — observe silent bug
insmod /home/root/sensor_driver_irq.ko
dmesg | grep "Sensor IRQ" | tail -5

# Check count — should be 0 and stay 0
cat /proc/interrupts | grep kotesh
sleep 3
cat /proc/interrupts | grep kotesh

# Confirm handler never called
dmesg | grep "HANDLER" | tail -5

# Unload — total_count=0 confirms bug
rmmod sensor_driver_irq
dmesg | grep "Sensor IRQ" | tail -3

# IRQ released
cat /proc/interrupts | grep kotesh
```

---

## What I Checked ✔

```
✔ dmesg | grep "Sensor IRQ"
  → [BUG]: registered with IRQF_TRIGGER_NONE — will never fire!
  → probe() returned 0 — devm_request_irq() succeeded despite wrong flag

✔ cat /proc/interrupts | grep kotesh
  → 37: 0  GIC-0  72 Edge  kotesh-sensor-irq
  → count = 0 — confirmed no interrupts delivered

✔ sleep 3 && cat /proc/interrupts | grep kotesh
  → count still 0 — not a timing issue, handler genuinely never fires

✔ dmesg | grep "HANDLER"
  → no output — handler function never executed

✔ rmmod sensor_driver_irq
  → remove() called! total_count=0 — zero firings confirmed
  → IRQ entry disappears from /proc/interrupts — released cleanly
```

---

## Root Cause

```c
/* BUGGY CODE */
ret = devm_request_irq(&pdev->dev, irq, sensor_irq_handler,
                       IRQF_TRIGGER_NONE,    /* ← no trigger type */
                       "kotesh-sensor-irq", pdev);
```

`IRQF_TRIGGER_NONE` means "use the trigger type already configured in hardware/DTS".
On QEMU virt with GIC, if no trigger is pre-configured, the interrupt is never delivered.

Common trigger flags:
```
IRQF_TRIGGER_NONE    = 0x00  — use pre-configured trigger (often means never fires)
IRQF_TRIGGER_RISING  = 0x01  — fire on rising edge  ← correct for most sensors
IRQF_TRIGGER_FALLING = 0x02  — fire on falling edge
IRQF_TRIGGER_HIGH    = 0x04  — fire while signal is HIGH (level)
IRQF_TRIGGER_LOW     = 0x08  — fire while signal is LOW (level)
```

---

## Fix (Applied in Ex2)

```c
/* FIXED CODE */
ret = devm_request_irq(&pdev->dev, irq, sensor_irq_handler,
                       IRQF_TRIGGER_RISING,  /* ← correct trigger */
                       "kotesh-sensor-irq", pdev);
```

---

## sed -i Fix Commands

```bash
# Fix trigger flag
sed -i 's/IRQF_TRIGGER_NONE/IRQF_TRIGGER_RISING/' sensor_driver_irq.c

# Fix comment
sed -i '35s/.*/    \/* FIXED: IRQF_TRIGGER_RISING — IRQ fires on rising edge *\//' \
    sensor_driver_irq.c

# Fix log message
sed -i '44s/.*/    pr_info("Sensor IRQ [FIXED]: registered with IRQF_TRIGGER_RISING\\n");/' \
    sensor_driver_irq.c

# Fix MODULE_DESCRIPTION
sed -i 's/BUGGY IRQF_TRIGGER_NONE/FIXED IRQF_TRIGGER_RISING/' sensor_driver_irq.c

# Verify
grep -n "TRIGGER\|BUG\|FIXED\|DESCRIPTION" sensor_driver_irq.c
```

---

## Interview Explanation

> "The driver registered its IRQ handler with `IRQF_TRIGGER_NONE` — which means no
> trigger type is configured. The kernel accepted the registration without error but
> the GIC never delivered the interrupt. I confirmed this via `/proc/interrupts` where
> the count stayed at 0 even after waiting. The fix is to use `IRQF_TRIGGER_RISING`
> which tells the GIC to deliver the interrupt on a rising edge signal."

---

## Key Learning

- `devm_request_irq()` succeeds even with wrong trigger flag — silent bug
- `IRQF_TRIGGER_NONE` does NOT mean "any trigger" — it means use pre-configured
- Always specify explicit trigger: `IRQF_TRIGGER_RISING` or `IRQF_TRIGGER_FALLING`
- `/proc/interrupts` count = 0 after load = trigger flag wrong or IRQ not wired
- `/proc/irq/N/` directory shows IRQ details including handler name
- `devm_request_irq()` auto-frees IRQ on driver remove — no manual `free_irq()` needed
- GIC SPI interrupt format in DTS: `<0x00 SPI_NUM TRIGGER_TYPE>`
  - `0x01` = edge rising, `0x04` = level high
