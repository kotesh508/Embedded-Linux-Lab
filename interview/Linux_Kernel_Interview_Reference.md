# Linux Kernel Interview Reference

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/bsp/device-tree/Issue_01_Compatible_Mismatch.md

## 🧠 Interview Explanation

> The Linux kernel matches a Device Tree node to a platform driver using the `compatible` string. The kernel walks the `of_match_table` in the driver and compares each entry against the `compatible` property in the DTS node using an **exact string match**. If there is any mismatch — even a hyphen vs underscore — the driver's `probe()` function is never called. The fix is to ensure the `compatible` string is byte-for-byte identical in both the DTS node and the driver's `of_device_id` table. Convention is `"vendor,device"` in lowercase with no spaces.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/bsp/device-tree/Issue_02_Disabled_Node.md

## 🧠 Interview Explanation

> In the Linux Device Tree, the `status` property controls whether the kernel treats a node as active hardware. A value of `"okay"` tells the kernel to register the device on the platform bus and match it to a driver. A value of `"disabled"` causes the kernel to skip the node entirely during boot — no platform device is created, so the driver's `probe()` is never called even if the module is loaded and the `compatible` string matches. This is commonly used in BSPs to ship a single DTS for a board family and selectively enable only the peripherals present on each variant using overlays or board-specific `.dtsi` files.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/bsp/device-tree/Issue_03_Missing_Reg_Property.md

## 🧠 Interview Explanation

> The `reg` property in a Device Tree node describes the physical memory address and size of a device's register space. When a driver calls `platform_get_resource(pdev, IORESOURCE_MEM, 0)`, the kernel translates the `reg` property from the DTS into a `struct resource` and returns it. If the `reg` property is missing, `platform_get_resource()` returns NULL. A well-written driver checks for this and returns `-EINVAL`, causing probe to fail with `error -22`. The fix is to add the correct `reg` property matching the device's actual hardware address range. This is different from a compatible mismatch or disabled node — in those cases probe is never called at all, but here probe is called and fails midway.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/bsp/device-tree/Issue_04_Wrong_Interrupt_Number.md

## 🧠 Interview Explanation

> Each interrupt line on a GIC can only be owned by one device unless `IRQF_SHARED` is used. In the Device Tree, the `interrupts` property specifies the interrupt type, number, and trigger mode. For ARM GIC, SPI interrupts map to Linux IRQ numbers as `SPI + 32`. If the DTS assigns an SPI number that is already claimed by another device (like `arch_timer` on SPI 3), `devm_request_irq()` returns `-EBUSY`, probe fails with `Resource temporarily unavailable`. The fix is to check `/proc/interrupts` on a running system to identify free interrupt lines and assign one to the new device.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/bsp/device-tree/Issue_05_Probe_Deferral.md

## 🧠 Interview Explanation

> Probe deferral is a Linux kernel mechanism where a driver's `probe()` function returns `-EPROBE_DEFER` to indicate that a required resource or dependency is not yet available. The kernel adds the device to a deferred probe list and retries probe after other devices finish initializing. Common causes include: a clock provider not yet registered, a regulator not yet available, a GPIO controller not yet probed, or an interrupt controller dependency not resolved. You can identify probe deferral by checking `/sys/kernel/debug/devices_deferred` — it shows each deferred device and the reason. The fix is either to ensure the supplier initializes first (using `initcall` ordering or `depends-on` in DTS), or to handle `-EPROBE_DEFER` explicitly in the driver.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/bsp/device-tree/Issue_06_Missing_Clock.md

## 🧠 Interview Explanation

> The `clocks` property in a DTS node specifies which clock provider the device uses, referenced by phandle. The `clock-names` property gives each clock a name so the driver can request it by name using `devm_clk_get(&pdev->dev, "name")`. When the `clocks` property is missing, `devm_clk_get()` returns `-ENOENT` (error -2) because the kernel cannot find any clock registered for that device. This is a common issue in BSP bring-up when porting a driver to a new board — the driver works on the reference board but fails on the custom board because the custom DTS is missing the clock binding. The fix is to identify the correct clock provider phandle from the DTS and add the `clocks` and `clock-names` properties to the device node.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/bsp/device-tree/Issue_07_Missing_Regulator.md

