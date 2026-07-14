# Ch03 Exercise 1 – GPIO: Wrong Direction Before gpio_set_value

## Objective
Demonstrate that calling `gpio_set_value()` on a GPIO pin that is still configured as
**INPUT** produces no effect — no error, no crash, but the pin stays LOW. Understand why
the kernel silently ignores the call and how to read the evidence from debugfs.

---

## Environment
| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| GPIO controller | ARM PL061 @ 0x9030000 (GPIOs 504–511) |
| Module | sensor_driver_gpio.ko |
| GPIO used | GPIO 508 (pl061 pin 4) |
| Test method | insmod → debugfs → rmmod |

---

## Symptom (Log Snippet)

```
root@qemuarm64:~# insmod /home/root/sensor_driver_gpio.ko
[  392.063162] Sensor GPIO [PROBE]: probe() called!
[  392.064708] Sensor GPIO: got gpio 508
[  392.066623] Sensor GPIO [BUG]: set gpio 508 HIGH — but direction is INPUT!
[  392.069337] Sensor GPIO [PROBE]: Ready

root@qemuarm64:~# cat /sys/kernel/debug/gpio
gpiochip0: GPIOs 504-511, parent: amba/9030000.pl061, 9030000.pl061:
 gpio-508 (                    |kotesh-sensor-gpio  ) in  lo
```

**Key observations:**

- `[BUG]` line printed — driver itself detected and logged the bug
- `gpio-508 … in lo` — direction is **in** (INPUT), value is **lo** (LOW)
- `gpio_set_value(508, 1)` was called — yet value stayed **lo**
- No kernel error, no crash — silent wrong behavior

---

## Stage Identification

```
insmod sensor_driver_gpio.ko
  └── module_platform_driver() registers driver
        └── kernel matches compatible "kotesh,sensor-gpio" → DTS node found
              └── sensor_probe() called
                    ├── of_get_named_gpio()       → returns 508  ✔
                    ├── devm_gpio_request()        → success      ✔
                    ├── gpio_direction_input(508)  → sets INPUT   ✔ (wrong)
                    ├── gpio_set_value(508, 1)     → IGNORED      ✗ (bug)
                    └── probe returns 0 — no error reported
```

---

## Reproduction Steps

```bash
# 1. Boot QEMU with updated DTB (kotesh-sensor-gpio node present)
~/BSP-Lab/boot_qemu.sh

# 2. Inside QEMU — check GPIO controller available
cat /sys/kernel/debug/gpio
# Expected: gpiochip0: GPIOs 504-511, parent: amba/9030000.pl061

# 3. Load buggy driver
insmod /home/root/sensor_driver_gpio.ko

# 4. Check GPIO state — should show INPUT + LOW despite set_value call
cat /sys/kernel/debug/gpio

# 5. Verify driver bound
ls /sys/bus/platform/drivers/sensor_gpio/

# 6. Unload
rmmod sensor_driver_gpio
dmesg | grep "Sensor GPIO"
```

---

## What I Checked ✔

```
✔ cat /sys/kernel/debug/gpio
  → gpio-508 (kotesh-sensor-gpio) in lo
  → "in" = INPUT direction confirmed
  → "lo" = value LOW confirmed — gpio_set_value had NO effect

✔ ls /sys/bus/platform/drivers/sensor_gpio/
  → 20011000.kotesh-sensor-gpio bind module uevent unbind
  → device IS bound — probe() ran successfully

✔ dmesg | grep "Sensor GPIO"
  → [BUG] line present — driver itself flagged the wrong direction
  → probe returned 0 — kernel saw no error (silent bug)

✔ rmmod sensor_driver_gpio
  → [PROBE]: remove() called! — clean unload
  → no crash, no panic — bug is behavioral, not fatal
```

---

## Root Cause

```c
/* BUGGY CODE in sensor_probe() */
gpio_direction_input(gpio);     /* ← sets direction = INPUT */
gpio_set_value(gpio, 1);        /* ← called on INPUT pin — silently ignored */
```

`gpio_set_value()` in the Linux kernel checks the pin direction internally.
If the pin is INPUT, the call is a **no-op** — no error returned, no warning printed.

The kernel GPIO subsystem behavior:
```
gpio_set_value(n, 1) on INPUT pin
  → gpio_chip->set() not called
  → pin stays at whatever the external signal drives it to
  → debugfs shows "in lo" — direction unchanged, value unchanged
```

This is a **silent behavioral bug** — the driver loads successfully, probe returns 0,
but the hardware is not in the expected state. On real hardware this would mean:
- A sensor power pin stays LOW when it should be HIGH
- Sensor never powers on
- Driver appears to work but sensor data is always zero/garbage

---

## Fix

The fix is to call `gpio_direction_output()` **instead of** `gpio_direction_input()`.
`gpio_direction_output(gpio, value)` sets direction AND drives the pin in one call:

```c
/* FIXED CODE */
ret = gpio_direction_output(gpio, 1);   /* sets OUTPUT + drives HIGH atomically */
if (ret) {
    pr_err("Sensor GPIO: direction_output failed %d\n", ret);
    return ret;
}
pr_info("Sensor GPIO [FIXED]: gpio %d set to OUTPUT HIGH\n", gpio);
/* gpio_set_value() NOT needed — direction_output already set the value */
```

**Why `gpio_direction_output(gpio, value)` is correct:**
- Second argument is the **initial value** — sets direction and value atomically
- No race between direction set and value set
- Returns error code — you can check and handle failure
- `gpio_set_value()` is only for pins already configured as output

---

## Interview Explanation

> "The driver called `gpio_direction_input()` then `gpio_set_value()` — which is a
> silent no-op. The kernel ignores `set_value` on input pins without any error.
> I confirmed it via `/sys/kernel/debug/gpio` which showed `in lo` — direction INPUT,
> value LOW — despite the set call. The fix is `gpio_direction_output(gpio, 1)` which
> sets direction and initial value atomically in one call."

---

## Key Learning

- `gpio_set_value()` on an INPUT pin is **silently ignored** — no error, no crash
- Always use `gpio_direction_output(gpio, initial_value)` to configure output pins
- `gpio_direction_output()` takes initial value as 2nd argument — no separate `set_value` needed at init
- `/sys/kernel/debug/gpio` is the primary tool to verify GPIO direction and value state
- `in lo` = INPUT direction, LOW value | `out hi` = OUTPUT direction, HIGH value
- Silent bugs are harder to find than crashes — always verify GPIO state via debugfs
- On real hardware this bug would mean a powered peripheral never receives power

---

## Mistakes Made During This Exercise

| Mistake | What Happened | Lesson |
|---|---|---|
| CONFIG_GPIO_PL061 not enabled | pl061 not probed, sensor driver deferred | Always check kernel config before testing GPIO drivers |
| Probe deferred silently | `devices_deferred` showed `supplier 9030000.pl061 not ready` | Check `/sys/kernel/debug/devices_deferred` when probe doesn't fire |
| `/sys/class/gpio` missing | CONFIG_GPIO_CDEV_V1 present but sysfs export failed | debugfs gpio is more reliable than sysfs for verification |
| Built .ko for x86 first | `Invalid architecture in ELF header: 62` | Always cross-compile with `ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-` for QEMU |
