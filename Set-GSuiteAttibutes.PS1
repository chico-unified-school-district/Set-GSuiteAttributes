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
 Reset-GSuitePasswords.ps1 -DC servername -ADCred $adCredObject
.EXAMPLE
 Reset-GSuitePasswords.ps1 -DC servername -ADCred $adCredObject -WhatIf -Verbose -Debug
.EXAMPLE
 Reset-GSuitePasswords.ps1 -OneLoop -DC servername -ADCred $adCredObject
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
    [Alias('DC', 'Server')]
    [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
    [string]$DomainController,
    # PSSession to Domain Controller and Use Active Directory CMDLETS  
    [Parameter(Mandatory = $True)]
    [Alias('ADCred')]
    [System.Management.Automation.PSCredential]$ADCredential,
    [switch]$OneLoop,
    [switch]$WhatIf
)

Clear-Host; $error.clear()
# Imported Sessions
# AD Domain Controller Session
$adCmdLets = 'Get-ADUser'
$adSession = New-PSSession -ComputerName $DomainController -Credential $ADCredential
Import-PSSession -Session $adSession -Module ActiveDirectory -CommandName $adCmdLets -AllowClobber

# Variables

# Imported Functions
. '.\lib\Add-Log.ps1' # Formats strings for logging purposes

# External Apps
$gam = '.\lib\gam-64\gam.exe' # GSuite cmd line tool - oauth2.txt is copied before this script runs

# Processing
$creationDateCutoff = (Get-Date).AddDays(-7)

$params = @{
    Filter     = {
        (employeeID -like "*") -and
        (homepage -like "*@ChicoUSD.net") -and
        (Enabled -eq $True)
    }
    Properties = 
    'employeeID',
    'homepage',
    'employeeNumber',
    'PasswordLastSet',
    'LastLogonDate',
    'Created'
    SearchBase = 'OU=Users,OU=Domain_Root,DC=chico,DC=usd'
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
    $userObjs = Get-ADUser @params | Where-Object { $_.created -ge $creationDateCutoff } # Get This Week's User Objects
    foreach ( $user in $userObjs ) {
        # Process AD Results
        $samid = $user.samAccountName
        [string]$id = $user.employeeID
        Write-Debug "Process $samid`?"
  
        ($guser = . $gam info user $samid) *>$null
        if ( [string]$guser -match $samid ) {
            # Check Google for a matching account
            Write-Verbose $user.samAccountName
            # GSUITE ORGANIZATION INFO
            $dn = $user.DistinguishedName
            $userType = if ( $dn -like "*Employees*" ) { 'teacher' } else { 'student' } # GSuite Title
            if ( [string]$guser -notmatch "costcenter`: $id" ) {
                # BEGIN Update org info
                # Set GSuite attributes related to MCGraw-Hill
                Add-Log action "$samid,GSUite Attributes set,title $userType,costcenter $id" $WhatIf
                if (!$WhatIf) {
                    (.$gam update user $samid@chicousd.net organization title $userType costcenter $id domain chicousd.net primary) *>$null
                }
            } # END Update org info
            # GSUITE CLASSROOM_TEACHERS MEMBERSHIP
            if ( $userType -eq 'teacher' ) {
                # add staff member to GSuite Group
                if ( [string]$classroomTeachers -notmatch "$samid@chicousd.net" ) {
                    Add-Log add "$samid,'Classroom_Teachers' GSuite group" $WhatIf
                    if (!$WhatIf) { (.$gam update group Classroom_Teachers add user $samid@chicousd.net) *>$null }
                }
            }
        }
        else { Write-Verbose "$samid not found in GSUite" } # End Check Google
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
Add-Log action "Tearing Down AD Sessions"
Get-PSSession | Remove-PSSession -WhatIf:$false