#!/bin/bash
# ============================================================
# REPRODUCE: Book 2 — All 10 Chapters
# Advanced Debugging: Race, Deadlock, Memory Corruption,
# DMA, Panic, High CPU, Softirq, Spinlock, Boot, ThreadSync
# ============================================================
# Author: S. Koteswara Rao
# Platform: QEMU ARM64 / Yocto Kirkstone 5.15.194
# ============================================================

BOOK2_DIR=~/30days_workWith_BSP/my_projects/book2
ROOTFS=~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4
MOUNT=/tmp/qemu-mount
KDIR=/home/kotesh/yocto/poky/build/tmp/work/qemuarm64-poky-linux/linux-yocto/5.15.194+gitAUTOINC+578937826f_431a37a229-r0/linux-qemuarm64-standard-build
ARCH=arm64
CROSS=aarch64-linux-gnu-

# ─────────────────────────────────────────────
# HOST: Build all Book 2 drivers
# ─────────────────────────────────────────────

build_ch01() {
    echo "=== [HOST] Build Ch01 Race Condition ==="
    cd "$BOOK2_DIR/ch01_race_condition"
    make clean && make
    echo "Ch01 Build: $?"
    ls *.ko
}

build_ch02() {
    echo "=== [HOST] Build Ch02 Deadlock ==="
    cd "$BOOK2_DIR/ch02_deadlock"
    cat > Makefile << MAKEOF
obj-m += deadlock_driver.o
KDIR := $KDIR
ARCH := $ARCH
CROSS_COMPILE := $CROSS
all:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) modules
clean:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) clean
MAKEOF
    make clean && make
    echo "Ch02 Build: $?"
    ls *.ko
}

build_ch03() {
    echo "=== [HOST] Build Ch03 Memory Corruption ==="
    cd "$BOOK2_DIR/ch03_memory_corruption"
    cat > Makefile << MAKEOF
obj-m += memory_corruption_driver.o
obj-m += memory_corruption_fixed.o
KDIR := $KDIR
ARCH := $ARCH
CROSS_COMPILE := $CROSS
all:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) modules
clean:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) clean
MAKEOF
    make clean && make
    echo "Ch03 Build: $?"
}

build_ch04() {
    echo "=== [HOST] Build Ch04 DMA ==="
    cd "$BOOK2_DIR/ch04_dma"
    cat > Makefile << MAKEOF
obj-m += dma_issue_driver.o
KDIR := $KDIR
ARCH := $ARCH
CROSS_COMPILE := $CROSS
all:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) modules
clean:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) clean
MAKEOF
    make clean && make
    echo "Ch04 Build: $?"
}

build_ch05() {
    echo "=== [HOST] Build Ch05 Panic Analysis ==="
    cd "$BOOK2_DIR/ch05_panic_analysis"
    cat > Makefile << MAKEOF
obj-m += panic_analysis_driver.o
obj-m += panic_analysis_fixed.o
EXTRA_CFLAGS += -g
KDIR := $KDIR
ARCH := $ARCH
CROSS_COMPILE := $CROSS
all:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) modules
clean:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) clean
MAKEOF
    make clean && make
    echo "Ch05 Build: $?"
}

build_ch06() {
    echo "=== [HOST] Build Ch06 High CPU ==="
    cd "$BOOK2_DIR/ch06_high_cpu"
    cat > Makefile << MAKEOF
obj-m += high_cpu_driver.o
obj-m += high_cpu_fixed.o
KDIR := $KDIR
ARCH := $ARCH
CROSS_COMPILE := $CROSS
all:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) modules
clean:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) clean
MAKEOF
    make clean && make
    echo "Ch06 Build: $?"
}

build_ch07() {
    echo "=== [HOST] Build Ch07 Softirq ==="
    cd "$BOOK2_DIR/ch07_softirq"
    cat > Makefile << MAKEOF
obj-m += softirq_driver.o
obj-m += softirq_fixed.o
KDIR := $KDIR
ARCH := $ARCH
CROSS_COMPILE := $CROSS
all:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) modules
clean:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) clean
MAKEOF
    make clean && make
    echo "Ch07 Build: $?"
}