## 🧠 Interview Explanation

> The `vcc-supply` property in a DTS node specifies which voltage regulator powers the device, referenced by phandle. The driver requests this regulator using `devm_regulator_get()` or `devm_regulator_get_optional()`. A critical difference: `devm_regulator_get()` silently returns a dummy regulator when the supply is missing — probe succeeds but the device may behave incorrectly at runtime. `devm_regulator_get_optional()` returns `-ENODEV` when the supply is missing, making the failure visible. This is a common BSP issue — the driver works on the reference platform but silently fails on a custom board with missing regulator bindings. Always use `devm_regulator_get_optional()` for supplies that are truly optional, and `devm_regulator_get()` only for mandatory supplies where you want a dummy fallback.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/bsp/device-tree/Issue_08_Missing_CONFIG_OF.md

## 🧠 Interview Explanation

> `CONFIG_OF` enables Device Tree support in the Linux kernel. When enabled, drivers use `of_match_table` inside `platform_driver.driver` to declare which DT `compatible` strings they handle. The kernel matches this table against the `compatible` property of DT nodes to call the driver's `probe()`. If `of_match_table` is missing — either because `CONFIG_OF` is disabled or the developer forgot to add it — the kernel cannot perform DT-based matching. The driver registers successfully and the device is created, but they are never bound and probe is never called. There are no error messages, making this a silent failure that is easy to miss. The fix is to add `of_match_table` with the correct compatible string and include `<linux/of.h>`.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/bsp/device-tree/Issue_09_Driver_Not_In_Image.md

## 🧠 Interview Explanation

> In embedded Linux, the DTS describes the hardware and the kernel uses it to create platform devices at boot. However, just having a DTS node does not guarantee the driver will run — the driver module must also be present in the rootfs. In Yocto, this requires the driver recipe to be added to `IMAGE_INSTALL` in the image recipe or bbappend. If this is missing, the kernel creates the platform device but no driver ever loads. The result is a completely silent failure — no error messages, no dmesg output. Diagnosis involves checking `/lib/modules/` for the `.ko` file, checking `/sys/bus/platform/drivers/` for driver registration, and verifying the image bbappend has the correct `IMAGE_INSTALL` entry.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/bsp/device-tree/Issue_10_Compatible_String_Mismatch.md

## 🧠 Interview Explanation

> When two kernel drivers declare the same `compatible` string in their `of_match_table`, both register on the platform bus but only the first one to register gets to probe the device. The second driver silently never probes. This is a common issue in BSP development when a vendor tree has both an upstream driver and a custom vendor driver claiming the same hardware. The kernel does not report an error — it just silently uses the first driver. Diagnosis involves checking `/sys/bus/platform/devices/<dev>/driver` to see which driver won, and `dmesg` to see which probe was called. The fix is to either remove the duplicate driver, use unique compatible strings per hardware revision, or use a compatible string list in DTS to select the preferred driver.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/drivers/char_driver/ch01_memory/Issue_01_Ex1_NULL_Ptr_Uninitialized.md

## 🧠 Interview Explanation

The kernel module declared a struct pointer as a global variable but never allocated memory for it. In C, uninitialized global pointers default to NULL (0x0). When `my_init()` tried to write to `dev->value`, the CPU raised a page fault at address 0x0. Unlike user space where only the process gets SIGSEGV, in kernel space there is no higher authority to catch the fault — the kernel generates an Oops and kills the faulting context. The fix is to always allocate memory with `kmalloc` before using a pointer, and always check the return value for NULL.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/drivers/char_driver/ch01_memory/Issue_01_Ex2_NULL_Ptr_kmalloc_Fix.md

## 🧠 Interview Explanation

