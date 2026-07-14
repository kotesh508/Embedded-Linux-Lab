# Ch03 Exercise 3 – GPIO: Userspace Access and Kernel Ownership

## Objective
Understand GPIO ownership in Linux — a GPIO claimed by a kernel driver via
`devm_gpio_request()` cannot be accessed from userspace tools (`gpioget`, `gpioset`).
Learn to use `gpiodetect`, `gpioinfo`, `gpioget`, `gpioset` to verify GPIO state and
understand when userspace access is and is not permitted.

---

## Environment
| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| GPIO controller | ARM PL061 @ 0x9030000 (GPIOs 504–511) |
| GPIO used | GPIO 508 = gpiochip0 line 4 |
| Userspace tools | gpiodetect, gpioinfo, gpioget, gpioset (libgpiod) |
| Test method | Driver loaded → tools fail → driver unloaded → tools work |

---

## Symptom (Log Snippet)

```
# With driver loaded — GPIO owned by kernel
root@qemuarm64:~# gpioinfo gpiochip0
gpiochip0 - 8 lines:
    line   4: unnamed "kotesh-sensor-gpio" output active-high [used]

root@qemuarm64:~# gpioget gpiochip0 4
gpioget: error reading GPIO values: Device or resource busy

root@qemuarm64:~# gpioset gpiochip0 4=0
gpioset: error setting the GPIO line values: Device or resource busy
```

**Key observations:**
- `[used]` in gpioinfo — kernel driver holds exclusive ownership
- `Device or resource busy` — userspace cannot access a kernel-owned GPIO
- This is **correct behavior** — not a bug

---

## Stage Identification

```
devm_gpio_request(&pdev->dev, gpio, "kotesh-sensor-gpio")
  └── kernel marks GPIO 508 as OWNED
        └── /dev/gpiochip0 line 4 → [used]
              └── gpioget/gpioset attempt → EBUSY returned
                    └── userspace: "Device or resource busy"

rmmod sensor_driver_gpio
  └── devm_ cleanup → GPIO 508 released automatically
        └── /dev/gpiochip0 line 4 → unused
              └── gpioget/gpioset → SUCCESS
```

---

## Reproduction Steps

```bash
# Boot QEMU
~/BSP-Lab/boot_qemu.sh

# Inside QEMU:

# STEP 1 — Load driver, verify ownership
insmod /home/root/sensor_driver_gpio.ko
gpioinfo gpiochip0
# Expected: line 4 → "kotesh-sensor-gpio" output active-high [used]

# STEP 2 — Try userspace access while driver owns GPIO
gpioget gpiochip0 4
# Expected: gpioget: error reading GPIO values: Device or resource busy

gpioset gpiochip0 4=0
# Expected: gpioset: error setting the GPIO line values: Device or resource busy

# STEP 3 — Unload driver, GPIO released
rmmod sensor_driver_gpio
gpioinfo gpiochip0
# Expected: line 4 → unnamed  unused  output  active-high

# STEP 4 — Userspace access now works
gpioget gpiochip0 4
# Expected: 1  (last value set by driver was HIGH)

gpioset gpiochip0 4=1
cat /sys/kernel/debug/gpio
# Expected: gpio-508 not shown (released, no kernel owner)

gpioset gpiochip0 4=0
cat /sys/kernel/debug/gpio

# STEP 5 — Reload driver, ownership reclaimed
insmod /home/root/sensor_driver_gpio.ko
gpioget gpiochip0 4
# Expected: Device or resource busy — driver owns it again

cat /sys/kernel/debug/gpio
# Expected: gpio-508 (kotesh-sensor-gpio) out hi
```

---

## What I Checked ✔

```
✔ gpioinfo gpiochip0 (driver loaded)
  → line 4: "kotesh-sensor-gpio" output active-high [used]
  → [used] = kernel driver holds exclusive ownership via gpio_request()

✔ gpioget gpiochip0 4 (driver loaded)
  → Device or resource busy
  → EBUSY = kernel rejects userspace access to owned GPIO

✔ rmmod sensor_driver_gpio
  → [PROBE]: remove() called!
  → devm_gpio_request() auto-releases on remove — no manual free needed

✔ gpioinfo gpiochip0 (driver unloaded)
  → line 4: unnamed  unused  output  active-high
  → [used] gone — GPIO is free

✔ gpioget gpiochip0 4 (driver unloaded)
  → 1  (reads HIGH — last value set by driver before unload)

✔ gpioset gpiochip0 4=0 / 4=1 (driver unloaded)
  → Success — userspace can now toggle freely

✔ insmod sensor_driver_gpio.ko (reload)
  → probe() called, gpio 508 set OUTPUT HIGH
  → gpioget immediately fails with EBUSY — ownership reclaimed
```

