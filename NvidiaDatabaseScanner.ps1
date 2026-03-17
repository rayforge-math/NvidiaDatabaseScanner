# --- PARAMETERS ---
Param(
    [Parameter(Mandatory=$false)]
    [string]$TargetPath = (Join-Path $PSScriptRoot "NvidiaSearch")
)

# --- INITIALIZATION ---
Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   NVIDIA DEEP-SCAN & AUTOMATION SYSTEM        " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "[LOG] $(Get-Date -Format 'HH:mm:ss') - Initializing process..." -ForegroundColor Gray

# Ensure target directory exists without changing session location
if (!(Test-Path $TargetPath)) { 
    Write-Host "[ACTION] Creating target directory: $TargetPath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $TargetPath | Out-Null 
}
$binPath = Join-Path $TargetPath "bin"

# 1. CHECK .NET SDK
Write-Host "`n[1/5] CHECKING .NET ENVIRONMENT" -ForegroundColor Cyan
if (!(Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "[!] .NET SDK missing. Attempting installation via Winget..." -ForegroundColor Yellow
    
    try {
        winget install Microsoft.DotNet.SDK.8 --silent --accept-package-agreements --accept-source-agreements
        # Refresh environment path for the current process
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        # Verify if installation was actually successful
        if (!(Get-Command dotnet -ErrorAction SilentlyContinue)) {
            throw "Installation completed but 'dotnet' command is still not recognized."
        }
        Write-Host "[OK] .NET SDK installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "[CRITICAL] .NET SDK is required but could not be installed automatically." -ForegroundColor Red
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Please install .NET 8 SDK manually: https://dotnet.microsoft.com/download" -ForegroundColor Gray
        return # Terminate script
    }
} else {
    $sdkVer = (dotnet --version)
    Write-Host "[OK] .NET SDK active (v$sdkVer)" -ForegroundColor Green
}

# 2. SELENIUM SETUP
Write-Host "`n[2/5] CONFIGURING SELENIUM & GECKODRIVER" -ForegroundColor Cyan
Write-Host "[ACTION] Creating C# project structure in target folder..." -ForegroundColor Gray
dotnet new classlib --force --output $TargetPath | Out-Null

Write-Host "[ACTION] Fetching NuGet packages (WebDriver + GeckoDriver)..." -ForegroundColor Gray
dotnet add $TargetPath package Selenium.WebDriver | Out-Null
dotnet add $TargetPath package Selenium.WebDriver.GeckoDriver | Out-Null

Write-Host "[ACTION] Publishing binaries to $binPath..." -ForegroundColor Gray
dotnet publish $TargetPath -o $binPath | Out-Null
Write-Host "[OK] Environment setup complete." -ForegroundColor Green

# 3. LOAD LIBRARIES (RECURSIVE SEARCH)
Write-Host "`n[3/5] LOADING ASSEMBLIES" -ForegroundColor Cyan
Write-Host "[ACTION] Searching recursively for WebDriver.dll in $binPath..." -ForegroundColor Gray

# Search recursively because NuGet often places DLLs in framework-specific subfolders
$dllFile = Get-ChildItem -Path $binPath -Filter "WebDriver.dll" -Recurse | Select-Object -First 1

if (!$dllFile) { 
    Write-Host "[CRITICAL] WebDriver.dll not found in $binPath!" -ForegroundColor Red
    return 
}
Add-Type -Path $dllFile.FullName
Write-Host "[OK] WebDriver assembly loaded: $($dllFile.Name)" -ForegroundColor Green

# 4. INITIALIZE BROWSER (RECURSIVE SEARCH)
Write-Host "`n[4/5] INITIALIZING BROWSER ENGINE" -ForegroundColor Cyan
Write-Host "[ACTION] Searching recursively for geckodriver.exe in $binPath..." -ForegroundColor Gray

# Locate geckodriver.exe (usually hidden in runtimes\win-x64\native)
$geckoFile = Get-ChildItem -Path $binPath -Filter "geckodriver.exe" -Recurse | Select-Object -First 1

if (!$geckoFile) { 
    Write-Host "[CRITICAL] GeckoDriver.exe not found in $binPath!" -ForegroundColor Red
    return 
}

$options = New-Object OpenQA.Selenium.Firefox.FirefoxOptions
$options.AddArgument("--headless") 

Write-Host "[INFO] Using Driver from: $($geckoFile.FullName)" -ForegroundColor Gray
$service = [OpenQA.Selenium.Firefox.FirefoxDriverService]::CreateDefaultService($geckoFile.DirectoryName)
$driver = New-Object OpenQA.Selenium.Firefox.FirefoxDriver($service, $options)
Write-Host "[OK] Firefox instance is ready." -ForegroundColor Green

# 5. DATA EXTRACTION
try {
    Write-Host "`n[5/5] STARTING METADATA SCAN (PT, PSID, PFID)" -ForegroundColor Cyan
    Write-Host "[INFO] Navigating to NVIDIA Database..." -ForegroundColor Gray
    $driver.Navigate().GoToUrl("https://www.nvidia.com/Download/index.aspx")
    
    Write-Host "[WAIT] Sleeping 5s for AJAX initialization..." -ForegroundColor Gray
    Start-Sleep -Seconds 5

    Write-Host "[SCAN] Extracting full driver parameters via JavaScript..." -ForegroundColor Yellow

    $deepScanJs = @"
    return (async () => {
        let fullGpuList = [];
        const types = await $.ajax({
            url: dd3Config.nvServicesLocation + '/controller.php',
            data: 'com.nvidia.services.Drivers.getMenuArrays/' + JSON.stringify({pt:'1', isBeta:'0'}),
            dataType: 'json'
        });

        const activeTypes = types[0].filter(t => t.id > 0);

        for (let type of activeTypes) {
            const seriesData = await $.ajax({
                url: dd3Config.nvServicesLocation + '/controller.php',
                data: 'com.nvidia.services.Drivers.getMenuArrays/' + JSON.stringify({pt: type.id.toString(), isBeta:'0'}),
                dataType: 'json'
            });

            if (seriesData && seriesData[1]) {
                const seriesList = seriesData[1].filter(s => s.id > 0 && !s.menutext.includes('Select'));
                for (let series of seriesList) {
                    const gpuData = await $.ajax({
                        url: dd3Config.nvServicesLocation + '/controller.php',
                        data: 'com.nvidia.services.Drivers.getMenuArrays/' + JSON.stringify({pt: type.id.toString(), pst: series.id.toString(), isBeta:'0'}),
                        dataType: 'json'
                    });

                    if (gpuData && gpuData[2]) {
                        gpuData[2].filter(g => g.id > 0).forEach(gpu => {
                            fullGpuList.push({
                                type_name: type.menutext,
                                pt: type.id,
                                series_name: series.menutext,
                                psid: series.id,
                                name: gpu.menutext,
                                pfid: gpu.id,
                                search_string: type.id + '|' + series.id + '|' + gpu.id 
                            });
                        });
                    }
                }
            }
        }
        return JSON.stringify(fullGpuList);
    })();
"@

    $rawResult = $driver.ExecuteScript($deepScanJs)
    $finalList = $rawResult | ConvertFrom-Json

    # SAVE RESULTS
    Write-Host "[ACTION] Processing $($finalList.Count) entries..." -ForegroundColor Gray
    $jsonPath = Join-Path $TargetPath "NvidiaDriverMasterData.json"
    $finalList | ConvertTo-Json -Depth 5 | Out-File $jsonPath -Encoding utf8
    
    Write-Host "`n===============================================" -ForegroundColor Green
    Write-Host "   SUCCESS: METADATA COLLECTION COMPLETE" -ForegroundColor Green
    Write-Host "   Total Entries : $($finalList.Count)" -ForegroundColor White
    Write-Host "   Output File   : $jsonPath" -ForegroundColor White
    Write-Host "===============================================" -ForegroundColor Green

    # Display Preview Table
    Write-Host "`nPreview of collected driver parameters:" -ForegroundColor Gray
    $finalList | Select-Object name, pt, psid, pfid, series_name -First 15 | Format-Table -AutoSize
}
catch {
    Write-Host "`n[ERROR] Fatal error during scan: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($null -ne $driver) {
        Write-Host "`n[CLEANUP] Closing browser engine..." -ForegroundColor Gray
        $driver.Quit()
        Write-Host "[LOG] $(Get-Date -Format 'HH:mm:ss') - Process terminated. Terminal location unchanged." -ForegroundColor Gray
    }
}