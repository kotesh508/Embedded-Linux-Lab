#!/usr/bin/env bash
# finalize_repo.sh
# Run this from inside ~/Embedded-Linux-Lab (the repo root).
#   cd ~/Embedded-Linux-Lab
#   bash finalize_repo.sh
#
# What it does:
#   1. Removes the duplicate ch01 files sitting loose in drivers/char_driver/
#   2. Creates/updates a README.md in every major folder and every empty leaf folder
#   3. Leaves git add/commit/push as a manual final step (printed at the end)

set -e

if [ ! -f "README.md" ]; then
  echo "ERROR: run this from the repo root (README.md not found here)."
  echo "cd ~/Embedded-Linux-Lab && bash finalize_repo.sh"
  exit 1
fi

echo "==> Step 1: removing duplicate files from drivers/char_driver/"
rm -f drivers/char_driver/Issue_01_Ex1_NULL_Ptr_Uninitialized.md
rm -f drivers/char_driver/Issue_01_Ex2_NULL_Ptr_kmalloc_Fix.md
rm -f drivers/char_driver/Issue_01_Ex3_NULL_Ptr_devm_kmalloc.md
echo "    done (originals kept under drivers/char_driver/ch01_memory/)"

echo "==> Step 2: writing README.md files"

mkdir -p yocto busybox projects kernel/memory kernel/driver_probe \
         protocols/i2c protocols/spi protocols/uart protocols/pcie \
         archive interview scripts tests \
         bsp/kernel-build bsp/petalinux bsp/rootfs \
         debugging/kernel_logs \
         drivers/i2c_driver drivers/pci_driver drivers/platform_driver

# ---------------------------------------------------------------------------
# Root README
# ---------------------------------------------------------------------------
cat > README.md << 'EOF'
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
EOF

# ---------------------------------------------------------------------------
# bsp/
# ---------------------------------------------------------------------------
cat > bsp/README.md << 'EOF'
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
EOF

# ---------------------------------------------------------------------------
# drivers/
# ---------------------------------------------------------------------------
cat > drivers/README.md << 'EOF'
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
EOF

# ---------------------------------------------------------------------------
# kernel/
# ---------------------------------------------------------------------------
cat > kernel/README.md << 'EOF'
# kernel/

Advanced, concurrency- and crash-level kernel debugging — the hardest tier
of the lab, built on top of the driver fundamentals in `drivers/`.

## advanced_debugging/
Race conditions, deadlocks, memory corruption, DMA issues, panic analysis,
and spinlock misuse, each as a full exercise set. `Issue_08_Ch08_Spinlock_QEMU_Verified.md`
and `Issue_05_Ch05_Panic_Analysis_QEMU_Verified.md` are confirmed-working
reproductions on QEMU. `REPRODUCE_Book2_All_Chapters.sh` reruns the full set.

## panic_analysis/
Ten focused panic scenarios: NULL pointer dereference, stack overflow,
BUG_ON/WARN_ON, divide-by-zero, hung task, Oops-vs-panic distinction,
use-after-free, double-free, OOM, and unaligned access. Reproduction
scripts: `REPRODUCE_03b_Panic_Issues_06to10.md`.

## memory/ , driver_probe/
Work in progress — dedicated memory-management and probe-lifecycle deep
dives will be added here as separate focus areas from the panic/advanced
chapters above.
EOF

# ---------------------------------------------------------------------------
# qemu/
# ---------------------------------------------------------------------------
cat > qemu/README.md << 'EOF'
# qemu/

Scripts to boot the lab kernel/rootfs in QEMU so every issue in this repo
can be reproduced without target hardware.

- `scripts/boot_qemu.sh` — boots the kernel + rootfs image used across the labs
- `scripts/bsp-session.sh` — sets up a full BSP debugging session (serial console, log capture)

Most `Issue_*.md` files reference one of these scripts directly in their
verification section.
EOF

# ---------------------------------------------------------------------------
# protocols/
# ---------------------------------------------------------------------------
cat > protocols/README.md << 'EOF'
# protocols/

Bus/protocol-level notes and driver exercises, separate from the generic
char_driver chapters — focused on protocol-specific debugging (bad ACKs,
wrong clock speed, transfer framing, etc.).

- `i2c/` — I2C driver and bus-transaction debugging (WIP)
- `spi/` — SPI transfer debugging (WIP)
- `uart/` — UART/console debugging (WIP)
- `pcie/` — PCIe enumeration/BAR debugging (WIP)
EOF

