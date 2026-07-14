# Ch03 Exercise 4 – GPIO: Pinmux DTS Node (Real Hardware Reference)

## Objective
Understand why GPIO pins on real SoCs (AM335x, iMX6, RPi) require pinmux configuration
in DTS before they work. Learn to add `pinctrl-names` and `pinctrl-0` properties to a
GPIO device node. Understand the error seen when pinmux is missing on real hardware.

> **Note:** QEMU virt machine has no pin mux hardware — pinctrl is not available
> (`/sys/kernel/debug/pinctrl` absent). This exercise is a real-hardware reference
> using AM335x (BeagleBone Black) as the target platform.

---

## Environment
| Item | Detail |
|---|---|
| Reference board | BeagleBone Black (AM335x SoC) |
| QEMU status | No pinctrl — `cat /sys/kernel/debug/pinctrl` → not found |
| Kernel | 5.15.x |
| DTS file | arch/arm/boot/dts/am335x-boneblack.dts |
| Pinctrl driver | pinctrl-single (AM335x) |

---

## What is Pinmux and Why is it Needed?

On real SoCs, each physical pin can serve multiple functions:

```
AM335x GPIO1_28 (pin P9_12):
  ├── Mode 0 → GPMC_BE1N     (memory bus)
  ├── Mode 1 → MMC1_SDCD     (SD card detect)
  ├── Mode 2 → ... 
  ├── Mode 7 → GPIO1_28      ← we want this
  └── Default at boot → Mode 0 (memory bus) — NOT GPIO!
```

Without pinmux configuration in DTS:
- Pin boots in wrong mode (e.g. memory bus)
- `gpio_direction_output()` call succeeds in kernel — no error
- But pin is physically not connected to GPIO block
- GPIO toggle has **no effect on the actual pin** — silent hardware bug

This is **worse than Ex1** — the kernel reports success but the hardware is wrong.

---

## Symptom on Real Hardware (Missing Pinmux)

```
# Driver loads cleanly — no errors
[   2.345678] Sensor GPIO [PROBE]: probe() called!
[   2.346123] Sensor GPIO: got gpio 60
[   2.347456] Sensor GPIO [FIXED]: gpio 60 set OUTPUT HIGH
[   2.348012] Sensor GPIO [PROBE]: Ready

# But oscilloscope on P9_12 shows: pin stuck at 0V
# LED connected to P9_12 never turns on
# gpio_direction_output() returned 0 — no error reported

# Check pinctrl state
cat /sys/kernel/debug/pinctrl/pinctrl-single/pins | grep -i "gpio1_28\|0x878"
# Shows: pin 110 (0x44e10878) function unknown — WRONG MODE
```

---

## DTS Node — Without Pinmux (BROKEN)

```dts
/* BROKEN — no pinctrl, pin stays in default mode */
kotesh-sensor-gpio {
    compatible = "kotesh,sensor-gpio";
    kotesh-gpio = <&gpio1 28 GPIO_ACTIVE_HIGH>;
    status = "okay";
    /* Missing: pinctrl-names and pinctrl-0 */
};
```

---

## DTS Node — With Pinmux (CORRECT for AM335x)

```dts
/* Step 1 — define pinmux state in &am33xx_pinmux */
&am33xx_pinmux {
    kotesh_sensor_gpio_pins: kotesh_sensor_gpio_pins {
        pinctrl-single,pins = <
            /*
             * P9_12 = AM335x GPIO1_28
             * Offset 0x878 in control module
             * Mode 7 = GPIO
             * PIN_OUTPUT_PULLDOWN = 0x07
             * 0x07 = mode7 | no pull-up | output
             */
            AM33XX_PADCONF(AM335X_PIN_GPMC_BE1N, PIN_OUTPUT_PULLDOWN, MUX_MODE7)
        >;
    };
};

/* Step 2 — reference pinmux state in device node */
kotesh-sensor-gpio {
    compatible = "kotesh,sensor-gpio";
    kotesh-gpio = <&gpio1 28 GPIO_ACTIVE_HIGH>;

    pinctrl-names = "default";          /* state name */
    pinctrl-0 = <&kotesh_sensor_gpio_pins>; /* state 0 = default */

    status = "okay";
};
```

---

## How Pinctrl Works at Probe Time

```
insmod sensor_driver_gpio.ko
  └── probe() called
        ├── pinctrl_get(dev)          → finds "default" state in DTS
        ├── pinctrl_lookup_state()    → finds kotesh_sensor_gpio_pins
        ├── pinctrl_select_state()    → writes 0x07 to register 0x44e10878
        │     └── pin P9_12 switched to GPIO mode (Mode 7)
        ├── of_get_named_gpio()       → returns gpio 60
        ├── devm_gpio_request()       → success
        └── gpio_direction_output()   → pin is now actually a GPIO ✔
```

