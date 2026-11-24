$ErrorActionPreference = "Stop"

if (-not (Test-Path "R:\")) {
    Write-Error "Drive R:\ was not found. Mount a 6 GB NTFS ImDisk RAM disk as R: first."
    exit 1
}

$rDrive = Get-PSDrive -Name R
if ($rDrive.Free -lt 4.5GB) {
    Write-Error "Drive R:\ needs at least 4.5 GB free space. Empty R: or mount a 6 GB RAM disk."
    exit 1
}

$outDir = "C:\HashBenchResults"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$sysPath = Join-Path $outDir "system_info.txt"
$csvPath = Join-Path $outDir "raw_results.csv"

$cs = Get-CimInstance Win32_ComputerSystem
$cpu = @(Get-CimInstance Win32_Processor)[0]
$os = Get-CimInstance Win32_OperatingSystem
$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
$powerPlan = (& powercfg /getactivescheme 2>&1) -join " "
$ramGB = [Math]::Round($cs.TotalPhysicalMemory / 1GB, 2)

$sysLines = @(
    "TimestampUTC: $((Get-Date).ToUniversalTime().ToString('o'))"
    "Manufacturer: $($cs.Manufacturer)"
    "Model: $($cs.Model)"
    "CPU_Name: $($cpu.Name)"
    "CPU_Cores: $($cpu.NumberOfCores)"
    "CPU_LogicalProcessors: $($cpu.NumberOfLogicalProcessors)"
    "CPU_MaxClockMHz: $($cpu.MaxClockSpeed)"
    "CPU_L2CacheKB: $($cpu.L2CacheSize)"
    "CPU_L3CacheKB: $($cpu.L3CacheSize)"
    "TotalRAM_GB: $ramGB"
    "OS_Caption: $($os.Caption)"
    "OS_Version: $($os.Version)"
    "OS_Build: $($os.BuildNumber)"
    "PowerShell_Version: $($PSVersionTable.PSVersion)"
    "PowerPlan: $powerPlan"
    "BatteryStatus: $(if ($bat) { $bat.BatteryStatus } else { 'DesktopOrUnknown' })"
)
$sysLines | Set-Content -Path $sysPath -Encoding UTF8

function New-DeterministicFile {
    param([string]$Path, [int64]$Bytes)
    $rng = New-Object System.Random 42
    $chunkSize = [int][Math]::Min([int64]4MB, [int64]$Bytes)
    $buf = New-Object byte[] $chunkSize
    $fs = [System.IO.File]::Create($Path)
    try {
        [int64]$written = 0
        while ($written -lt $Bytes) {
            $toWrite = [int][Math]::Min([int64]$chunkSize, [int64]($Bytes - $written))
            $rng.NextBytes($buf)
            $fs.Write($buf, 0, $toWrite)
            $written += $toWrite
        }
        $fs.Flush()
    } finally {
        $fs.Dispose()
    }
}

function Invoke-HashTrial {
    param(
        [string]$Phase,
        [string]$Medium,
        [string]$Tool,
        [string]$SizeLabel,
        [int64]$ExactBytes,
        [string]$FilePath,
        [int]$Trial,
        [bool]$IsWarmup,
        [string]$RunOrder,
        [string]$Algorithm
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    if ($Tool -eq "CertUtil") {
        $out = & certutil.exe -hashfile $FilePath $Algorithm 2>&1
        $sw.Stop()
        if ($LASTEXITCODE -ne 0) {
            throw "CertUtil failed on $FilePath ($Algorithm): $out"
        }
        $digest = ($out[1].ToString().Trim() -replace "\s", "").ToUpperInvariant()
    } else {
        $res = Get-FileHash -Path $FilePath -Algorithm $Algorithm
        $sw.Stop()
        $digest = $res.Hash.ToUpperInvariant()
    }
    $sec = $sw.Elapsed.TotalSeconds
    $mib = $ExactBytes / 1048576.0
    $tp = if ($sec -gt 0) { [Math]::Round($mib / $sec, 4) } else { 0 }

    return [PSCustomObject]@{
        TimestampUTC   = (Get-Date).ToUniversalTime().ToString("o")
        Phase          = $Phase
        Medium         = $Medium
        Tool           = $Tool
        SizeLabel      = $SizeLabel
        ExactBytes     = $ExactBytes
        Trial          = $Trial
        IsWarmup       = $IsWarmup
        RunOrder       = $RunOrder
        Algorithm      = $Algorithm
        ElapsedSeconds = [Math]::Round($sec, 6)
        ThroughputMiBs = $tp
        HashDigest     = $digest
    }
}

$results = New-Object System.Collections.Generic.List[object]

$orders = @(
    @("MD5", "SHA256", "SHA512"),
    @("SHA256", "SHA512", "MD5"),
    @("SHA512", "MD5", "SHA256"),
    @("MD5", "SHA512", "SHA256"),
    @("SHA256", "MD5", "SHA512")
)

function Run-RotatedSuite {
    param(
        [string]$Phase,
        [string]$Medium,
        [string]$Tool,
        [string]$SizeLabel,
        [int64]$ExactBytes,
        [string]$FilePath,
        [int]$Trials,
        [bool]$IncludeWarmup
    )
    if ($IncludeWarmup) {
        foreach ($algo in @("MD5", "SHA256", "SHA512")) {
            Write-Host "[$Phase | $Medium | $Tool | $SizeLabel] Warmup $algo..."
            $results.Add((Invoke-HashTrial $Phase $Medium $Tool $SizeLabel $ExactBytes $FilePath 0 $true "MD5_SHA256_SHA512" $algo))
        }
    }
    for ($t = 1; $t -le $Trials; $t++) {
        $order = $orders[($t - 1) % $orders.Count]
        $orderLabel = $order -join "_"
        foreach ($algo in $order) {
            Write-Host "[$Phase | $Medium | $Tool | $SizeLabel] Trial $t/$Trials $algo..."
            $results.Add((Invoke-HashTrial $Phase $Medium $Tool $SizeLabel $ExactBytes $FilePath $t $false $orderLabel $algo))
        }
    }
}

$ramSizes = @(
    @{ Label = "1KiB"; Bytes = [int64]1024; Warmup = $false; RunGetFileHash = $true  },
    @{ Label = "1GiB"; Bytes = [int64]1GB;  Warmup = $true;  RunGetFileHash = $true  },
    @{ Label = "2GiB"; Bytes = [int64]2GB;  Warmup = $true;  RunGetFileHash = $false },
    @{ Label = "4GiB"; Bytes = [int64]4GB;  Warmup = $true;  RunGetFileHash = $false }
)

foreach ($item in $ramSizes) {
    $path = "R:\bench_$($item.Label).bin"
    Write-Host "Generating $path ($($item.Bytes) bytes)..."
    New-DeterministicFile -Path $path -Bytes $item.Bytes
    try {
        $phase = if ($item.Label -eq "1KiB") { "OverheadBaseline" } else { "RAMDiskScaling" }
        Run-RotatedSuite $phase "RAMDisk" "CertUtil" $item.Label $item.Bytes $path 5 $item.Warmup
        if ($item.RunGetFileHash) {
            Run-RotatedSuite "ToolComparison" "RAMDisk" "GetFileHash" $item.Label $item.Bytes $path 5 $item.Warmup
        }
    } finally {
        if (Test-Path $path) { Remove-Item -Path $path -Force }
    }
}

$ssdFile = Join-Path $outDir "bench_1GiB_ssd.bin"
Write-Host "Generating $ssdFile (1 GiB SSD baseline)..."
New-DeterministicFile -Path $ssdFile -Bytes ([int64]1GB)
try {
    Run-RotatedSuite "StorageBaseline" "SSD" "CertUtil" "1GiB" ([int64]1GB) $ssdFile 5 $true
} finally {
    if (Test-Path $ssdFile) { Remove-Item -Path $ssdFile -Force }
}

$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "DONE. Saved system_info.txt and raw_results.csv to $outDir"
