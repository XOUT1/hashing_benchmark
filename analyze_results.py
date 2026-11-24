import pandas as pd

df = pd.read_csv("raw_results.csv")
nw = df[df["IsWarmup"] == False].copy()

print("Total runs:", len(df), "| Steady-state trials:", len(nw), "| Warmup passes:", len(df) - len(nw))

print("\nHash digest check (1 = identical digest across all runs):")
print(df.groupby(["SizeLabel", "Algorithm"])["HashDigest"].nunique())

print("\nSummary statistics (steady-state trials, n=5 per condition):")
summary = nw.groupby(["Phase", "Medium", "Tool", "SizeLabel", "Algorithm"]).agg(
    n=("ElapsedSeconds", "count"),
    mean_s=("ElapsedSeconds", "mean"),
    sd_s=("ElapsedSeconds", "std"),
    min_s=("ElapsedSeconds", "min"),
    max_s=("ElapsedSeconds", "max"),
    median_s=("ElapsedSeconds", "median"),
    mean_MiBs=("ThroughputMiBs", "mean"),
    sd_MiBs=("ThroughputMiBs", "std"),
).reset_index()
print(summary.to_string(index=False))

print("\nScaling ratios on RAM Disk (CertUtil):")
ram = nw[(nw["Phase"] == "RAMDiskScaling") & (nw["Tool"] == "CertUtil")]
for algo in ["MD5", "SHA512", "SHA256"]:
    t1 = ram[(ram["SizeLabel"] == "1GiB") & (ram["Algorithm"] == algo)]["ElapsedSeconds"].mean()
    t2 = ram[(ram["SizeLabel"] == "2GiB") & (ram["Algorithm"] == algo)]["ElapsedSeconds"].mean()
    t4 = ram[(ram["SizeLabel"] == "4GiB") & (ram["Algorithm"] == algo)]["ElapsedSeconds"].mean()
    tp1 = ram[(ram["SizeLabel"] == "1GiB") & (ram["Algorithm"] == algo)]["ThroughputMiBs"].mean()
    tp4 = ram[(ram["SizeLabel"] == "4GiB") & (ram["Algorithm"] == algo)]["ThroughputMiBs"].mean()
    print(f"  {algo:<6}: 2GiB/1GiB = {t2/t1:.2f}x | 4GiB/1GiB = {t4/t1:.2f}x | Throughput change 1->4GiB = {(tp4-tp1)/tp1*100:+.2f}%")

print("\n1 GiB Tool Comparison (CertUtil vs Get-FileHash on RAM Disk):")
for algo in ["MD5", "SHA512", "SHA256"]:
    cu = nw[(nw["Medium"]=="RAMDisk") & (nw["SizeLabel"]=="1GiB") & (nw["Tool"]=="CertUtil") & (nw["Algorithm"]==algo)]["ElapsedSeconds"].mean()
    gf = nw[(nw["Medium"]=="RAMDisk") & (nw["SizeLabel"]=="1GiB") & (nw["Tool"]=="GetFileHash") & (nw["Algorithm"]==algo)]["ElapsedSeconds"].mean()
    print(f"  {algo:<6}: CertUtil={cu:.3f}s vs Get-FileHash={gf:.3f}s ({(gf-cu)/cu*100:+.1f}%, {gf-cu:+.3f}s)")

print("\n1 GiB Storage Comparison (CertUtil RAM Disk vs Local SSD):")
for algo in ["MD5", "SHA512", "SHA256"]:
    rm = nw[(nw["Medium"]=="RAMDisk") & (nw["SizeLabel"]=="1GiB") & (nw["Tool"]=="CertUtil") & (nw["Algorithm"]==algo)]["ElapsedSeconds"].mean()
    ss = nw[(nw["Medium"]=="SSD") & (nw["SizeLabel"]=="1GiB") & (nw["Tool"]=="CertUtil") & (nw["Algorithm"]==algo)]["ElapsedSeconds"].mean()
    print(f"  {algo:<6}: RAMDisk={rm:.3f}s vs SSD={ss:.3f}s ({(ss-rm)/rm*100:+.1f}%, {ss-rm:+.3f}s)")