build_ch08() {
    echo "=== [HOST] Build Ch08 Spinlock ==="
    cd "$BOOK2_DIR/ch08_spinlock"
    cat > Makefile << MAKEOF
obj-m += spinlock_driver.o
obj-m += spinlock_fixed.o
KDIR := $KDIR
ARCH := $ARCH
CROSS_COMPILE := $CROSS
all:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) modules
clean:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) clean
MAKEOF
    make clean && make
    echo "Ch08 Build: $?"
}

build_ch09() {
    echo "=== [HOST] Build Ch09 Boot Optimization ==="
    cd "$BOOK2_DIR/ch09_boot_opt"
    cat > Makefile << MAKEOF
obj-m += boot_delay_driver.o
obj-m += boot_delay_fixed.o
obj-m += async_probe_driver.o
KDIR := $KDIR
ARCH := $ARCH
CROSS_COMPILE := $CROSS
all:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) modules
clean:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) clean
MAKEOF
    make clean && make
    echo "Ch09 Build: $?"
}

build_ch10() {
    echo "=== [HOST] Build Ch10 Thread Sync ==="
    cd "$BOOK2_DIR/ch10_thread_sync"
    cat > Makefile << MAKEOF
obj-m += thread_sync_driver.o
obj-m += thread_sync_fixed.o
KDIR := $KDIR
ARCH := $ARCH
CROSS_COMPILE := $CROSS
all:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) modules
clean:
	make -C \$(KDIR) M=\$(PWD) ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) clean
MAKEOF
    make clean && make
    echo "Ch10 Build: $?"
}

deploy_all() {
    echo "=== [HOST] Deploy all Book 2 drivers to rootfs ==="
    sudo mkdir -p "$MOUNT"
    sudo mount -o loop "$ROOTFS" "$MOUNT"
    find "$BOOK2_DIR" -name "*.ko" -exec sudo cp {} "$MOUNT/home/root/" \;
    ls "$MOUNT/home/root/"*.ko
    sudo umount "$MOUNT"
    echo "[HOST] Done. Boot: ~/BSP-Lab/boot_qemu.sh"
}

build_all() {
    mkdir -p "$BOOK2_DIR/ch02_deadlock"
    mkdir -p "$BOOK2_DIR/ch03_memory_corruption"
    mkdir -p "$BOOK2_DIR/ch04_dma"
    mkdir -p "$BOOK2_DIR/ch05_panic_analysis"
    mkdir -p "$BOOK2_DIR/ch06_high_cpu"
    mkdir -p "$BOOK2_DIR/ch07_softirq"
    mkdir -p "$BOOK2_DIR/ch08_spinlock"
    mkdir -p "$BOOK2_DIR/ch09_boot_opt"
    mkdir -p "$BOOK2_DIR/ch10_thread_sync"

    build_ch01
    build_ch02
    build_ch03
    build_ch04
    build_ch05
    build_ch06
    build_ch07
    build_ch08
    build_ch09
    build_ch10
    deploy_all
}

# ─────────────────────────────────────────────
# QEMU SECTION — paste manually inside QEMU
# ─────────────────────────────────────────────

cat << 'QEMU'

============================================================
 QEMU SECTION — run inside QEMU after: ~/BSP-Lab/boot_qemu.sh
 login: root
============================================================

=== Ch01: Race Condition ===
insmod /home/root/race_counter_driver.ko
dmesg | grep RACE
# Expected:
# RACE [BUG]  counter = 1282 (expected 2000) — WRONG!
# RACE [FIXED] counter = 2000 (expected 2000) — CORRECT!
rmmod race_counter_driver

=== Ch02: Deadlock — BUG (hangs ~10s, Ctrl+C to escape) ===
insmod /home/root/deadlock_driver.ko use_fix=0
# Wait 10 seconds — observe silence then soft lockup
dmesg | grep -E "DEADLOCK|soft lockup"
# Ctrl+C then reboot QEMU

=== Ch02: Deadlock — FIXED ===
insmod /home/root/deadlock_driver.ko use_fix=1
dmesg | grep DEADLOCK
# Expected: both threads print "got both locks — SUCCESS"
rmmod deadlock_driver

=== Ch03: Memory Corruption — BUG ===
insmod /home/root/memory_corruption_driver.ko
echo "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" > /dev/mem_corrupt
dmesg | grep -E "KASAN|BUG|corruption"
# Expected: KASAN: slab-out-of-bounds (if KASAN enabled)
# Without KASAN: crash at unrelated location

