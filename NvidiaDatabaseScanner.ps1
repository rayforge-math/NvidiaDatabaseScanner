# --- PARAMETERS ---
Param(
    [Parameter(Mandatory=$false)]
    [string]$TargetPath = $PSScriptRoot
)

$geckoDriver = "geckodriver.exe"
$webDriver = "WebDriver.dll"

# --- INITIALIZATION ---
Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   NVIDIA DEEP-SCAN & AUTOMATION SYSTEM        " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "[LOG] $(Get-Date -Format 'HH:mm:ss') - Initializing process..." -ForegroundColor Gray

$searchPath = $TargetPath

# 1. LOAD LIBRARIES (RECURSIVE SEARCH)
Write-Host "`n[1/3] LOADING ASSEMBLIES" -ForegroundColor Cyan
Write-Host "[ACTION] Searching for $webDriver in $searchPath..." -ForegroundColor Gray

$dllFile = Get-ChildItem -Path $searchPath -Filter "$webDriver" -Recurse | Select-Object -First 1

if (!$dllFile) { 
    Write-Host "[CRITICAL] $webDriver not found!" -ForegroundColor Red
    return 
}

Unblock-File -Path $dllFile.FullName
Add-Type -Path $dllFile.FullName
Write-Host "[OK] $webDriver assembly loaded." -ForegroundColor Green

# 2. INITIALIZE BROWSER (RECURSIVE SEARCH)
Write-Host "`n[2/3] INITIALIZING BROWSER ENGINE" -ForegroundColor Cyan
Write-Host "[ACTION] Searching for $geckoDriver in $searchPath..." -ForegroundColor Gray

$geckoFile = Get-ChildItem -Path $searchPath -Filter "$geckoDriver" -Recurse | Select-Object -First 1

if (!$geckoFile) { 
    Write-Host "[CRITICAL] $geckoDriver not found!" -ForegroundColor Red
    return 
}

$options = New-Object OpenQA.Selenium.Firefox.FirefoxOptions
$options.AddArgument("--headless") 

Write-Host "[INFO] Using Driver from: $($geckoFile.FullName)" -ForegroundColor Gray
$service = [OpenQA.Selenium.Firefox.FirefoxDriverService]::CreateDefaultService($geckoFile.DirectoryName)
$driver = New-Object OpenQA.Selenium.Firefox.FirefoxDriver($service, $options)
$driver.Manage().Timeouts().AsynchronousJavaScript = [TimeSpan]::FromMinutes(5)     # avoid client-side timeouts
Write-Host "[OK] Firefox instance is ready." -ForegroundColor Green

# 5. DATA EXTRACTION
try {
    Write-Host "`n[5/5] STARTING METADATA SCAN (PT, PSID, PFID)" -ForegroundColor Cyan
    Write-Host "[INFO] Navigating to NVIDIA Database..." -ForegroundColor Gray
    $driver.Navigate().GoToUrl("https://www.nvidia.com/Download/index.aspx")
    
    Write-Host "[WAIT] Waiting for document ready state..." -ForegroundColor Gray

    while ($driver.ExecuteScript("return document.readyState") -ne "complete") {
        Start-Sleep -Milliseconds 200
    }
    Write-Host "[OK] Document is ready." -ForegroundColor Green

    Write-Host "[SCAN] Extracting full driver parameters via JavaScript..." -ForegroundColor Yellow

    $deepScanJs = @"
    const done = arguments[arguments.length - 1]; // Seleniums Callback-Funktion
    
    (async () => {
        let fullGpuList = [];
        const seenGpuIds = new Set();
        const baseUrl = dd3Config.nvServicesLocation + '/controller.php';
        // helper to avoid server-side timeouts 
        const sleep = ms => new Promise(r => setTimeout(r, ms));

        const fetchData = async (p) => {
            try {
                // default payload to catch all possible entries
                const payload = { driverType: "all", sa: "1", isBeta: "0", ...p };
                return await $.ajax({
                    url: baseUrl,
                    timeout: 10000, // Schutz gegen hängende Einzel-Requests
                    data: 'com.nvidia.services.Drivers.getMenuArrays/' + JSON.stringify(payload),
                    dataType: 'json'
                });
            } catch (e) { return null; }
        };

        const typesResponse = await fetchData({pt: '0'});
        if (!typesResponse || !typesResponse[0]) { done("[]"); return; }

        const activeTypes = typesResponse[0].filter(t => t.id > 0);

        // check all hardware types 
        for (let type of activeTypes) {
            //await sleep(100);
            const seriesData = await fetchData({pt: type.id.toString()});
        
            if (seriesData && seriesData[1]) {
                const seriesList = seriesData[1].filter(s => s.id > 0 && !s.menutext.includes('Select'));

                // check all product series within a type 
                for (let series of seriesList) {
                    //await sleep(100); 
                    const gpuData = await fetchData({
                        pt: type.id.toString(), 
                        pst: series.id.toString()
                    });

                    // extract all hardware entries within a series 
                    if (gpuData && gpuData[2]) {
                        gpuData[2].filter(g => g.id > 0).forEach(gpu => {
                            const uniqueKey = type.id + '-' + series.id + '-' + gpu.id;
                            if (!seenGpuIds.has(uniqueKey)) {
                                seenGpuIds.add(uniqueKey);
                                fullGpuList.push({
                                    type_name: type.menutext,
                                    pt: type.id,
                                    series_name: series.menutext,
                                    psid: series.id,
                                    name: gpu.menutext,
                                    pfid: gpu.id
                                });
                            }
                        });
                    }
                }
            }
        }
        done(JSON.stringify(fullGpuList));
    })();
"@

    $rawResult = $driver.ExecuteAsyncScript($deepScanJs)
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
    Write-Host "[ACTION] Cleaning up environment..." -ForegroundColor Gray

    if ($null -ne $driver) { $driver.Quit(); $driver.Dispose() }

    $null = Get-Process "geckodriver" -ErrorAction SilentlyContinue | Stop-Process -Force
    $null = Get-Process "firefox" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "" } | Stop-Process -Force

    Write-Host "[OK] $(Get-Date -Format 'HH:mm:ss') - Cleanup complete." -ForegroundColor Green
}