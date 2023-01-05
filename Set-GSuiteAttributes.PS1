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
 [switch]$OneLoop,
 [Alias('wi')]
 [switch]$WhatIf
)

# Imported Functions
. '.\lib\Add-Log.ps1' # Formats strings for logging purposes
. .\lib\Clear-SessionData.ps1
. .\lib\New-ADSession.ps1
. .\lib\Select-DomainController.ps1
. .\lib\Show-TestRun.ps1

Show-TestRun
Clear-SessionData

$dc = Select-DomainController $DomainControllers
New-ADSession -dc $dc -cmdlets 'Get-ADUser' -cred $ADCredential

# External Apps
$gam = '.\bin\gam-64\gam.exe'

# Processing
$creationDateCutoff = ((Get-Date).AddDays(-5)).date # Shorten days to reduce re-processing accounts

$params = @{
 # Filter     = {
 #  (employeeID -like "*") -and
 #  (homepage -like "*@*") -and
 #  (Enabled -eq $True) -and
 #  (Created -ge $creationDateCutoff)
 # }
 Filter     = " Created -gt '$creationDateCutoff' -and
 EmployeeID -like '*' -and
  homepage -like '*@*' "
 Properties =
 'employeeID',
 'homepage',
 'employeeNumber',
 'PasswordLastSet',
 'LastLogonDate',
 'Created',
 'WhenChanged'
}

if ( $WhatIf ) { $endTime = Get-Date } # DO Loop cut short on test run
else { $endTime = (get-date "5:00 PM") } # DO Loop stops at this time
if ($WhatIf) { $waitTime = 1 } else { $waitTime = 3600 } # Sleep fox x seconds between each loop.
Add-Log script "Running until $endTime" $WhatIf
if (!$WhatIf) { Add-Log script "Running every $($waitTime/60) minutes" }

do {
 Write-Verbose 'Getting Classroom_Teachers GSuite group members...'
 ($classroomTeachers = . $gam info group Classroom_Teachers) *>$null
 # Cast passwordlastset and created dates to strings and compare. Only include if strings are equal.
 Write-Verbose 'Getting qualifying AD Objects...'
 # $userObjs = Get-ADUser @params | Where-Object { $_.Enabled -eq $True } # Get User Objects
 $userObjs = Get-ADUser @params | Sort-Object -Property Created -Descending
 if ($userObjs.count -ge 1) { Write-Verbose $userObjs.count }
 foreach ( $user in $userObjs ) {
  # Process AD Results
  $samid = $user.samAccountName
  Write-Verbose $samid
  Write-Debug "Process $samid`?"

  $gSuiteEmail = $user.homepage
  [string]$id = $user.employeeID
  $dn = $user.DistinguishedName
  $userType = if ( $dn -like "*Employees*" ) { 'teacher' } else { 'student' } # GSuite Title

  ($guser = .$gam print users query $gSuiteEmail allfields) *>$null
  if ( $guser.count -le 1 ) {
   # checks num of lines in users query result.
   Write-Verbose "$samid not found in GSUite"
   continue
  }

  $guserObj = $guser | ConvertFrom-CSV
  $msgVarsGsuiteData = $samid, $guserObj.'organizations.0.costCenter', $guserObj.'organizations.0.title'
  Write-Verbose ('{0},CostCenter: [{1}],Title: [{2}]' -f $msgVarsGsuiteData)
  # Check/Set gsuite attributes
  if ( ( $guserObj.'organizations.0.costCenter' -ne $id) -or ($guserObj.'organizations.0.title' -ne $userType) ) {
   # Check Google for a matching account
   Write-Verbose ('costCenter ''{0}'' or title ''{1}'' not set for gsuite user {2}' -f $userType, $id, $user.homepage)
   # GSUITE ORGANIZATION INFO
   # Set GSuite attributes related to MCGraw-Hill
   $msgVars = $gSuiteEmail, $userType, $id, 'chicousd.net'
   Add-Log gsuiteaction ('{0},title:{1}|costCenter:{2}|domain:{3}' -f $msgVars) $WhatIf
   if (!$WhatIf) {
    (.$gam update user $samid@chicousd.net organization title $userType costcenter $id domain chicousd.net primary) *>$null
   }
   # GSUITE CLASSROOM_TEACHERS MEMBERSHIP
   if ( $userType -eq 'teacher' ) {
    # add staff member to GSuite Group
    if ( [string]$classroomTeachers -notmatch "$samid@chicousd.net" ) {
     Add-Log add "$samid,'Classroom_Teachers' GSuite group" $WhatIf
     if (!$WhatIf) { (.$gam update group Classroom_Teachers add user $samid@chicousd.net) *>$null }
    }
   }
  } # End Check/Set gsuite attributes

 } # End Process AD Results
 if ( $OneLoop ) { BREAK }
 #  Wait x seconds and run again until $endTime
 if ( !$WhatIf ) {
  "Next run at $((get-Date).AddSeconds($waitTime))"
  foreach ($n in $waitTime..1) {
   Start-Sleep 1
   # Write-Progress -Activity "Processing User Objects" -Status Waiting -Sec $n
  }
 }
} until ((get-date) -ge $endTime )

Clear-SessionData
Show-TestRun

# Get-ADUsers |