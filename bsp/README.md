# bsp/

Board Support Package level issues — everything between U-Boot handing off
to the kernel and a fully booted, driver-ready userspace.

## boot/
Boot-sequence failures: missing console, wrong root device, filesystem
built as a module instead of built-in, missing block driver, "no init
found." Each issue includes the exact boot log before/after the fix.
See `REPRODUCE_01_Boot_DTS_Driver_Issues.md` for the reproduction script.

## device-tree/
Device Tree issues that block a driver from binding: compatible-string
mismatches, disabled nodes, missing `reg`/interrupt properties, wrong
interrupt-cell format, missing clock/regulator references, missing
`CONFIG_OF`, and the full platform-driver probe cycle. See
`REPRODUCE_03a_Panic_Issues_01to05.md` for the reproduction script.

## kernel-build/ , petalinux/ , rootfs/
Work in progress — kernel build configuration notes, PetaLinux-specific
BSP notes, and root filesystem construction notes will be added here.
