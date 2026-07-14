# Ch03 Exercise 2 – GPIO: Fix with gpio_direction_output

## Objective
Fix the Ex1 bug by replacing `gpio_direction_input()` + `gpio_set_value()` with the
correct single call `gpio_direction_output(gpio, initial_value)`. Verify the fix via
`/sys/kernel/debug/gpio` showing `out hi` — direction OUTPUT, value HIGH.

---

## Environment
| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| GPIO controller | ARM PL061 @ 0x9030000 (GPIOs 504–511) |
| Module | sensor_driver_gpio.ko (fixed) |
| GPIO used | GPIO 508 (pl061 pin 4) |
| Test method | insmod → debugfs verify → rmmod |

---

## Symptom (Ex1 Bug — what we fixed)

```
[  392.066623] Sensor GPIO [BUG]: set gpio 508 HIGH — but direction is INPUT!

root@qemuarm64:~# cat /sys/kernel/debug/gpio
gpiochip0: GPIOs 504-511, parent: amba/9030000.pl061, 9030000.pl061:
 gpio-508 (                    |kotesh-sensor-gpio  ) in  lo   ← INPUT, LOW
```

`gpio_set_value()` on an INPUT pin is silently ignored — no error, pin stays LOW.

---

## Fix Applied

```c
/* BEFORE — BUGGY */
gpio_direction_input(gpio);     /* sets INPUT */
gpio_set_value(gpio, 1);        /* silently ignored on INPUT pin */
pr_info("Sensor GPIO [BUG]: set gpio %d HIGH — but direction is INPUT!\n", gpio);

/* AFTER — FIXED */
ret = gpio_direction_output(gpio, 1);   /* sets OUTPUT + drives HIGH atomically */
if (ret) {
    pr_err("Sensor GPIO: direction_output failed %d\n", ret);
    return ret;
}
pr_info("Sensor GPIO [FIXED]: gpio %d set OUTPUT HIGH\n", gpio);
```

**Why `gpio_direction_output(gpio, value)` is correct:**
- Sets direction AND initial value in **one atomic call**
- No race window between direction set and value set
- Returns error code — failure is detectable
- `gpio_set_value()` is only valid **after** direction is already OUTPUT

---

## Verified Output (Fixed Driver)

```
root@qemuarm64:~# insmod /home/root/sensor_driver_gpio.ko
[  209.299030] Sensor GPIO [PROBE]: probe() called!
[  209.300942] Sensor GPIO: got gpio 508
[  209.302684] Sensor GPIO [FIXED]: gpio 508 set OUTPUT HIGH
[  209.303283] Sensor GPIO [PROBE]: Ready

root@qemuarm64:~# cat /sys/kernel/debug/gpio
gpiochip0: GPIOs 504-511, parent: amba/9030000.pl061, 9030000.pl061:
 gpio-508 (                    |kotesh-sensor-gpio  ) out hi   ← OUTPUT, HIGH ✅

root@qemuarm64:~# rmmod sensor_driver_gpio
[  209.784099] Sensor GPIO [PROBE]: remove() called!
```

---

## Stage Identification

```
insmod sensor_driver_gpio.ko (fixed)
  └── sensor_probe() called
        ├── of_get_named_gpio()          → returns 508        ✔
        ├── devm_gpio_request()          → success            ✔
        ├── gpio_direction_output(508,1) → OUTPUT + HIGH set  ✔ (fixed)
        ├── pr_info [FIXED] printed      → no [BUG] line      ✔
        └── probe returns 0
              └── debugfs: gpio-508 out hi                    ✔
```

---

## Reproduction Steps

```bash
# 1. Build fixed driver on host
cd ~/30days_workWith_BSP/my_projects/ch03_gpio
# Edit sensor_driver_gpio.c — replace direction_input+set_value with direction_output
make clean && make

# 2. Copy to QEMU rootfs
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp sensor_driver_gpio.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount

# 3. Boot QEMU
~/BSP-Lab/boot_qemu.sh

# 4. Inside QEMU — load fixed driver
insmod /home/root/sensor_driver_gpio.ko

# 5. Verify OUTPUT + HIGH
cat /sys/kernel/debug/gpio
# Expected: gpio-508 ( |kotesh-sensor-gpio ) out hi

# 6. Check dmesg — no [BUG] line
dmesg | grep "Sensor GPIO" | tail -5

# 7. Clean unload
rmmod sensor_driver_gpio
dmesg | grep "Sensor GPIO" | tail -3
```

---

## What I Checked ✔

```
✔ dmesg | grep "Sensor GPIO"
  → [FIXED]: gpio 508 set OUTPUT HIGH   — correct log, no [BUG] line

✔ cat /sys/kernel/debug/gpio
  → gpio-508 (kotesh-sensor-gpio) out hi
  → "out" = OUTPUT direction confirmed
  → "hi"  = value HIGH confirmed — gpio_direction_output worked

✔ rmmod sensor_driver_gpio
  → [PROBE]: remove() called! — clean unload
  → devm_gpio_request() auto-releases GPIO on remove (no manual free needed)

✔ Build: 0 — clean compile, no warnings
```

---

## Root Cause Comparison

| | Buggy (Ex1) | Fixed (Ex2) |
|---|---|---|
| Direction call | `gpio_direction_input(gpio)` | `gpio_direction_output(gpio, 1)` |
| Value call | `gpio_set_value(gpio, 1)` — ignored | Not needed — direction_output sets it |
| debugfs result | `in lo` — INPUT, LOW | `out hi` — OUTPUT, HIGH |
| Error detection | None — silent bug | `ret` checked, error logged |
| Atomicity | Two separate calls — race possible | Single call — atomic |

---

## Interview Explanation

> "The fix was to replace `gpio_direction_input()` + `gpio_set_value()` with a single
> `gpio_direction_output(gpio, 1)` call. This sets direction and initial value atomically.
> I verified the fix using `/sys/kernel/debug/gpio` — before the fix it showed `in lo`,
> after the fix it showed `out hi`. The key insight is that `gpio_set_value()` is only
> valid on pins already configured as output — calling it on an input pin is silently
> ignored by the kernel with no error."

---

## Key Learning

- `gpio_direction_output(gpio, value)` = direction + value in **one atomic call**
- `gpio_set_value()` is only for pins **already** configured as OUTPUT
- `devm_gpio_request()` auto-releases GPIO when device is removed — no manual free
- Always check return value of `gpio_direction_output()` — it can fail
- `/sys/kernel/debug/gpio` format: `gpio-N (label) [in|out] [lo|hi]`
- `in lo` = INPUT LOW | `in hi` = INPUT HIGH | `out lo` = OUTPUT LOW | `out hi` = OUTPUT HIGH
