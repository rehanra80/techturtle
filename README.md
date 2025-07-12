
# SCCM Health Check PowerShell Script

This PowerShell script generates a comprehensive SCCM Health Check Report in HTML format, combining automated diagnostics and manual review guidance. It's designed for SCCM administrators who want a quick overview of their environment's health and configuration.

---

## How to Use This Script

1. **Configure**  
   Open the script and update the following variables to match your environment:
   ```powershell
   $SiteCode = "ABC"           # Your SCCM Site Code
   $ReportPath = "C:\Temp\"    # Path to save the report
````

2. **Run**
   Execute the script from a PowerShell console on the SCCM Primary Site Server.
   Run as an account with Full Administrator rights in SCCM for complete access to all required data.

3. **Review**
   Open the generated report file (e.g., `C:\Temp\SCCM_Health_Check_Report.html`) in any modern web browser.

---

## Script Overview

### Automation & Manual Checks

* Uses WMI and SCCM PowerShell cmdlets to perform automated checks for:

  * Service status
  * Component messages
  * Object counts
* Includes "Manual Check" rows for areas that require subjective review or console-level inspection (e.g., logs or content distribution details).

### Styling

* Report design is controlled by the `$head` variable using embedded CSS.
* Output is clean, professional, and customizable.

### Error Handling

* Implements a `try/catch` block to gracefully handle connection or module-loading issues.
* Logs and handles errors during SCCM site connection.

### Automation-Friendly

* The script can be scheduled via Windows Task Scheduler for regular reporting.
* Easy to extend for custom organizational needs.

---

## Components Covered in Health Check

The script evaluates the following ConfigMgr (SCCM) components:

* Server Connectivity and Performance
* Sites and Hierarchy
* SQL Server
* Maintenance Tasks
* Status Summarisation
* Management Point
* Application Catalog
* Accounts
* Client Settings
* Discovery
* Collections
* Distribution Points and Distribution Point Groups
* Boundaries and Boundary Groups
* Endpoint Protection
* Software Metering
* Operating System Deployment
* Software Update Alerts
* Database Replication
* Content Distribution
* Deployments
* Applications
* Packages
* Devices
* Compliance Settings

---

## Notes

* This script blends automated intelligence with guided administrative insight.
* Manual check entries help ensure critical areas aren't overlooked due to automation limitations.
* Suitable for SCCM health auditing, periodic reviews, and compliance tracking.