for p in i2c spi uart pcie; do
cat > protocols/$p/README.md << EOF
# protocols/$p/

Work in progress. Will contain $p-specific driver debugging exercises
following the same format as \`drivers/char_driver/\`: problem statement,
normal flow, broken flow, investigation, fix, verification.
EOF
done

# ---------------------------------------------------------------------------
# debugging/
# ---------------------------------------------------------------------------
cat > debugging/README.md << 'EOF'
# debugging/

Cross-cutting debugging reference used across every lab in this repo.

- `debug_commands/DEBUG_COMMANDS_REFERENCE.md` — the full command/tool
  reference: dmesg, sysfs/debugfs paths, KASAN, kmemleak, lockdep, KCSAN,
  ftrace, initcall_debug, and more — indexed by which bug class each tool catches.
- `kernel_logs/` — captured boot/panic logs referenced from individual issues (WIP)
EOF

cat > debugging/kernel_logs/README.md << 'EOF'
# debugging/kernel_logs/

Work in progress. Raw dmesg/panic log captures referenced from individual
`Issue_*.md` files will be stored here for reproducibility.
EOF

# ---------------------------------------------------------------------------
# WIP-only folders
# ---------------------------------------------------------------------------
cat > yocto/README.md << 'EOF'
# yocto/

Work in progress. Yocto/BitBake workflow notes: layers, recipes, `devtool
modify` / `devtool finish` patch workflow, image customization — the build
system used to turn every fix in this repo into a deployable patch.
EOF

cat > busybox/README.md << 'EOF'
# busybox/

Work in progress. BusyBox rootfs configuration notes used by the QEMU
reproduction environment in `qemu/`.
EOF

cat > projects/README.md << 'EOF'
# projects/

End-to-end project write-ups that combine multiple issues from `bsp/`,
`drivers/`, and `kernel/` into a single realistic engineering task —
closer to how a real interview panel presents a bug ("RTC not working on
new board") rather than an isolated chapter.
EOF

cat > interview/README.md << 'EOF'
# interview/

Interview question banks and mock-interview notes for Embedded Linux /
BSP / System Integration Engineer roles (3–5 years experience), organized
by round: project discussion, Embedded C, driver internals, debugging,
Yocto, boot process, Device Tree, protocols, Linux internals, Git workflow.
EOF

cat > scripts/README.md << 'EOF'
# scripts/

Work in progress. Helper/automation scripts shared across labs (setup,
cleanup, log collection).
EOF

cat > tests/README.md << 'EOF'
# tests/

Work in progress. Test harnesses used to stress/verify fixes (e.g. repeated
load/unload cycles for the memory-leak chapter, soak tests for DMA).
EOF

cat > archive/README.md << 'EOF'
# archive/

Older or superseded material kept for reference only. Not part of the
active lab curriculum.
EOF

cat > bsp/kernel-build/README.md << 'EOF'
# bsp/kernel-build/

Work in progress. Kernel build configuration notes (defconfig, config
fragments, cross-compile setup) specific to this BSP.
EOF

cat > bsp/petalinux/README.md << 'EOF'
# bsp/petalinux/

Work in progress. PetaLinux-specific BSP notes, if/when a Xilinx/AMD
target is added to the lab.
EOF

cat > bsp/rootfs/README.md << 'EOF'
# bsp/rootfs/

Work in progress. Root filesystem construction and configuration notes
(udev/mdev, init system, device node handling).
EOF

for d in i2c_driver pci_driver platform_driver; do
cat > drivers/$d/README.md << EOF
# drivers/$d/

Work in progress. Dedicated $d examples, following the same
problem/normal-flow/broken-flow/fix/verification format used in
\`drivers/char_driver/\`.
EOF
done

echo "    done — README.md written to every major and empty folder"

echo ""
echo "==> Step 3: review changes"
git status

echo ""
echo "=========================================================="
echo " Cleanup complete. Next steps (run these yourself):"
echo "=========================================================="
echo "  git add ."
echo "  git commit -m \"Organize Embedded Linux Engineering Lab\""
echo ""
echo "  # If this repo has no GitHub remote yet:"
echo "  gh repo create Embedded-Linux-Lab --public --source=. --remote=origin"
echo "  git push -u origin main"
echo ""
echo "  # If it already has a remote:"
echo "  git push origin main"
echo ""
echo "  Your public link will be:"
echo "  https://github.com/<your-github-username>/Embedded-Linux-Lab"
echo "=========================================================="
