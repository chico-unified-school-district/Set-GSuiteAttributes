#Requires -Version 5.0
<#
.SYNOPSIS
Synchronizes Active Directory user attributes with Google Workspace (formerly GSuite).

.DESCRIPTION
This script automates the synchronization of user attributes between Active Directory and Google Workspace.
It performs the following key functions:
- Updates user organization details (cost center and title)
- Manages teacher group memberships
- Processes only accounts modified in the last 5 days
- Runs continuously with configurable stop time
- Uses GAM for Google Workspace operations

.PARAMETER ADCredential
PSCredential object containing AD account with necessary permissions to read user objects.

.PARAMETER GoogleDomain
The primary domain name of your Google Workspace organization (e.g., "school.edu").

.PARAMETER GoogleGroup
The email address of the Google Group to manage teacher memberships (e.g., "teachers@school.edu").

.PARAMETER StopTime
Optional. Time to stop processing (default: 5:00 PM). Format: "HH:mm tt"

.PARAMETER WhatIf
Optional. Run in test mode without making actual changes.

.EXAMPLE
# Basic usage with required parameters
Set-GSuiteAttributes.PS1 -ADCred $credentials -GoogleDomain "school.edu" -GoogleGroup "teachers@school.edu"

.EXAMPLE
# Test run with verbose logging
Set-GSuiteAttributes.PS1 -ADCred $credentials -GoogleDomain "school.edu" -GoogleGroup "teachers@school.edu" -WhatIf -Verbose

.EXAMPLE
# Run with custom stop time
Set-GSuiteAttributes.PS1 -ADCred $credentials -GoogleDomain "school.edu" -GoogleGroup "teachers@school.edu" -StopTime "6:00 PM"

.NOTES
Requirements:
- PowerShell 5.0+
- GAM installed at C:\GAM7\gam.exe
- Active Directory domain controller access
- Google Workspace admin access
- CommonScriptFunctions module
- Configured oauth2.txt for GAM authentication

The script only processes AD accounts that meet these criteria:
- Created/modified within the last 5 days
- Have an EmployeeID attribute
- Have a homepage attribute (used as Gmail address)
- Account is enabled

.LINK
https://github.com/jay0lee/GAM
#>
[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)][PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)][string]$GoogleDomain,
 [Parameter(Mandatory = $True)][string]$GoogleGroup,
 [string]$StopTime = '5:00 PM',
 [Alias('wi')][switch]$WhatIf
)
# ========================================New=======================================
function Add-GGroupMember {
 begin {
  Write-Verbose ('Getting {0} GSuite group members...' -f $GoogleGroup)
  $ErrorActionPreference = 'Continue'
  ($groupList = & $gam info group $GoogleGroup) *>$null
  $ErrorActionPreference = 'Stop'
 }
 process {
  if ($_.title -ne 'teacher') { return }

  $msg = $MyInvocation.MyCommand.Name, $_.gmail

  if ( [string]$groupList -match $_.gmail ) {
   return (Write-Verbose ('{0},[{1}] Group membership correct' -f $msg))
  }

  $vMsg = "& $gam update group {0} add user {1}" -f $GoogleGroup, $_.gmail
  Write-Verbose ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $vMsg)
  Write-Host ('{0},[{1}]' -f $msg) -F Blue
  if (-not$WhatIf) {
   $ErrorActionPreference = 'Continue'
   (& $gam update group $GoogleGroup add user $_.gmail) *>$null
   $ErrorActionPreference = 'Stop'
  }
 }
}

function Compare-GData {
 process {
  $ErrorActionPreference = 'Continue'
  ($guser = & $gam print users query "email:$($_.gmail)" allfields) *>$null
  $ErrorActionPreference = 'Stop'
  $msg = $MyInvocation.MyCommand.Name, $_.gmail
  $gObj = $guser | ConvertFrom-Csv
  if (-not$gObj) { return (Write-Verbose ('{0},[{1}] not found in GSUite' -f $msg)) }

  Write-Verbose ('{0},[{1}]' -f $msg)

  $cc = $gObj.'organizations.0.costCenter'
  $title = $gObj.'organizations.0.title'
  if ( ($cc -eq $_.costCenter) -and ($title -eq $_.title) ) {
   $_.update = $false
   return $_
  }
  $_
 }
}

function Format-Obj {
 process {
  [pscustomobject]@{
   costCenter = $_.EmployeeID
   gmail      = $_.homepage
   update     = $null
   title      = if ( $_.DistinguishedName -like '*Employees*' ) { 'teacher' } else { 'student' }
  }
 }
}

function Get-ADObjs {
 param ([Parameter(Mandatory = $True)][pscredential]$Cred)
 begin {
  $creationDateCutoff = ((Get-Date).AddDays(-5)).date # Shorten days to reduce re-processing accounts
  $params = @{
   Filter     = "Created -gt '$creationDateCutoff' -and
    EmployeeID -like '*' -and
    homepage -like '*@*' -and
    Enabled -eq 'True'"
   Properties = 'employeeID', 'homepage'
   Credential = $Cred
  }
 }
 process {
  $objs = Get-ADUser @params
  Write-Verbose ('{0} count: {1}' -f $MyInvocation.MyCommand.Name, $objs.count)
  $objs
 }
}

function Update-GUser {
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.gmail
  if ($_.update -eq $false ) { return (Write-Verbose ('{0},{1},Data is correct' -f $msg)), $_ }

  $gmail = $_.gmail
  $title = $_.title
  $cc = $_.costCenter

  $vMsg = "& $gam update user $gmail organization title $title costcenter $cc domain $GoogleDomain primary"
  Write-Verbose ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $vMsg)
  Write-Host ('{0},[{1}]' -f $msg) -f Blue
  if (-not$WhatIf) {
   $ErrorActionPreference = 'Continue'
   (& $gam update user $gmail organization title $title costcenter $cc domain $GoogleDomain primary) *>$null
   $ErrorActionPreference = 'Stop'
  }
  $_
 }
}

# ======================================== Main =======================================
Show-BlockInfo Start
Import-Module -Name 'CommonScriptFunctions'
Import-Module -Name ActiveDirectory -Cmdlet Get-ADUser -WarningAction SilentlyContinue -ErrorAction Stop

Show-BlockInfo Main
if ($WhatIf) { Show-TestRun }

$gam = 'C:\GAM7\gam.exe'

if (!$WhatIf) { Write-Host 'Runs every 60 minutes' -F Green }
do {

 Get-ADObjs -Cred $ADCredential |
  Format-Obj |
   Compare-GData |
    Update-GUser |
     Add-GGroupMember

 if ($WhatIf) { break }
 Write-Host ( 'Next Run at {0}' -f (Get-Date).AddMinutes(60) ) -F Green
 Start-Sleep (60 * 60)
} until ((Get-Date) -ge $StopTime)

if ($WhatIf) { Show-TestRun }
Show-BlockInfo End