# Set-GSuiteAttributes

A PowerShell script to synchronize Active Directory user attributes with Google Workspace (formerly GSuite).

## Prerequisites

- PowerShell 5.0 or higher
- GAM (Google Apps Manager) installed at `C:\GAM7\gam.exe`
- Active Directory domain controller access
- Google Workspace admin access
- Configured oauth2.txt file for GAM authentication

## Features

- Synchronizes user attributes between AD and Google Workspace
- Updates organization details (cost center and title)
- Manages teacher group memberships
- Processes only recently modified accounts (last 5 days)
- Supports WhatIf mode for testing
- Continuous operation with configurable stop time
- Verbose logging options

## Synchronization Details

### User Selection Criteria

- Account created/modified within last 5 days
- Has EmployeeID attribute populated
- Has homepage attribute (used as Gmail address)
- Account is enabled in AD

### Synchronized Attributes

- Cost Center: Maps from AD EmployeeID
- Title: Set to "teacher" for users in Employees OU, "student" for others
- Group Membership: Teachers are added to specified Google Group

### Processing Flow

1. Retrieves qualifying AD users
2. Formats user data for comparison
3. Checks current Google Workspace attributes
4. Updates Google Workspace if differences found
5. Manages teacher group membership
6. Waits 60 minutes before next cycle

## Parameters

| Parameter         | Type         | Required | Description                                |
| ----------------- | ------------ | -------- | ------------------------------------------ |
| DomainControllers | String[]     | Yes      | AD domain controller(s) to connect to      |
| ADCredential      | PSCredential | Yes      | AD account with proper permissions         |
| GoogleDomain      | String       | Yes      | Google Workspace domain name               |
| GoogleGroup       | String       | Yes      | Google Group to manage teacher memberships |
| StopTime          | String       | No       | Time to stop processing (default: 5:00 PM) |
| WhatIf            | Switch       | No       | Run in test mode without making changes    |

## Usage Examples

```powershell
# Basic usage
Set-GSuiteAttributes.PS1 -DCs "dc01.domain.com" -ADCred $credentials -GoogleDomain "domain.com" -GoogleGroup "teachers@domain.com"

# Test run with verbose output
Set-GSuiteAttributes.PS1 -DCs "dc01.domain.com" -ADCred $credentials -GoogleDomain "domain.com" -GoogleGroup "teachers@domain.com" -WhatIf -Verbose

# Set custom stop time
Set-GSuiteAttributes.PS1 -DCs "dc01.domain.com" -ADCred $credentials -GoogleDomain "domain.com" -GoogleGroup "teachers@domain.com" -StopTime "6:00 PM"
```

## Error Handling

- Uses try-catch blocks for GAM operations
- Continues processing on individual user errors
- Logs all operations and errors
- Clears session data between cycles

## Dependencies

- CommonScriptFunctions module
- GAM for Google Workspace operations
- Active Directory PowerShell module

## Notes

- Designed for use with Jenkins automation
- Uses GAM for all Google Workspace operations
- Processes users in batches to minimize API calls
- Maintains detailed logs for troubleshooting
