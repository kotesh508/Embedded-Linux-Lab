# Issue 09 — Ch09: Kernel Config (Kconfig) — All 3 Exercises

## Chapter
Ch09 — Kernel Configuration (Kconfig / menuconfig)

---

## Theory Background

### What is Kconfig?

```
Kconfig = kernel configuration system
  - Each subsystem has a Kconfig file defining options
  - Options compiled into .config during menuconfig/defconfig
  - Result: include/generated/autoconf.h with #define CONFIG_XXX

Three ways a CONFIG can be set:
  CONFIG_FOO=y   → compiled into kernel (built-in)
  CONFIG_FOO=m   → compiled as loadable module
  # CONFIG_FOO is not set  → disabled

Driver code uses:
  #ifdef CONFIG_FOO         → compile-time check
  IS_ENABLED(CONFIG_FOO)   → runtime check (always compiles)
  IS_BUILTIN(CONFIG_FOO)   → true only if =y (not =m)
```

### Where CONFIG Values Come From

```
Source tree:
  drivers/misc/Kconfig          → defines CONFIG_SENSOR_DEBUG
  drivers/misc/sensor/Kconfig   → your driver's options

Build time:
  make menuconfig               → interactive editor
  make defconfig                → default values
  bitbake linux-yocto -c menuconfig  → Yocto way

Runtime evidence:
  /proc/config.gz               → compressed .config of running kernel
  zcat /proc/config.gz | grep FOO
  cat /boot/config-$(uname -r)  → on some distros
```

### #ifdef vs IS_ENABLED

```c
/* #ifdef — compile-time only, code removed if not set */
#ifdef CONFIG_SENSOR_DEBUG
    pr_info("debug info\n");   /* not compiled if CONFIG=n */
#endif

/* IS_ENABLED — always compiled, evaluated at runtime */
if (IS_ENABLED(CONFIG_SENSOR_DEBUG)) {
    pr_info("debug info\n");   /* compiled but branch eliminated by optimizer */
}
/* IS_ENABLED is safer — catches typos at compile time */
```

---

## Ex1 — Missing CONFIG Options: Silent Feature Loss

### Bug Description
Driver uses `#ifdef CONFIG_SENSOR_DEBUG` and `#ifdef CONFIG_SENSOR_THRESHOLD`
but these options are never defined anywhere (no Kconfig entry, not in .config).
Result: `#else` branch always taken — debug silently disabled, feature missing.
**No compile error** — this is a silent bug.

### Reproduce Steps

```bash
# Host: build
cd ~/30days_workWith_BSP/my_projects/ch09_kconfig
# Makefile: obj-m += sensor_driver_kconfig.o
make clean && make
echo "Build: $?"

# Deploy + QEMU
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 /tmp/qemu-mount
sudo cp sensor_driver_kconfig.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# QEMU
insmod /home/root/sensor_driver_kconfig.ko
dmesg | grep "Sensor Kconfig" | tail -5
rmmod sensor_driver_kconfig
```

### Actual Output (Buggy)

```
[  213.614833] Sensor Kconfig [PROBE]: probe() called!
[  213.615784] Sensor Kconfig [BUG]: CONFIG_SENSOR_DEBUG not set — debug disabled!
[  213.616203] Sensor Kconfig [BUG]: CONFIG_SENSOR_THRESHOLD not set — feature missing!
[  213.616619] Sensor Kconfig [PROBE]: Ready
```

### Root Cause

```c
/* CONFIG_SENSOR_DEBUG never defined in Kconfig or .config */
#ifdef CONFIG_SENSOR_DEBUG     ← always false
    pr_info("debug...");       ← never compiled/executed
#else
    pr_warn("[BUG]: CONFIG_SENSOR_DEBUG not set");  ← always runs
#endif
```

### Fix Commands

```bash
# Option 1: define with default in driver Kconfig
cat > Kconfig << 'EOF'
menu "Kotesh Sensor Driver Options"
config SENSOR_DEBUG
    bool "Enable sensor debug output"
    default n
config SENSOR_THRESHOLD
    bool "Enable sensor threshold feature"
    default y
endmenu
EOF

# Option 2: define via extra CFLAGS in Makefile
echo 'ccflags-y += -DCONFIG_SENSOR_THRESHOLD=1' >> Makefile

# Option 3: use IS_ENABLED with safe default (see Ex2)
```

---

## Ex2 — Fixed CONFIG with Safe Defaults