The fix allocates memory with `kmalloc` before the pointer is used, checks the return value for NULL, and frees the memory in the exit function with `kfree`. The critical rule is order — allocate first, check NULL, then use. Setting the pointer to NULL after `kfree` prevents use-after-free. The timer must be cancelled before `kfree` to prevent the callback from accessing freed memory after it is freed.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/drivers/char_driver/ch01_memory/Issue_01_Ex3_NULL_Ptr_devm_kmalloc.md

## 🧠 Interview Explanation

`devm_kmalloc` is device-managed memory allocation — the kernel automatically frees it when the device is removed or when `probe()` fails, even if the driver's `remove()` function is never called. This eliminates memory leaks in error paths where `kfree` might be accidentally skipped. The rule of thumb: use `kmalloc` for simple standalone modules, use `devm_kzalloc` for all platform drivers with `probe/remove`.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/drivers/char_driver/ch02_device_tree/Issue_02_Ex1_DTS_Compatible_Mismatch.md

## 🧠 Interview Explanation

A compatible string mismatch is the most silent failure in Linux driver development — the module loads, the driver registers, but probe() is never called and no error is printed. The kernel simply skips any device whose DTS compatible string does not exactly match the driver's of_match_table entry, character by character. Diagnosis: check `/sys/bus/platform/drivers/<driver>/` for a device symlink — if only bind/unbind/uevent/module are present, the driver is unbound. Fix: compare the compatible strings character by character and ensure exact match.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/drivers/char_driver/ch02_device_tree/Issue_02_Ex2_DTS_Fix_Host_vs_QEMU.md

## 🧠 Interview Explanation

After fixing the compatible string typo, the driver still doesn't probe on the host x86 kernel because the ThinkPad uses ACPI-based platform devices, not Device Tree. The `/proc/device-tree/` directory doesn't exist on x86 systems. Platform drivers with `of_match_table` require an ARM-based system with a DTB passed by the bootloader. To fully verify the fix, a matching DTS node must be added to the QEMU `qemu-virt.dts` and the system must be booted with the updated DTB — covered in Exercise 3.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/drivers/char_driver/ch02_device_tree/Issue_02_Ex3_DTS_QEMU_Verified.md

## 🧠 Interview Explanation

A DTS compatible string mismatch silently prevents probe() from being called — no error, no warning. The fix requires three things to align: the driver's `of_match_table` compatible string must exactly match the DTS node's compatible property, the system must be DTS-based (ARM64 with DTB, not x86 ACPI), and the module must be cross-compiled for the correct architecture. On a ThinkPad x86 host, platform drivers with `of_match_table` will never probe because the host uses ACPI not Device Tree. The complete fix was verified on QEMU ARM64 where probe() was called, the device symlink appeared in `/sys/bus/platform/drivers/sensor_dts/`, and remove() was called cleanly on unload.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/kernel/panic_analysis/Panic_Issue_01_NULL_Pointer_Dereference.md

## 🧠 Interview Explanation

> A NULL pointer dereference occurs when kernel code tries to read or write through a pointer that is NULL (address 0x0). In Linux on ARM64, virtual address 0 is never mapped, so the MMU raises a Data Abort exception which the kernel reports as "Unable to handle kernel NULL pointer dereference". The panic message shows the faulting PC (exact function and offset), the call trace (how execution reached that point), and the register dump (which register held NULL). The key fields to read are: the virtual address (confirms NULL), the PC line (identifies the exact function), and the call trace (shows the execution path). The fix is always to validate pointers before use and return an appropriate error code if they are NULL.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/kernel/panic_analysis/Panic_Issue_02_Stack_Overflow.md

## 🧠 Interview Explanation

