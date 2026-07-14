# Embedded Linux BSP & Kernel Debugging Lab

A structured Embedded Linux learning repository focused on Linux Kernel, BSP development, Linux Device Drivers, Boot Flow, Device Tree, Yocto, QEMU, protocol debugging, and kernel troubleshooting.

This repository represents my personal hands-on engineering lab created to strengthen practical Linux kernel and BSP knowledge through reproducible debugging exercises, driver development, and complete boot-flow analysis.

---

# About

Embedded Software Engineer with around 3 years of industry experience in Embedded Linux, BSP, Linux Kernel debugging, driver modification, protocol debugging, software validation, and embedded system integration.

This repository contains self-created learning projects and AI-assisted documentation developed outside of professional work for learning, experimentation, and interview preparation.

---

# Repository Goals

- Learn Linux Kernel Internals
- Understand complete BSP bring-up
- Practice Linux Device Driver development
- Master Boot Flow debugging
- Debug Device Tree issues
- Analyze Kernel Panic and Oops
- Practice Protocol debugging
- Build reproducible Embedded Linux labs
- Prepare for BSP and Linux Kernel interviews

---

# Technologies

- Linux Kernel 6.6
- Embedded Linux
- ARM64
- x86_64
- QEMU
- Yocto Project
- Buildroot
- PetaLinux
- U-Boot
- Device Tree (DTS/DTB)
- Platform Drivers
- Character Drivers
- PCIe
- I2C
- SPI
- UART
- GPIO
- IRQ
- hrtimer
- Spinlock
- kmalloc / kfree
- printk
- dmesg
- GDB
- objdump
- addr2line

---

# Repository Structure

```
Embedded-Linux-Lab

├── 01_Boot_Issues
├── 02_DTS_Driver_Issues
├── 03_Panic_Analysis
├── 04_Char_Driver_Issues
├── 05_I2C_Driver_Lab
├── 06_SPI_Driver_Lab
├── 07_UART_Driver_Lab
├── 08_PCIe_Driver_Lab
├── 09_Platform_Driver_Lab
├── 10_BSP_Labs
├── 11_QEMU_Labs
├── 12_Yocto_Labs
├── 13_Buildroot_Labs
├── 14_PetaLinux_Labs
├── 15_BootFlow_Analysis
├── 16_Protocol_Debugging
├── 17_Kernel_Call_Flow
├── 18_Interview_Reference
├── scripts
└── docs
```

---

# Learning Modules

## Boot Issues

- No Console
- Wrong RootFS
- Missing init
- Missing Block Driver
- Kernel Boot Analysis
- Boot Argument Debugging

---

## Device Tree & Platform Driver

- Compatible mismatch
- Missing reg property
- Probe defer
- Missing clocks
- Missing regulator
- Platform driver probe flow
- Interrupt parsing
- Driver matching
- Device registration

---

## Linux Kernel Panic Analysis

- NULL Pointer
- Stack Overflow
- Divide by Zero
- Hung Task
- Oops
- Kernel Panic
- Use After Free
- Double Free
- OOM Killer
- Unaligned Access

---

## Linux Device Driver Labs

### Character Driver

- Driver Registration
- File Operations
- copy_to_user
- copy_from_user
- ioctl
- kmalloc
- Spinlock
- Mutex
- Wait Queue
- Poll

### I2C Driver

- LM75 Driver
- Driver Probe
- Register Access
- I2C Transactions
- Device Tree Integration

### SPI Driver

- SPI Device Registration
- Transfer APIs
- Driver Matching
- Full Duplex Communication

### UART Driver

- UART Driver Flow
- Serial Communication
- Interrupt Driven UART
- Debugging Techniques

### PCIe Driver

- BAR Mapping
- Probe
- Remove
- DMA Concepts
- Interrupt Handling
- PCI Enumeration

### Platform Driver

- Device Tree Matching
- Platform Device
- Platform Driver
- Probe
- Remove

---

# BSP Labs

- Linux Kernel Build
- Kernel Configuration
- Buildroot
- Yocto
- PetaLinux
- RootFS
- Device Tree
- Bootloader
- U-Boot
- Kernel Image Generation

---

# QEMU Labs

- ARM64 QEMU
- Kernel Boot
- RootFS
- Device Tree
- Driver Loading
- Debugging
- Kernel Panic Reproduction

---

# Protocol Debugging

- I2C
- SPI
- UART
- PCIe
- Register Debugging
- Timing Analysis
- Interrupt Flow

---

# Kernel Debugging

- printk
- dmesg
- addr2line
- objdump
- gdb
- crash analysis
- stack trace
- probe debugging

---

# Interview Preparation

This repository also contains structured interview preparation covering:

- Embedded C
- Linux Internals
- Linux Device Drivers
- BSP
- Device Tree
- Boot Process
- Memory Management
- Interrupts
- Synchronization
- PCIe
- I2C
- SPI
- UART
- Kernel Debugging
- Coding Questions

---

# Lab Environment

Host
- Ubuntu 22.04

Kernel
- Linux 6.6

Architecture
- ARM64
- x86_64

Virtual Platform
- QEMU

Tools

- GCC
- Make
- Git
- GDB
- objdump
- addr2line
- Device Tree Compiler

---

# Disclaimer

This repository contains personal learning projects, AI-assisted documentation, and self-created Embedded Linux laboratory exercises.

It is intended for learning, experimentation, and interview preparation.

No proprietary source code, confidential company information, or employer-owned intellectual property is included.

---

# Future Work

- GitHub Actions CI
- Jenkins CI/CD
- Automated Kernel Module Build
- QEMU Boot Automation
- Kernel Testing Automation
- Yocto Image Automation
- Linux Kernel Patch Contributions

---

Built through continuous hands-on learning, experimentation, debugging, and practical exploration of Embedded Linux and BSP development.