Without pinctrl:
```
insmod sensor_driver_gpio.ko
  └── probe() called
        ├── (no pinctrl step — pin stays in Mode 0)
        ├── of_get_named_gpio()       → returns gpio 60
        ├── devm_gpio_request()       → success (kernel doesn't check mux)
        └── gpio_direction_output()   → success (kernel doesn't check mux)
              └── BUT: pin physically still in Mode 0 — not GPIO block
                    → toggle has NO effect on the physical pin
```

---

## Pinmux Register Values for AM335x GPIO

```
PIN_OUTPUT           = 0x00  (output, no pull)
PIN_OUTPUT_PULLUP    = 0x10  (output, pull-up enabled)
PIN_OUTPUT_PULLDOWN  = 0x08  (output, pull-down enabled)
PIN_INPUT            = 0x20  (input, no pull)
PIN_INPUT_PULLUP     = 0x37  (input, pull-up)
PIN_INPUT_PULLDOWN   = 0x27  (input, pull-down)

MUX_MODE0 = 0x0  (function 0)
MUX_MODE7 = 0x7  (GPIO on AM335x — always mode 7)

Combined example:
PIN_OUTPUT_PULLDOWN | MUX_MODE7 = 0x08 | 0x07 = 0x0F
```

---

## Verification on Real Hardware

```bash
# After loading driver with correct pinmux DTS:

# 1. Check pin is in GPIO mode
cat /sys/kernel/debug/pinctrl/pinctrl-single/pins | grep "0x878"
# Expected: pin 110 (0x44e10878) 0x0000000f function kotesh_sensor_gpio_pins

# 2. Check pinctrl state applied
cat /sys/kernel/debug/pinctrl/pinctrl-single/pingroups
# Expected: group: kotesh_sensor_gpio_pins

# 3. Check GPIO state
cat /sys/kernel/debug/gpio | grep "gpio-60"
# Expected: gpio-60 (kotesh-sensor-gpio) out hi

# 4. Physical verification
# LED on P9_12 should be ON
# Oscilloscope: 3.3V on pin
```

---

## QEMU Comparison

```
QEMU virt machine:
  ├── No physical pins — no pinmux hardware
  ├── /sys/kernel/debug/pinctrl → not found
  ├── GPIO works directly — no mux needed
  └── Good for testing GPIO API, NOT for testing pinmux

Real hardware (AM335x, iMX6, RPi):
  ├── Every pin has multiple functions
  ├── Pinmux MUST be configured before GPIO works
  ├── Missing pinmux = silent hardware failure
  └── Always add pinctrl-names + pinctrl-0 to GPIO device nodes
```

---

## Our QEMU DTS Node (No Pinmux Needed)

```dts
/* QEMU — no pinmux required, works as-is */
kotesh-sensor-gpio@20011000 {
    compatible = "kotesh,sensor-gpio";
    reg = <0x0 0x20011000 0x0 0x1000>;
    kotesh-gpio = <0x8004 0x04 0x00>;  /* pl061 phandle, pin 4, active high */
    status = "okay";
    /* No pinctrl needed — QEMU virt has no pin mux hardware */
};
```

---

## Interview Explanation

> "On real SoCs every physical pin can be configured for multiple functions — GPIO,
> UART, SPI, etc. Without pinmux configuration in DTS, the pin stays in its default
> boot mode which is usually not GPIO. The kernel driver calls
> `gpio_direction_output()` and gets success — but the pin is physically not connected
> to the GPIO block, so toggling it has no effect. This is a silent hardware bug.
> The fix is to add `pinctrl-names = default` and `pinctrl-0` referencing a pinmux
> state defined in `&am33xx_pinmux` that sets the pin to Mode 7 (GPIO mode on AM335x).
> QEMU doesn't have this issue because the virtual machine has no pin mux hardware."

---

## Key Learning

- Real SoCs require pinmux before GPIO works — QEMU does not
- Missing pinmux = `gpio_direction_output()` succeeds but pin has no effect — silent bug
- Always add `pinctrl-names = "default"` and `pinctrl-0` to GPIO device nodes on real hardware
- AM335x GPIO mode = MUX_MODE7 always
- `pinctrl-single,pins` format: `AM33XX_PADCONF(pin, pull_mode, mux_mode)`
- Verify pinmux applied: `/sys/kernel/debug/pinctrl/pinctrl-single/pins`
- Verify GPIO state: `/sys/kernel/debug/gpio`
- QEMU is good for GPIO API testing — real hardware needed for pinmux testing

---

## Ch03 Complete Summary

| Exercise | Topic | Key Command | Result |
|---|---|---|---|
| Ex1 | Wrong direction — `gpio_direction_input` + `set_value` | `cat /sys/kernel/debug/gpio` | `in lo` — silent bug |
| Ex2 | Fix — `gpio_direction_output(gpio, 1)` | `cat /sys/kernel/debug/gpio` | `out hi` — correct |
| Ex3 | Userspace ownership — `devm_gpio_request` blocks userspace | `gpioinfo gpiochip0` | `[used]` → EBUSY |
| Ex4 | Pinmux — real hardware requires mux config before GPIO works | `pinctrl/pins` debugfs | Mode 7 = GPIO |
