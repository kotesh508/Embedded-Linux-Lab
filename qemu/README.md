# qemu/

Scripts to boot the lab kernel/rootfs in QEMU so every issue in this repo
can be reproduced without target hardware.

- `scripts/boot_qemu.sh` — boots the kernel + rootfs image used across the labs
- `scripts/bsp-session.sh` — sets up a full BSP debugging session (serial console, log capture)

Most `Issue_*.md` files reference one of these scripts directly in their
verification section.
