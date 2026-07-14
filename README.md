# Embedded Linux Lab

A structured, hands-on lab for Embedded Linux / BSP / System Integration
engineering — built while preparing for 3–5 year experience-level interviews.

Every issue in this repo follows the same format: **problem statement →
normal flow → broken flow → root-cause investigation → fix → verification
on QEMU/hardware**. Nothing here is theory-only; every issue was reproduced
and fixed, not just described.

## Repository layout

| Folder | What's inside |
|---|---|
| [`bsp/`](bsp/) | Boot process and Device Tree issues — console, rootfs, DTS compatible/interrupt/clock/regulator problems |
| [`drivers/`](drivers/) | Character, platform, I2C, and PCI driver labs — 10 chapters from NULL pointers through boot delay |
| [`kernel/`](kernel/) | Advanced kernel debugging — race conditions, deadlocks, memory corruption, DMA, panic analysis |
| [`protocols/`](protocols/) | SPI / I2C / UART / PCIe protocol notes and driver-level exercises |
| [`qemu/`](qemu/) | Scripts to boot and reproduce every issue above inside QEMU |
| [`debugging/`](debugging/) | Reference sheet of debug commands (dmesg, ftrace, KASAN, lockdep, etc.) used across the labs |
| [`yocto/`](yocto/) | Yocto/BitBake build, layer, and patch workflow notes |
| [`busybox/`](busybox/) | BusyBox rootfs configuration notes |
| [`projects/`](projects/) | End-to-end project write-ups combining multiple issues |
| [`interview/`](interview/) | Interview question banks and mock-interview notes |
| [`docs/`](docs/) | BSP diagnostic reference and other cross-cutting docs |
| [`scripts/`](scripts/) | Helper/automation scripts |
| [`tests/`](tests/) | Test harnesses |
| [`archive/`](archive/) | Older/deprecated material kept for reference |

## How each issue is documented

Every `Issue_NN_*.md` file follows:

1. **Problem statement** — the symptom, exactly as a tester/customer would report it
2. **Normal flow** — how the subsystem is supposed to behave
3. **Broken flow** — where and why it diverges
4. **Investigation** — exact commands/tools used (dmesg, sysfs, debugfs, KASAN, lockdep, ftrace, etc.)
5. **Fix** — the actual code/config change
6. **Verification** — how the fix was confirmed (QEMU boot log, repeated stress test, etc.)

## Environment

- Kernel: Linux 6.6
- Build system: Yocto / BitBake
- Reproduction: QEMU (see [`qemu/`](qemu/)) plus target hardware where noted
- Workflow: `devtool modify` → `devtool build` → verify → `devtool finish` → patch added to layer recipe

## About

Maintained by Kotesh as part of Embedded Linux / BSP Engineer interview preparation.
Issues are added continuously as new debugging scenarios are practiced.
