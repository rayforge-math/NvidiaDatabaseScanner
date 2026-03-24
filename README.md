# Nvidia Database Scanner

A high-performance automation tool designed to extract hidden technical identifiers from the NVIDIA driver database. It uses PowerShell 7 and Selenium to crawl the NVIDIA API and generate a master data file containing every GPU model and its corresponding search IDs (`pt`, `psid`, `pfid`).

---

## Prerequisites

Before running the scanner, ensure your system meets these requirements:

| Requirement | Details |
|-------------|---------|
| **PowerShell 7+** | Optimized for PowerShell Core. [Download here.](https://github.com/PowerShell/PowerShell/releases) |
| **Firefox-based Browser** | Works with Mozilla Firefox, Floorp, or LibreWolf. The scanner automatically detects your browser via the Windows Registry. |

---

## Installation & Execution

The scanner is **stationary and portable** — it stores all dependencies within its own project folder.

**1. Download** – Clone the repository.

**2. Set Execution Policy** – Open PowerShell 7 and allow script execution:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**3. Run the Scanner:**

- **Default** – Stores the resulting `NvidiaDriverMasterData.json` next to the script:
  ```powershell
  .\NvidiaDatabaseScanner.ps1
  ```
- **Custom Path** – Store the resulting `NvidiaDriverMasterData.json` in a specific location:
  ```powershell
  .\NvidiaDatabaseScanner.ps1 -TargetPath "C:\Custom\Path"
  ```

---

## Metadata Reference (JSON Structure)

The generated `NvidiaDriverMasterData.json` maps human-readable names to the technical IDs required for NVIDIA driver API lookups.

### Example Entry

```json
{
  "type_name": "GeForce",
  "pt": 1,
  "series_name": "GeForce RTX 50 Series (Notebooks)",
  "psid": 133,
  "name": "NVIDIA GeForce RTX 5090 Laptop GPU",
  "pfid": 1073,
  "search_string": "1|133|1073"
}
```

### Field Definitions

| Field | Description |
|-------|-------------|
| `type_name` | The broad product category (e.g., GeForce, Quadro, Tesla). |
| `pt` | **Product Type ID** – The primary category ID (e.g., `1` for GeForce). |
| `series_name` | The marketing generation of the hardware. |
| `psid` | **Product Series ID** – Identifies the specific generation within a category. |
| `name` | **GPU Model** – The full name of the specific graphics card. |
| `pfid` | **Product Family ID** – The unique fingerprint for that specific card. |
| `search_string` | **Legacy Format** – A pre-joined string in `pt\|psid\|pfid` format for direct API use. |

---

## Troubleshooting

### 1. Browser Detection (Floorp / Custom Installs)

The scanner uses GeckoDriver, which locates your browser (Firefox, Floorp, etc.) via the Windows **App Paths** Registry.

### 2. File Not Found (Recursive Search)

The scanner performs a recursive search within the `bin` folder to locate `WebDriver.dll` and `geckodriver.exe`.

- If it reports "Not Found", verify the binaries/libraries are present.
- Check whether your **Firewall or Antivirus** is blocking `geckodriver.exe` from executing.

---

## Automation Logic

The scanner performs a **Deep AJAX Scan**. Instead of simulating clicks through dropdown menus, it injects an asynchronous JavaScript collector that communicates directly with NVIDIA's `controller.php` backend. This approach is significantly faster and more reliable than standard UI automation.

### Request Reverse Engineering

The API request structure was derived by inspecting the bundled client-side JavaScript on NVIDIA's driver download page. Specifically, the file:

```
clientlib-driverflownvlookup.min.<hash>.js
```

(where `<hash>` is a versioned hex string, e.g. `f47c018386396534b27cb5a8733688e3`) was analyzed via browser DevTools to understand how the frontend constructs its lookup requests against `controller.php`. The relevant query parameters, payload structure, and endpoint behavior were extracted from this minified bundle and used as the basis for the scanner's direct API calls.