### Fix Description
- `#ifndef CONFIG_SENSOR_DEBUG` guard provides safe fallback `= 0`
- `#ifndef CONFIG_SENSOR_THRESHOLD` guard provides safe fallback `= 1`
- Driver behaves correctly whether CONFIG is set or not

### Actual Output (Fixed)

```
[  213.951915] Sensor Kconfig [PROBE]: probe() called!
[  213.952201] Sensor Kconfig [FIXED]: DEBUG disabled (CONFIG_SENSOR_DEBUG=0)
[  213.952524] Sensor Kconfig [FIXED]: threshold feature enabled
[  213.952804] Sensor Kconfig [PROBE]: Ready
```

### Fix Pattern

```c
/* FIXED: provide safe defaults when CONFIG not set */
#ifndef CONFIG_SENSOR_DEBUG
#define CONFIG_SENSOR_DEBUG 0
#endif

#ifndef CONFIG_SENSOR_THRESHOLD
#define CONFIG_SENSOR_THRESHOLD 1
#endif

/* Now use #if instead of #ifdef */
#if CONFIG_SENSOR_DEBUG
    pr_info("debug info\n");
#else
    pr_info("debug disabled\n");
#endif
```

---

## Ex3 — Runtime CONFIG Reporting

### Description
Driver reports actual kernel CONFIG values at probe() time using `#ifdef`.
Useful to verify which debug features are compiled into the running kernel.

### Reproduce Steps (QEMU)

```bash
insmod /home/root/sensor_driver_kconfig_ex3.ko
dmesg | grep "Sensor Kconfig Ex3" | tail -10
rmmod sensor_driver_kconfig_ex3

# Verify against /proc/config.gz
zcat /proc/config.gz | grep -E "KMEMLEAK|KFENCE|DEBUG_FS|KPROBES"
```

### Actual Output

```
[  214.351287] Sensor Kconfig Ex3 [PROBE]: probe() called!
[  214.351632] Sensor Kconfig Ex3 [CONFIG]: CONFIG_DEBUG_KMEMLEAK=y
[  214.351967] Sensor Kconfig Ex3 [CONFIG]: CONFIG_KFENCE=y
[  214.352262] Sensor Kconfig Ex3 [CONFIG]: CONFIG_DEBUG_FS=y
[  214.352560] Sensor Kconfig Ex3 [CONFIG]: CONFIG_HAVE_KPROBES=y
[  214.352877] Sensor Kconfig Ex3 [PROBE]: Ready — config reported above
```

### Kernel Config Evidence (from /proc/config.gz)

```
CONFIG_HAVE_DEBUG_KMEMLEAK=y
CONFIG_DEBUG_KMEMLEAK=y
CONFIG_DEBUG_KMEMLEAK_MEM_POOL_SIZE=16000
CONFIG_DEBUG_KMEMLEAK_AUTO_SCAN=y
CONFIG_KFENCE=y
CONFIG_DEBUG_FS=y
CONFIG_HAVE_KPROBES=y
```

### menuconfig Path to Enable kmemleak

```
bitbake linux-yocto -c menuconfig

Navigate:
  Kernel hacking →
    [*] Kernel debugging        ← enable first
    Memory Debugging →
      [*] Kernel memory leak detector   ← then enable this
      [*]   Enable kmemleak auto scan thread on boot up

Save → bitbake linux-yocto -c compile -f → bitbake core-image-minimal
```

---

## Kconfig Summary

| Method | When to use | Example |
|--------|-------------|---------|
| `#ifdef CONFIG_FOO` | Compile-time conditional code | Debug logging |
| `IS_ENABLED(CONFIG_FOO)` | Always-compiled conditional | Safer alternative |
| `#ifndef CONFIG_FOO / #define` | Safe defaults for out-of-tree modules | External drivers |
| `/proc/config.gz` | Verify running kernel config | `zcat /proc/config.gz \| grep FOO` |
| `menuconfig` | Enable/disable at build time | Yocto: `bitbake linux-yocto -c menuconfig` |

---

## Key Takeaways

1. Missing `CONFIG_` = **silent** bug — no compile error, wrong runtime behavior
2. Out-of-tree modules **cannot** add to kernel Kconfig — use `ccflags-y` or `#ifndef` guards
3. `IS_ENABLED()` is safer than `#ifdef` — catches typos at compile time
4. `/proc/config.gz` = runtime evidence of what's compiled in
5. **Always provide defaults** for CONFIG options in out-of-tree drivers
6. `CONFIG_DEBUG_KMEMLEAK=y` required for kmemleak — verify before memory leak debugging