---

## Full Output Reference

```
# Driver loaded — userspace blocked
root@qemuarm64:~# gpioinfo gpiochip0
    line   4: unnamed "kotesh-sensor-gpio" output active-high [used]

root@qemuarm64:~# gpioget gpiochip0 4
gpioget: error reading GPIO values: Device or resource busy

# Driver unloaded — userspace works
root@qemuarm64:~# rmmod sensor_driver_gpio
[ 1141.531666] Sensor GPIO [PROBE]: remove() called!

root@qemuarm64:~# gpioinfo gpiochip0
    line   4: unnamed  unused  output  active-high

root@qemuarm64:~# gpioget gpiochip0 4
1

root@qemuarm64:~# gpioset gpiochip0 4=1
root@qemuarm64:~# cat /sys/kernel/debug/gpio
gpiochip0: GPIOs 504-511, parent: amba/9030000.pl061, 9030000.pl061:
(empty — no kernel owner)

root@qemuarm64:~# gpioset gpiochip0 4=0

# Driver reloaded — ownership reclaimed
root@qemuarm64:~# insmod /home/root/sensor_driver_gpio.ko
[ 1142.207515] Sensor GPIO [PROBE]: probe() called!
[ 1142.208687] Sensor GPIO [FIXED]: gpio 508 set OUTPUT HIGH

root@qemuarm64:~# gpioget gpiochip0 4
gpioget: error reading GPIO values: Device or resource busy

root@qemuarm64:~# cat /sys/kernel/debug/gpio
    gpio-508 ( |kotesh-sensor-gpio ) out hi
```

---

## Root Cause Explanation

```c
/* In sensor_probe() */
devm_gpio_request(&pdev->dev, gpio, "kotesh-sensor-gpio");
```

`devm_gpio_request()` registers the GPIO as **exclusively owned** by the kernel driver.
The kernel GPIO subsystem marks it as `[used]` in the character device interface.

When userspace calls `gpioget` or `gpioset` via `/dev/gpiochip0`:
```
libgpiod → ioctl(GPIO_V2_LINE_REQUEST) → kernel checks ownership
         → GPIO already requested by driver → returns -EBUSY
         → userspace sees: "Device or resource busy"
```

When driver is removed, `devm_` cleanup automatically releases the GPIO:
```
rmmod → device_release() → devm cleanup → gpio_free(508)
      → GPIO marked as unused → userspace ioctl succeeds
```

---

## Interview Explanation

> "When a kernel driver calls `devm_gpio_request()`, it takes exclusive ownership of
> that GPIO line. Userspace tools like `gpioget` and `gpioset` from libgpiod cannot
> access it — they get `EBUSY`. I verified this by loading the driver, trying
> `gpioget gpiochip0 4` which failed, then unloading the driver and retrying —
> it worked immediately. `devm_gpio_request()` auto-releases on driver remove, so
> no manual `gpio_free()` is needed. The `gpioinfo` tool shows `[used]` when a
> kernel driver owns the line."

---

## Key Learning

- `devm_gpio_request()` gives **exclusive kernel ownership** — userspace is blocked
- `gpioinfo` shows `[used]` when kernel driver owns the GPIO line
- `Device or resource busy` = EBUSY = GPIO already claimed by kernel driver
- `devm_` prefix = automatic cleanup on driver remove — no manual `gpio_free()` needed
- After `rmmod`, GPIO is freed — `gpioget`/`gpioset` work immediately
- `gpiodetect` — lists all GPIO chips
- `gpioinfo [chip]` — shows all lines with direction, value, owner
- `gpioget [chip] [line]` — reads value (fails if kernel owns it)
- `gpioset [chip] [line=value]` — sets value (fails if kernel owns it)
- `/sys/kernel/debug/gpio` — shows only kernel-owned GPIOs with label