> Kernel stack overflow occurs when a kernel thread exhausts its stack space, typically due to infinite or excessively deep recursion. On ARM64, the kernel stack is 16KB per thread. Each function call consumes stack space for saved registers, frame pointer, and local variables. When the stack pointer crosses the bottom of the stack into the guard page, the ARM64 hardware raises a Data Abort. The kernel detects this as "Insufficient stack space to handle exception" and panics with "kernel stack overflow". Unlike a NULL pointer dereference which may produce only an Oops, stack overflow always causes a hard panic with no recovery. The stack layout in the panic message shows the task stack range and the SP value — if SP is near the bottom of the task stack range, it confirms overflow. The fix is to always have a base case in recursive functions or convert deep recursion to iteration.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/kernel/panic_analysis/Panic_Issue_03_BUG_ON_WARN_ON.md

## 🧠 Interview Explanation

> `WARN_ON` and `BUG_ON` are kernel assertion macros. `WARN_ON(condition)` fires when the condition is true — it prints a warning message with the source file, line number, and call trace, then allows execution to continue. `BUG_ON(condition)` also fires when the condition is true but causes a hard kernel panic — execution stops immediately. In the dmesg output, WARN_ON is identified by `------------[ cut here ]------------` followed by `WARNING:`, while BUG_ON produces `kernel BUG at <file>:<line>!`. The source file and line number are printed directly, making these the easiest panics to debug. In driver development, prefer returning error codes over `BUG_ON` for recoverable conditions, and use `WARN_ON` to flag unexpected states that shouldn't stop the system.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/kernel/panic_analysis/Panic_Issue_04_Divide_by_Zero.md

## 🧠 Interview Explanation

> On ARM64, integer divide by zero does not trigger a hardware CPU exception like on x86. Instead, the GCC compiler inserts a runtime check before each division — if the divisor is zero, a `BRK` (breakpoint) instruction fires. The kernel reports this as "Unexpected kernel BRK exception at EL1" with BRK handler code `f20003e8`. This is different from x86 which shows "divide error: 0000". The faulting instruction in the Code line will be `d4207d00` which is `BRK #0x3e80`. The PC line shows exactly which function and offset caused it. The fix is to always validate that the divisor is non-zero before performing integer division, especially when the divisor comes from hardware registers, DT properties, or user-provided values.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/kernel/panic_analysis/Panic_Issue_05_Hung_Task.md

## 🧠 Interview Explanation

> A hung task occurs when a kernel thread stays blocked or in an infinite sleep loop for longer than `hung_task_timeout_secs` (default 120s). The kernel's `khungtaskd` daemon monitors for threads in uninterruptible sleep (`D` state) or repeatedly sleeping without making progress. When detected, it prints `INFO: task <name> blocked for more than N seconds` with a call trace showing where the thread is stuck. This is different from a soft lockup (CPU spinning without scheduling) or hard lockup (CPU with IRQs disabled). In BSP driver development, a common mistake is performing long operations or waiting in `probe()` — this blocks the udevd worker thread that called probe, and eventually triggers a hung task warning. The fix is to use kernel threads or workqueues for any long-running work, ensuring probe returns quickly.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/kernel/panic_analysis/Panic_Issue_06_Oops_vs_Panic.md

## 🧠 Interview Explanation

> A Kernel Oops is a non-fatal kernel error — the kernel detects a fault (like
> a NULL pointer dereference), prints registers and a call trace, kills the
> offending process, and continues running. By default `panic_on_oops=0` so the
> system survives. Setting `panic_on_oops=1` converts any Oops into a hard
> Kernel Panic — the system halts and must be rebooted. In production BSP work,
> `panic_on_oops=1` is often combined with `panic_timeout=N` so the system
> auto-reboots via watchdog after a fatal error. The `sysrq` interface is useful
> for testing panic behavior — `echo c > /proc/sysrq-trigger` forces an
> immediate kernel crash in kernel context, bypassing the userspace process
> protection that can let an Oops survive.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/kernel/panic_analysis/Panic_Issue_07_Use_After_Free.md

## 🧠 Interview Explanation

