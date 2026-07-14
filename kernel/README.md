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