=== Ch03: Memory Corruption — FIXED ===
insmod /home/root/memory_corruption_fixed.ko
echo "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" > /dev/mem_corrupt
dmesg | grep "FIXED.*bytes"
# Expected: received 10 bytes safely (clamped to buf size)
rmmod memory_corruption_fixed

=== Ch04: DMA Issue ===
insmod /home/root/dma_issue_driver.ko
dmesg | grep DMA
# Expected:
# DMA [BUG]:  passing VIRTUAL address to hardware
# DMA [FIXED]: physical = 0x000000004ab1234
rmmod dma_issue_driver

=== Ch05: Panic Analysis — BUG ===
insmod /home/root/panic_analysis_driver.ko
echo "test" > /dev/panic_dev
dmesg | grep -A 15 "Unable to handle"
# Copy the pc offset e.g. my_driver_write+0x12/0x50

# HOST: decode it
# addr2line -e panic_analysis_driver.o -a 0x12

=== Ch05: Panic Analysis — FIXED ===
insmod /home/root/panic_analysis_fixed.ko
echo "test" > /dev/panic_dev
dmesg | grep "FIXED"
# Expected: count incremented — no panic
rmmod panic_analysis_fixed

=== Ch06: High CPU — BUG ===
insmod /home/root/high_cpu_driver.ko
top   # observe 99% CPU on poll thread
dmesg | grep HIGH_CPU
rmmod high_cpu_driver

=== Ch06: High CPU — FIXED ===
insmod /home/root/high_cpu_fixed.ko
top   # observe near 0% CPU
dmesg | grep HIGH_CPU
rmmod high_cpu_fixed

=== Ch07: Softirq Misuse — BUG ===
insmod /home/root/softirq_driver.ko
dmesg | grep "sleeping function called from invalid context"
# Expected: BUG: in_atomic(): 1
rmmod softirq_driver 2>/dev/null || true

=== Ch07: Softirq — FIXED ===
insmod /home/root/softirq_fixed.ko
dmesg | grep SOFTIRQ
# Expected: work_handler ran in workqueue context
rmmod softirq_fixed

=== Ch08: Spinlock — BUG (hangs on second write) ===
insmod /home/root/spinlock_driver.ko
echo "trigger" > /dev/spinlock_dev  # no unlock on error path
echo "trigger" > /dev/spinlock_dev  # HANGS HERE
dmesg | grep "soft lockup"
# Reboot QEMU after this

=== Ch08: Spinlock — FIXED ===
insmod /home/root/spinlock_fixed.ko
echo "trigger" > /dev/spinlock_dev   # returns error, lock released
echo "trigger" > /dev/spinlock_dev   # works — no hang
dmesg | grep SPINLOCK
rmmod spinlock_fixed

=== Ch09: Boot Optimization — BUG ===
date
insmod /home/root/boot_delay_driver.ko
date
# Expected: 5+ second gap
dmesg | grep "BOOT\|probe took"
rmmod boot_delay_driver

=== Ch09: Boot Optimization — FIXED ===
date
insmod /home/root/boot_delay_fixed.ko
date
# Expected: same second — probe returns immediately
sleep 6
dmesg | grep "BOOT\|async\|delayed init"
rmmod boot_delay_fixed

=== Ch09: initcall_debug evidence ===
dmesg | grep -E "platform_probe|really_probe|do_one_initcall"

=== Ch10: Thread Sync — BUG ===
insmod /home/root/thread_sync_driver.ko
dmesg | grep SYNC
# Expected: inconsistent consumer output (0 bytes or partial)
rmmod thread_sync_driver

=== Ch10: Thread Sync — FIXED ===
insmod /home/root/thread_sync_fixed.ko
dmesg | grep SYNC
# Expected: consumer always sees complete state
rmmod thread_sync_fixed

=== Final Verification ===
dmesg | grep -E "RACE|DEADLOCK|KASAN|DMA|PANIC|HIGH_CPU|SOFTIRQ|SPINLOCK|BOOT|SYNC"

QEMU

echo ""
echo "Usage:"
echo "  source REPRODUCE_Book2_All_Chapters.sh"
echo "  build_all      # build + deploy all 10 chapters"
echo "  build_ch01     # build only Ch01"
echo "  deploy_all     # deploy all built .ko to rootfs"
echo ""
echo "Then boot QEMU and run the QEMU section above."
