# Wildlife Camera Trap — Image Deduplication System

**UNPLUGGED Hardware Hackathon | Method 2: Verilog/VHDL**  
**Team:** ByteBuilders | **College:** VESIT, Mumbai  
**Target FPGA:** Digilent Basys 3 Artix-7 (xc7a35tcpg236-1) | **Tool:** Vivado 2018.3

---

## Problem Statement

Wildlife camera traps continuously capture fixed-size greyscale image blocks (8-bit pixels). Due to repeated triggers and environmental variations, many captured images are visually similar. This wastes storage and transmission bandwidth.

**Goal:** Design a synthesisable Verilog hardware module that generates a 64-bit image signature, compares two signatures, and outputs a duplicate flag when similarity exceeds a configurable threshold — in real time, without a CPU.

---

## Solution Overview

We implement a **perceptual hashing** algorithm entirely in hardware:

1. Divide the image into an 8×8 grid (64 cells)
2. Compute the average brightness of each cell
3. Compare each cell average to the global mean → set 1 bit per cell
4. This produces a 64-bit signature (fingerprint)
5. XOR two signatures and count differing bits (**Hamming distance**)
6. If `hamming_dist <= THRESHOLD` → images are duplicates

---

## Repository Structure

```
wildlife_dedup/
├── src/
│   ├── image_signature_gen.v     # Core FSM — generates 64-bit perceptual hash
│   ├── signature_comparator.v    # Hamming distance popcount adder tree
│   └── wildlife_cam_dedup.v      # Top-level wrapper
├── tb/
│   └── tb_wildlife_cam_dedup.v   # Self-checking testbench (5 test cases)
├── docs/
│   ├── waveform_screenshot.png   # Vivado XSim simulation waveform
│   └── design_report.docx        # Full design explanation report
└── README.md
```

---

## Module Descriptions

### `image_signature_gen`
4-state FSM that processes a streaming pixel input and outputs a 64-bit hash.

| State | Action |
|-------|--------|
| `S_IDLE` | Wait for first pixel. Clear all 64 accumulators. |
| `S_ACCUM` | 4096 cycles — accumulate each pixel into its 8×8 cell |
| `S_COMPUTE` | 128 cycles — Phase 0: compute cell means. Phase 1: compare to global mean, set bits |
| `S_DONE` | Assert `sig_valid` for 1 cycle |

### `signature_comparator`
Combinational 5-stage binary adder tree that counts differing bits between two 64-bit signatures (popcount of XOR). Result ready in the same cycle `compare_en` is asserted.

### `wildlife_cam_dedup` (Top Level)
Instantiates two `image_signature_gen` modules (one per channel) and one `signature_comparator`.

---

## Port Reference

### `wildlife_cam_dedup` top-level ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | System clock (100 MHz) |
| `rst_n` | in | 1 | Active-low synchronous reset |
| `pixel_in_a` | in | 8 | Image A pixel (greyscale) |
| `pixel_valid_a` | in | 1 | High for one cycle per pixel |
| `image_done_a` | in | 1 | Pulse after last pixel of Image A |
| `pixel_in_b` | in | 8 | Image B pixel |
| `pixel_valid_b` | in | 1 | High for one cycle per pixel |
| `image_done_b` | in | 1 | Pulse after last pixel of Image B |
| `compare_en` | in | 1 | Trigger comparison after both sigs ready |
| `sig_a` | out | 64 | 64-bit hash of Image A |
| `sig_b` | out | 64 | 64-bit hash of Image B |
| `sig_a_valid` | out | 1 | Pulses when sig_a is ready |
| `sig_b_valid` | out | 1 | Pulses when sig_b is ready |
| `hamming_dist` | out | 7 | Number of differing bits (0–64) |
| `is_duplicate` | out | 1 | 1 if images are similar |
| `result_valid` | out | 1 | Pulses when result is ready |

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `IMG_WIDTH` | 64 | Image width in pixels |
| `IMG_HEIGHT` | 64 | Image height in pixels |
| `THRESHOLD` | 10 | Max Hamming distance to classify as duplicate |

---

## Simulation Results

Simulated in **Vivado 2018.3 XSim** (Behavioural). Total runtime: **910,595 ns @ 100 MHz**.

| Test Case | Image A | Image B | Expected | Hamming | Result |
|-----------|---------|---------|----------|---------|--------|
| TC1 | Gradient | Identical gradient | DUPLICATE | 0 | ✅ PASS |
| TC2 | Gradient | Gradient + 5 brightness | DUPLICATE | 0 | ✅ PASS |
| TC3 | Gradient | Checkerboard | NOT DUPLICATE | 32 | ✅ PASS |
| TC4 | Gradient | Inverted gradient | NOT DUPLICATE | 64 | ✅ PASS |
| TC5 | Uniform grey | Same uniform grey | DUPLICATE | 0 | ✅ PASS |

**5 / 5 PASSED**

---

## How to Run the Simulation
<!--
### Option 1 — TCL script (fastest)

```bash
cd wildlife_dedup
vivado -mode tcl -source create_project.tcl
```

### Option 2 — Vivado GUI
-->
1. Open Vivado 2018.3
2. Create new project → part `xc7a35tcpg236-1`
3. Add design sources: all `.v` files from `src/`
4. Add simulation source: `tb/tb_wildlife_cam_dedup.v`
5. Set top: `wildlife_cam_dedup` (sources), `tb_wildlife_cam_dedup` (sim)
6. Flow Navigator → Run Simulation → Run Behavioral Simulation
7. In TCL console: `run all`

---

## Timing Summary

| Phase | Duration @ 100 MHz |
|-------|--------------------|
| Pixel stream (64×64) | 40.96 µs per channel |
| S_COMPUTE | 1.28 µs |
| Comparison | 1 clock cycle (10 ns) |
| **Total per frame pair** | **~83 µs** |

---

## Resource Utilisation (estimated, Artix-7)

| Resource | Usage |
|----------|-------|
| Flip-flops | ~1600 (64 × 24-bit accumulators) |
| LUTs | ~200 (FSM logic + popcount tree) |
| DSP blocks | 0 |
| BRAM | 0 |

---

## Video Demo

[YouTube link — add after recording]

---

## References

- Perceptual Hashing: [phash.org](http://phash.org)
- Basys 3 Reference Manual: [Digilent](https://digilent.com/reference/programmable-logic/basys-3/start)
- Vivado Design Suite User Guide: [Xilinx UG835](https://www.xilinx.com/support/documentation/sw_manuals/xilinx2018_3/ug835-vivado-tcl-commands.pdf)
