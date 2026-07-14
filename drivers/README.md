# drivers/

Driver-level debugging labs, organized by bug class. `char_driver/` is the
main course — 10 chapters, each with multiple worked examples (`_Ex1`,
`_Ex2`, ...) showing the bug, the fix, and the verified-correct version.

## char_driver/ — chapter index

| Chapter | Topic |
|---|---|
| ch01_memory | NULL pointer: uninitialized, kmalloc fix, devm_kmalloc fix |
| ch02_device_tree | DTS compatible mismatch, host-vs-QEMU fix, QEMU-verified |
| ch03_gpio | Wrong direction, fixed direction, userspace ownership, pinmux DTS |
| ch04_irq | Wrong trigger type, fixed trigger, shared IRQ flag |
| ch05_character_device | Wrong major number, full fix set |
| ch06_memory_leak | kmalloc without kfree, full fix set, devm double-free |
| ch07_stack | Large local array, recursion panic, dump_stack reporter |
| ch08_userspace_interface | copy_to_user/copy_from_user exercises and proper debug flow |
| ch09_kconfig | Kconfig dependency exercises |
| ch10_boot_delay | Boot delay exercises |

## i2c_driver/ , pci_driver/ , platform_driver/
Work in progress — dedicated protocol/bus-specific driver examples beyond
the char_driver chapters above will be added here.
