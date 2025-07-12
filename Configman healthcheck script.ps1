<#
.SYNOPSIS
    Generates an HTML health check report for a System Center Configuration Manager (SCCM) environment.
.DESCRIPTION
    This script connects to an SCCM site and performs a series of health checks across various components.
    It compiles the results into a single, styled HTML file for easy review, matching the structure of the provided demo report.
    The script must be run on a machine with the Configuration Manager console installed.
.NOTES
    Author: Rehan Raze
    Version: 2.0
    Prerequisites:
    - PowerShell 5.1 or later.
    - Configuration Manager PowerShell module.
    - Run with an account that has sufficient rights in SCCM and on the Site/SQL servers.
#>

# --- Script Configuration ---

# SCCM Site Code
$SiteCode = "PS1" # <-- IMPORTANT: Change this to your site code

# Path to export the HTML report
$ReportPath = "C:\Temp\SCCM_Health_Check_Report.html" # <-- IMPORTANT: Ensure this path exists

# Thresholds for warnings
$CpuThreshold = 90 # %
$MemThreshold = 90 # %
$DiskSpaceThreshold = 15 # % Free Space
$CollectionEvalTimeThreshold = 120 # Seconds
$ClientActivityThreshold = 90 # % Active

# --- End of Configuration ---

# --- HTML Styling (CSS) ---
$head = @"
<style>
body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f4f4f4; }
h1 { color: #004488; text-align: center; }
h2 { color: #005a9e; border-bottom: 2px solid #005a9e; padding-bottom: 5px; margin-top: 30px; }
table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 15px;
    box-shadow: 0 2px 5px rgba(0,0,0,0.1);
}
th, td {
    border: 1px solid #ddd;
    padding: 10px;
    text-align: left;
    font-size: 14px;
}
th {
    background-color: #0078d4;
    color: white;
    font-weight: bold;
}
tr:nth-child(even) { background-color: #f9f9f9; }
tr:hover { background-color: #f1f1f1; }
.status-Healthy { background-color: #d4edda; color: #155724; }
.status-Warning { background-color: #fff3cd; color: #856404; }
.status-Critical { background-color: #f8d7da; color: #721c24; }
.status-Running { background-color: #d4edda; color: #155724; }
.status-ManualCheck { background-color: #e2e3e5; color: #383d41; }
.notes { font-style: italic; color: #555; }
.summary {
    background-color: #e2eef9;
    padding: 15px;
    border-left: 5px solid #0078d4;
    margin-bottom: 20px;
}
</style>
"@

# --- Function to create HTML table rows ---
function New-HealthCheckRow {
    param(
        [string]$CheckItem,
        [string]$Status,
        [string]$Notes
    )
    # Sanitize inputs to prevent HTML injection
    $CheckItem = [System.Web.HttpUtility]::HtmlEncode($CheckItem)
    $Status = [System.Web.HttpUtility]::HtmlEncode($Status)
    $Notes = [System.Web.HttpUtility]::HtmlEncode($Notes)

    # Determine the CSS class for the status cell
    $statusClass = "status-$($Status.Replace(' ', ''))"

    # Create the HTML row
    return "<tr><td>$CheckItem</td><td class='$statusClass'>$Status</td><td class='notes'>$Notes</td></tr>"
}

# --- Initialize Report ---
$reportFragments = @()
$reportFragments += "<h1>SCCM Configuration Manager Health Check Report</h1>"
$reportFragments += "<div class='summary'><strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br><strong>Site Code:</strong> $($SiteCode)</div>"

# --- Connect to SCCM Site ---
try {
    # Dynamically find and import the module
    $AdminUIPath = $env:SMS_ADMIN_UI_PATH
    if (-not $AdminUIPath) {
        throw "SMS_ADMIN_UI_PATH environment variable not found. Is the Configuration Manager console installed?"
    }
    $ModulePath = Join-Path (Split-Path $AdminUIPath) "ConfigurationManager.psd1"
    if (-not (Test-Path $ModulePath)) {
        throw "ConfigurationManager.psd1 not found at '$ModulePath'."
    }
    Import-Module $ModulePath
    if ((Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue) -eq $null) {
        New-PSDrive -Name $SiteCode -PSProvider "AdminUI.PS.Provider\CMSite" -Root $env:computername
    }
    Set-Location "$($SiteCode):"
    $Site = Get-CMSite
    $SiteServerName = $Site.ServerName
    Write-Host "Successfully connected to site $($SiteCode) on server $($SiteServerName)."
}
catch {
    Write-Error "Failed to connect to SCCM site $SiteCode. $_"
    $head = @"
    <style>body { font-family: sans-serif; } h1 { color: red; }</style>
    <h1>Error: Failed to connect to SCCM Site $SiteCode</h1>
    <p>Please ensure the Configuration Manager console is installed and the script is run with appropriate permissions.</p>
    <p>Error details: $($_.Exception.Message)</p>
"@
    ConvertTo-Html -Head $head | Out-File $ReportPath
    exit
}


# --- Report Sections ---

# Server Connectivity and Performance
$reportFragments += "<h2>Server Connectivity and Performance</h2>"
$tableRows = @()
try {
    $cpu = Get-CimInstance -ClassName Win32_Processor -ComputerName $SiteServerName | Measure-Object -Property LoadPercentage -Average
    $mem = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $SiteServerName
    $memUsedPercent = [math]::Round((($mem.TotalVisibleMemorySize - $mem.FreePhysicalMemory) / $mem.TotalVisibleMemorySize) * 100, 2)
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $SiteServerName -Filter "DriveType=3"

    $cpuStatus = if ($cpu.Average -gt $CpuThreshold) { "Warning" } else { "Healthy" }
    $memStatus = if ($memUsedPercent -gt $MemThreshold) { "Warning" } else { "Healthy" }

    $tableRows += New-HealthCheckRow -CheckItem "Site Server CPU Utilization" -Status $cpuStatus -Notes "Average Load: $($cpu.Average)%"
    $tableRows += New-HealthCheckRow -CheckItem "Site Server Memory Utilization" -Status $memStatus -Notes "$memUsedPercent% used. Free: $([math]::Round($mem.FreePhysicalMemory / 1MB, 2)) GB"

    foreach ($d in $disk) {
        $freePercent = [math]::Round(($d.FreeSpace / $d.Size) * 100, 2)
        $diskStatus = if ($freePercent -lt $DiskSpaceThreshold) { "Warning" } else { "Healthy" }
        $tableRows += New-HealthCheckRow -CheckItem "Disk Space ($($d.DeviceID))" -Status $diskStatus -Notes "$freePercent% free. ($([math]::Round($d.FreeSpace / 1GB, 2)) GB of $([math]::Round($d.Size / 1GB, 2)) GB)"
    }
}
catch {
    $tableRows += New-HealthCheckRow -CheckItem "Server Performance Checks" -Status "Critical" -Notes "Failed to query WMI on $SiteServerName. Error: $($_.Exception.Message)"
}
$reportFragments += ConvertTo-Html -As Table -Fragment -PreContent $tableRows

# Sites and Hierarchy
$reportFragments += "<h2>Sites and Hierarchy</h2>"
$tableRows = @()
$siteStatus = (Get-CMSite).Status
$siteStatusText = if ($siteStatus -eq 0) { "Healthy" } else { "Warning" }
$tableRows += New-HealthCheckRow -CheckItem "Site Server Status" -Status $siteStatusText -Notes "Site status code: $siteStatus"
$tableRows += New-HealthCheckRow -CheckItem "Intersite Replication Status" -Status "Manual Check" -Notes "Use Replication Link Analyzer for detailed status."
$tableRows += New-HealthCheckRow -CheckItem "`hman.log` for Hierarchy Manager" -Status "Manual Check" -Notes "Review hman.log on the site server for errors."
$reportFragments += ConvertTo-Html -As Table -Fragment -PreContent $tableRows

# SQL Server
$reportFragments += "<h2>SQL Server</h2>"
$tableRows = @()
$sqlServerName = $Site.SQLServerName
try {
    $sqlInstance = if ($Site.SQLServerInstanceName) { "MSSQL`$$($Site.SQLServerInstanceName)" } else { "MSSQLSERVER" }
    $sqlAgentInstance = if ($Site.SQLServerInstanceName) { "SQLAGENT`$$($Site.SQLServerInstanceName)" } else { "SQLSERVERAGENT" }
    
    $sqlService = Get-Service -Name $sqlInstance -ComputerName $sqlServerName
    $sqlAgentService = Get-Service -Name $sqlAgentInstance -ComputerName $sqlServerName
    
    $tableRows += New-HealthCheckRow -CheckItem "SQL Server Service Status" -Status $sqlService.Status -Notes "Service: $($sqlService.Name)"
    $tableRows += New-HealthCheckRow -CheckItem "SQL Server Agent Service Status" -Status $sqlAgentService.Status -Notes "Service: $($sqlAgentService.Name)"
}
catch {
    $tableRows += New-HealthCheckRow -CheckItem "SQL Service Status" -Status "Critical" -Notes "Could not connect to SQL server services on $sqlServerName. Error: $($_.Exception.Message)"
}
$tableRows += New-HealthCheckRow -CheckItem "SCCM Database Backup Status" -Status "Manual Check" -Notes "Check the 'Backup SCCM Site Server' maintenance task status."
$tableRows += New-HealthCheckRow -CheckItem "Database File Free Space" -Status "Manual Check" -Notes "Verify MDF/LDF file sizes and available space within SQL Server Management Studio."
$reportFragments += ConvertTo-Html -As Table -Fragment -PreContent $tableRows

# Maintenance Tasks
$reportFragments += "<h2>Maintenance Tasks</h2>"
$tableRows = @()
$maintTasks = Get-CMSiteMaintenanceTask
$failedTasks = $maintTasks | Where-Object { $_.LastStatus -ne "Completed" -and $_.IsEnabled -eq $true }
if ($failedTasks) {
    $tableRows += New-HealthCheckRow -CheckItem "Overall Maintenance Task Status" -Status "Warning" -Notes "$($failedTasks.Count) enabled task(s) have not completed successfully."
    foreach ($task in $failedTasks) {
        $tableRows += New-HealthCheckRow -CheckItem "Failed Task: $($task.TaskName)" -Status "Warning" -Notes "Last Status: $($task.LastStatus) at $($task.LastStartTime)"
    }
}
else {
    $tableRows += New-HealthCheckRow -CheckItem "Overall Maintenance Task Status" -Status "Healthy" -Notes "All enabled maintenance tasks completed successfully in their last run."
}
$reportFragments += ConvertTo-Html -As Table -Fragment -PreContent $tableRows

# Management Point (MP)
$reportFragments += "<h2>Management Point (MP)</h2>"
$tableRows = @()
$mps = Get-CMSiteSystemServer | Where-Object { $_.Role -eq "SMS Management Point" }
foreach ($mp in $mps) {
    $compStatus = Get-CMComponentStatusMessage -ComponentName "SMS_MP_CONTROL_MANAGER" -ComputerName $mp.ServerName -Severity Error -Hours 24
    $status = if ($compStatus) { "Warning" } else { "Healthy" }
    $tableRows += New-HealthCheckRow -CheckItem "MP Component Status ($($mp.ServerName))" -Status $status -Notes "Checked for errors in SMS_MP_CONTROL_MANAGER in the last 24 hours."
    $tableRows += New-HealthCheckRow -CheckItem "IIS Application Pool ($($mp.ServerName))" -Status "Manual Check" -Notes "Verify CcmService_AppPool is running via IIS Manager."
}
$reportFragments += ConvertTo-Html -As Table -Fragment -PreContent $tableRows

# Collection
$reportFragments += "<h2>Collection</h2>"
$tableRows = @()
$longEvalCollections = Get-CMCollection | Select-Object Name, CollectionID, LastRefreshTime, EvaluationTime | Where-Object { $_.EvaluationTime -gt $CollectionEvalTimeThreshold }
$incrementalCollections = Get-CMCollection -RefreshType 2
if ($longEvalCollections) {
    $tableRows += New-HealthCheckRow -CheckItem "Collection Evaluation Time" -Status "Warning" -Notes "$($longEvalCollections.Count) collection(s) are taking longer than $CollectionEvalTimeThreshold seconds to evaluate."
}
else {
    $tableRows += New-HealthCheckRow -CheckItem "Collection Evaluation Time" -Status "Healthy" -Notes "No collections are exceeding the evaluation time threshold."
}
$tableRows += New-HealthCheckRow -CheckItem "Number of Incrementally Enabled Collections" -Status "Healthy" -Notes "$($incrementalCollections.Count) collections are enabled for incremental updates."
$reportFragments += ConvertTo-Html -As Table -Fragment -PreContent $tableRows

# Distribution Point (DP)
$reportFragments += "<h2>Distribution Point (DP)</h2>"
$tableRows = @()
$dpStatus = Get-CMDistributionPoint | Select-Object ServerName, IsPeerDP, IsPullDP, State
$failedDps = $dpStatus | Where-Object { $_.State -ne 1 } # State 1 is 'Success'
if ($failedDps) {
    $tableRows += New-HealthCheckRow -CheckItem "DP Health Status" -Status "Warning" -Notes "$($failedDps.Count) DPs are not in a healthy state."
}
else {
    $tableRows += New-HealthCheckRow -CheckItem "DP Health Status" -Status "Healthy" -Notes "All DPs report a healthy state."
}
$tableRows += New-HealthCheckRow -CheckItem "DP Group Content Distribution" -Status "Manual Check" -Notes "Review content status in the console for DP Groups."
$reportFragments += ConvertTo-Html -As Table -Fragment -PreContent $tableRows

# Software Updates (SUP)
$reportFragments += "<h2>Software Updates (SUP)</h2>"
$tableRows = @()
try {
    $sup = Get-CMSoftwareUpdatePoint
    $syncStatus = Get-CMSoftwareUpdateSynchronizationStatus
    $statusText = if ($syncStatus.LastSyncStateName -eq "Completed") { "Healthy" } else { "Warning" }
    $tableRows += New-HealthCheckRow -CheckItem "WSUS Synchronization Status" -Status $statusText -Notes "Last Sync: $($syncStatus.LastSyncTime), Status: $($syncStatus.LastSyncStateName)"
    $tableRows += New-HealthCheckRow -CheckItem "SUP Component Health (WCM.log, WSUSCtrl.log)" -Status "Manual Check" -Notes "Review logs on $($sup.ServerName) for errors."
}
catch {
    $tableRows += New-HealthCheckRow -CheckItem "SUP Status" -Status "Critical" -Notes "Could not retrieve SUP information. Error: $($_.Exception.Message)"
}
$reportFragments += ConvertTo-Html -As Table -Fragment -PreContent $tableRows

# Devices
$reportFragments += "<h2>Devices</h2>"
$tableRows = @()
$totalDevices = (Get-CMDevice | Measure-Object).Count
$activeDevices = (Get-CMDevice -Active).Count
$activePercent = if ($totalDevices -gt 0) { [math]::Round(($activeDevices / $totalDevices) * 100, 2) } else { 0 }
$status = if ($activePercent -lt $ClientActivityThreshold) { "Warning" } else { "Healthy" }
$tableRows += New-HealthCheckRow -CheckItem "Client Activity Status" -Status $status -Notes "$activePercent% of clients are active ($activeDevices of $totalDevices)."
$tableRows += New-HealthCheckRow -CheckItem "Client Health Evaluation (ccmeval)" -Status "Manual Check" -Notes "Review client health dashboard in the console for detailed statistics."
$reportFragments += ConvertTo-Html -As Table -Fragment -PreContent $tableRows

# Add Placeholders for other sections
$placeholderSections = @(
    "Application Catalog", "Accounts", "Client Settings", "Discovery",
    "Boundary and Boundary Group", "Endpoint Protection", "Software Metering",
    "Operating System", "Alerts", "Database Replication", "Content Distribution",
    "Deployments", "Application", "Packages", "Compliance Settings"
)

foreach ($section in $placeholderSections) {
    $reportFragments += "<h2>$section</h2>"
    $tableRows = @(New-HealthCheckRow -CheckItem "Overall Status" -Status "Manual Check" -Notes "This section requires manual verification in the SCCM console or specific logs.")
    $reportFragments += ConvertTo-Html -As Table -Fragment -PreContent $tableRows
}


# --- Finalize and Export Report ---
ConvertTo-Html -Head $head -Body $reportFragments | Out-File $ReportPath

Write-Host "Health check report generated successfully at: $ReportPath"

# --- Cleanup ---
Set-Location "C:"
