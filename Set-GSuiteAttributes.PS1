#Requires -Version 5.0
<#
.SYNOPSIS
 Sets various GSuite user attributes so that connected services can function properly
.DESCRIPTION
Using gam.exe, an encrypted oauth2.txt file, a Domain Controller,
and an AD Account with propers access to the Domain,
the script can update AD/GSuite passwords and GSuite attributes for
qualifying AD user objects.
.EXAMPLE
 Reset-GSuitePasswords.ps1 -DCs servername -ADCred $adCredObject
.EXAMPLE
 Reset-GSuitePasswords.ps1 -DCs servername -ADCred $adCredObject -WhatIf -Verbose -Debug
.EXAMPLE
 Reset-GSuitePasswords.ps1 -OneLoop -DCs servername -ADCred $adCredObject
.INPUTS
 Gam.exe oauth2.txt
 ACtive Driectory Domain Controller name.
 Active Directory account with access to the Domain Controller
 and proper OU access
.OUTPUTS
 AD objects are updated
 AD/GSuite passwords are updated
 GSuite attributes are updated
 Logging info is generated for each action
.NOTES
 This was built for use with Jenkins
#>
[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)]
 [Alias('DCs')]
 [string[]]$DomainControllers,
 # PSSession to Domain Controller and Use Active Directory CMDLETS
 [Parameter(Mandatory = $True)]
 [Alias('ADCred')]
 [System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)]
 [string]$GoogleDomain,
 [Parameter(Mandatory = $True)]
 [string]$GoogleGroup,
 [string]$StopTime = '5:00 PM',
 [Alias('wi')]
 [switch]$WhatIf
)
# ========================================New=======================================
function Add-GGroupMember {
 begin {
  Write-Verbose ('Getting {0} GSuite group members...' -f $GoogleGroup)
  ($groupList = & $gam info group $GoogleGroup) *>$null
 }
 process {
  if ($_.title -ne 'teacher') { return }

  $msg = $MyInvocation.MyCommand.Name, $_.gmail

  if ( [string]$groupList -match $_.gmail ) {
   return (Write-Verbose ("{0},[{1}] Group membership correct" -f $msg))
  }

  $vMsg = "& $gam update group {0} add user {1}" -f $GoogleGroup, $_.gmail
  Write-Verbose ("{0},[{1}]" -f $MyInvocation.MyCommand.Name, $vMsg)
  Write-Host ('{0},[{1}]' -f $msg) -F Blue
  if (-not$WhatIf) { (& $gam update group $GoogleGroup add user $_.gmail) *>$null }
 }
}

function Compare-GData {
 process {
  ($guser = & $gam print users query "email:$($_.gmail)" allfields) *>$null
  $msg = $MyInvocation.MyCommand.Name, $_.gmail
  $gObj = $guser | ConvertFrom-CSV
  if (-not$gObj) { return (Write-Verbose ("{0},[{1}] not found in GSUite" -f $msg)) }

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
   title      = if ( $_.DistinguishedName -like "*Employees*" ) { 'teacher' } else { 'student' }
  }
 }
}

function Get-ADObjs ($dcs, $cred) {
 begin {
  $creationDateCutoff = ((Get-Date).AddDays(-5)).date # Shorten days to reduce re-processing accounts
  $params = @{
   Filter     = "Created -gt '$creationDateCutoff' -and
    EmployeeID -like '*' -and
    homepage -like '*@*' -and
    Enabled -eq 'True'"
   Properties = 'employeeID', 'homepage'
  }
  $dc = Select-DomainController $dcs
  New-ADSession -dc $dc -cmdlets 'Get-ADUser' -cred $cred
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
  if ($_.update -eq $false ) { return (Write-Verbose ("{0},[{1}] Data is correct" -f $msg)), $_ }

  $gmail = $_.gmail
  $title = $_.title
  $cc = $_.costCenter

  $vMsg = "& $gam update user $gmail organization title $title costcenter $cc domain $GoogleDomain primary"
  Write-Verbose ("{0},[{1}]" -f $MyInvocation.MyCommand.Name, $vMsg)
  Write-Host ('{0},[{1}]' -f $msg) -f Blue
  if (-not$WhatIf) {
   (& $gam update user $gmail organization title $title costcenter $cc domain $GoogleDomain primary) *>$null
  }
  $_
 }
}

# ======================================== Main =======================================
. .\lib\Clear-SessionData.ps1
. .\lib\New-ADSession.ps1
. .\lib\Select-DomainController.ps1
. .\lib\Show-TestRun.ps1

$gam = '.\bin\gam.exe'

Show-TestRun

if (-not$WhatIf) { Write-Host 'Runs every 60 minutes' -F Green }

do {
 Clear-SessionData
 Get-ADObjs $DomainControllers $ADCredential | Format-Obj | Compare-GData | Update-GUser | Add-GGroupMember
 Clear-SessionData
 if (-not$WhatIf) {
  Write-Host ( 'Next Run at {0}' -f (Get-Date).AddMinutes(60) ) -F Green
  Start-Sleep (60 * 60)
 }
} until ($WhatIf -or ((Get-Date) -ge $StopTime))