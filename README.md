# Comparing MD5, SHA-256, and SHA-512 Execution Scaling and Measurement Overhead

Reproducibility package for the Vistula University **Architecture of Computer Systems (CII3SE003CI)** research paper by **Iwin Siju (Student ID: 77512)**, November 2026.

## Overview
This repository contains the PowerShell benchmark script, raw timing data, hardware telemetry, and Python summary script used to compare **MD5**, **SHA-256**, and **SHA-512** on a consumer Windows 11 laptop across two native Windows utilities (`CertUtil.exe` and PowerShell `Get-FileHash`) and two storage paths (a 6 GB ImDisk RAM disk and the local SSD).

## Files Included
- `run_benchmark.ps1` — PowerShell 5.1 script that generates deterministic non-zero binary files (`System.Random` seed `42`), records hardware/OS specs, runs 1 warmup pass plus 5 steady-state trials per condition in rotated algorithm order, and checks output hash digests.
- `system_info.txt` — Hardware and OS specifications recorded automatically on the test laptop (**Lenovo LOQ 83DV**, 13th Gen Intel Core i7-13650HX, 16 GB RAM, Windows 11 Pro Build 26200).
- `raw_results.csv` — All 120 raw timing runs (105 measured trials + 15 warmup passes), including UTC timestamps, exact file sizes, run order, execution times, throughput (MiB/s), and output digests.
- `analyze_results.py` — Python 3 script (requires `pandas`) that verifies digest consistency and reproduces every summary number reported in the manuscript.

## Requirements
- **Benchmarking:** Windows 10/11, Windows PowerShell 5.1+, native `certutil.exe`, and [ImDisk Virtual Disk Driver](https://sourceforge.net/projects/imdisk-toolkit/) (6 GB NTFS RAM disk mounted as `R:`).
- **Summary Analysis:** Python 3.9+ with `pandas`.

## How to Reproduce
1. Plug the laptop into AC power and close heavy background apps.
2. Mount a **6 GB NTFS RAM disk** at drive letter `R:` using ImDisk Virtual Disk Driver.
3. Run the benchmark from PowerShell:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\run_benchmark.ps1
   ```
   This saves `system_info.txt` and `raw_results.csv` to `C:\HashBenchResults\`.
4. Run the Python summary check:
   ```bash
   python analyze_results.py
   ```

## Expected Verification Digests (Seed 42)
Because test files are generated deterministically with seed `42`, running `run_benchmark.ps1` on any Windows machine should produce identical hashes:

| File Size | Exact Bytes | MD5 | SHA-256 (first 16 hex) | SHA-512 (first 16 hex) |
| :--- | ---: | :--- | :--- | :--- |
| 1 KiB | 1,024 | `22755BF4F31F13CF5B5FF8199186E5A9` | `58E7E5FEF17DDC65...` | `00EBCD27877B3489...` |
| 1 GiB | 1,073,741,824 | `3D7F1A28A7BFA2B12C598B043017AEA9` | `FC792826D46A658F...` | `E97DAC1201279C33...` |
| 2 GiB | 2,147,483,648 | `E0060AFDE63997D79BD84CBBB50C7A0E` | `11AB0D4FDEE31F04...` | `6D380381CFF87F0A...` |
| 4 GiB | 4,294,967,296 | `44F3408950B186A5C55AE7B3BDE1BDAD` | `00B8C6DB6A6B6757...` | `907903F9645105B7...` |

## Limitations
- Built-in Windows hashing tools do not include a switch to disable Intel SHA Extensions, so hardware acceleration is inferred from documented CPU support rather than isolated with an on/off test.
- Because the 1 GiB SSD file was generated immediately before hashing without clearing Windows cache, the SSD baseline reflects warm OS caching rather than cold physical flash reads.
- Results apply to a single consumer laptop (Lenovo LOQ 83DV, Windows 11, Balanced power plan) using single-threaded tools.