> Use-After-Free is one of the most dangerous kernel bugs because it causes
> silent memory corruption without any immediate crash. After `kfree()`, the
> SLUB allocator reclaims the memory and may overwrite it with its own metadata
> or reallocate it to another object. If the original pointer is accessed again,
> reads return corrupted data and writes silently corrupt the heap — potentially
> corrupting a completely different kernel object. The bug may not manifest as
> a crash until much later in unrelated code, making it extremely hard to debug.
> The correct tool is KASAN (Kernel Address Sanitizer), which instruments every
> memory access and immediately reports UAF with full allocation and free
> backtraces. In BSP driver development, the best prevention is using `devm_`
> allocations which are automatically managed, and always setting pointers to
> NULL after `kfree()` so any subsequent access causes an immediate visible
> NULL pointer Oops rather than silent corruption.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/kernel/panic_analysis/Panic_Issue_08_Double_Free.md

## 🧠 Interview Explanation

> A double free occurs when `kfree()` is called twice on the same pointer.
> The first `kfree()` returns the chunk to SLUB's free list and writes the
> poison value `dead000000000100` into it. The second `kfree()` corrupts the
> free list by inserting the same chunk twice. Subsequent allocations anywhere
> in the kernel may receive the corrupted chunk, and when the kernel tries to
> follow its next pointer it gets `dead000000000100` as an address, causing a
> NULL dereference at offset 0x8. This triggers a cascade of Oops across
> completely unrelated kernel threads — in our case corrupting 9 different
> contexts including the EXT4 journal thread. The crash location has no
> relation to the actual double free bug. The smoking gun in the register dump
> is `x4: dead000000000100` — SLUB's LIST_POISON2 magic value. The fix is to
> always set pointers to NULL after `kfree()` since `kfree(NULL)` is a safe
> no-op, or better yet use `devm_kmalloc()` for driver allocations which are
> managed automatically.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/kernel/panic_analysis/Panic_Issue_09_OOM.md

## 🧠 Interview Explanation

> Out of Memory occurs when the kernel exhausts all available RAM and swap and
> cannot reclaim enough through page cache eviction. There are two OOM
> scenarios: a page allocation failure where a large contiguous allocation fails
> but the system continues (kmalloc returns NULL), and a full OOM where the OOM
> killer fires, selects the highest-scoring process by RSS size, kills it, and
> reclaims its memory. In our lab we exhausted 945 MB of 985 MB total RAM
> through unreclaimable slab allocations, triggering a page allocation failure
> for order:8 (1MB contiguous) but not a full OOM kill because the probe()
> function returned after kmalloc failed, releasing pressure. The key diagnostic
> is `Slab: ~987MB` and `SUnreclaim: ~978MB` in /proc/meminfo — almost all RAM
> consumed by unreclaimable kernel slab. In BSP driver development, always use
> `devm_kmalloc()` for allocations so they are automatically freed on device
> removal, always handle NULL returns from kmalloc, and for production embedded
> systems set `panic_on_oom=2` with a watchdog timeout for automatic recovery.

=====================================================
FILE: /home/kotesh/Embedded-Linux-Lab/kernel/panic_analysis/Panic_Issue_10_Unaligned_Access.md

## 🧠 Interview Explanation

> Unaligned memory access occurs when a multi-byte value is read from or
> written to an address not aligned to its natural size — for example reading
> a 4-byte u32 from an odd address. On ARM64, Linux boots with hardware
> alignment fixup enabled (SCTLR_EL1.A=0), so unaligned accesses are
> transparently handled by the CPU without faulting, but at a performance cost
> and with potential for subtle data corruption as we saw — the read value
> was wrong. On architectures like MIPS or strict ARM32 configurations, the
> same access would cause a SIGBUS. In BSP driver development the most
> common bad pointer scenarios are: accessing physical MMIO addresses directly
> without ioremap (must always use devm_ioremap_resource), using ERR_PTR
> values without checking IS_ERR first, and DMA buffers that are not
> cache-line aligned causing data corruption. The correct pattern for MMIO
> is always readl/writel which guarantee alignment, ordering, and portability
> across all architectures.

