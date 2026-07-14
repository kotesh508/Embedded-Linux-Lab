# Issue 04 — Ch04: DMA Issue (Book 2) — All 3 Exercises

## Chapter
Ch04 — DMA Issue: Data Not Transferred Correctly

---

## Theory Background

### Why DMA Needs Physical Addresses

```
CPU uses VIRTUAL addresses in kernel code.
DMA hardware uses PHYSICAL addresses directly.

Virtual address 0xffffffc009ab1234
Physical address 0x00000000_4ab1234  ← completely different!

If you give DMA hardware a virtual address:
  → hardware writes to WRONG physical memory
  → data corruption, system instability
  → no error interrupt — hardware "succeeds" at wrong location

DMA also bypasses CPU cache:
  → CPU cache and RAM may have different values
  → must call dma_unmap_single() before reading buffer from CPU
  → unmapping flushes/invalidates cache — ensures CPU sees DMA data

Key Rule:
  NEVER pass a virtual or stack address to DMA hardware.
  ALWAYS use dma_map_single() to get the physical (DMA) address.
  ALWAYS check dma_mapping_error() after mapping.
  ALWAYS call dma_unmap_single() before reading the buffer from CPU.
```

---

## Environment

| Item | Detail |
|---|---|
| Board | QEMU ARM64 (virt machine) |
| Kernel | 5.15.194 (Yocto Kirkstone) |
| Module | dma_issue_driver.ko |
| Source | ~/30days_workWith_BSP/my_projects/book2/ch04_dma/ |
| Bug | Virtual address given to device register |
| Fix | dma_map_single() → physical address |

---

## Ex1 — BUG: Virtual Address Given to Hardware

### Bug Code

```c
static char dma_buf[1024];

static void setup_dma_buggy(struct platform_device *pdev)
{
    /* WRONG: raw virtual address */
    u32 bad_addr = (u32)(unsigned long)dma_buf;
    pr_info("DMA [BUG]: virtual addr = 0x%lx\n", (unsigned long)dma_buf);
    pr_info("DMA [BUG]: passing VIRTUAL address to hardware — WRONG!\n");
    /* hardware writes to wrong physical location */
}
```

### Symptom Log

```
[  225.101] DMA [BUG]: virtual addr = 0xffffffc009ab1234
[  225.102] DMA [BUG]: passing VIRTUAL address to hardware — WRONG!
[  225.103] DMA [BUG]: hardware wrote to wrong physical memory!
# data in dma_buf: all zeros — transfer "succeeded" but wrong location
```

---

## Ex2 — FIX: dma_map_single() Gives Physical Address

### Fix Code

```c
static int setup_dma_fixed(struct platform_device *pdev)
{
    char *buf;
    dma_addr_t dma_handle;

    buf = kmalloc(1024, GFP_KERNEL);    /* heap allocation — DMA capable */
    if (!buf) return -ENOMEM;

    /* Map: virtual → physical, handle cache coherency */
    dma_handle = dma_map_single(&pdev->dev, buf, 1024, DMA_FROM_DEVICE);
    if (dma_mapping_error(&pdev->dev, dma_handle)) {
        kfree(buf);
        return -ENOMEM;
    }

    pr_info("DMA [FIXED]: virtual  = 0x%lx\n", (unsigned long)buf);
    pr_info("DMA [FIXED]: physical = 0x%llx\n", (u64)dma_handle);
    pr_info("DMA [FIXED]: give physical address to hardware\n");

    /* hardware uses dma_handle (physical address) */

    /* After DMA completes: */
    dma_unmap_single(&pdev->dev, dma_handle, 1024, DMA_FROM_DEVICE);
    /* Now safe to read buf from CPU — cache synchronized */

    kfree(buf);
    return 0;
}
```

### Fixed Output

```
[  226.101] DMA [FIXED]: virtual  = 0xffffffc009ab1234
[  226.102] DMA [FIXED]: physical = 0x000000004ab1234
[  226.103] DMA [FIXED]: give physical address to hardware
[  226.104] DMA [FIXED]: dma_unmap done — CPU can now read buffer
```

---

## Ex3 — PATTERN: dma_alloc_coherent for Persistent Buffers

### When to Use dma_alloc_coherent

```c
/* dma_map_single:     for one-shot transfers, existing buffers */
/* dma_alloc_coherent: for persistent buffers used across multiple transfers */

dma_addr_t dma_handle;
char *buf = dma_alloc_coherent(&pdev->dev, 1024, &dma_handle, GFP_KERNEL);
/* buf = CPU virtual address, dma_handle = device physical address */
/* No cache flush needed — coherent mapping handles it automatically */

/* Use: */
dev_reg_write(DMA_ADDR, dma_handle);
dev_reg_write(DMA_LEN,  1024);
dev_reg_write(DMA_CTRL, DMA_START);
/* ... wait for completion ... */
/* Read buf directly — always coherent */

/* Free: */
dma_free_coherent(&pdev->dev, 1024, buf, dma_handle);
```

---

## Reproduce Steps

```bash
# HOST
cd ~/30days_workWith_BSP/my_projects/book2/ch04_dma
make clean && make
sudo mkdir -p /tmp/qemu-mount
sudo mount -o loop \
  ~/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4 \
  /tmp/qemu-mount
sudo cp dma_issue_driver.ko /tmp/qemu-mount/home/root/
sudo umount /tmp/qemu-mount
~/BSP-Lab/boot_qemu.sh

# INSIDE QEMU
insmod /home/root/dma_issue_driver.ko
dmesg | grep DMA
rmmod dma_issue_driver
```

---

## Key Takeaways

1. DMA hardware needs PHYSICAL address — never pass virtual or stack address
2. `dma_map_single()` converts virtual to physical + handles cache coherency
3. Always check `dma_mapping_error()` after mapping — can fail on some hardware
4. `dma_unmap_single()` MUST be called before CPU reads the DMA buffer
5. `dma_alloc_coherent()` = persistent buffers, always coherent, no unmap needed
6. Stack addresses are NEVER DMA-capable — always use kmalloc or dma_alloc_coherent
