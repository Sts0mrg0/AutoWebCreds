[![Build status](https://ci.appveyor.com/api/projects/status/github/pldmgg/=master&svg=true)](https://ci.appveyor.com/project/pldmgg/autowebcreds/branch/master)


# AutoWebCreds
This Module takes advantage of Selenium chromedriver.exe, EventGhost, and the Windows Credential Manager to automatically login to many different web services.
Currently, this module does not handle 2-factor authentication, I'll see what I can do in the future.

## Getting Started

```powershell
# One time setup
    # Download the repository
    # Unblock the zip
    # Extract the AutoWebCreds folder to a module path (e.g. $env:USERPROFILE\Documents\WindowsPowerShell\Modules\)
# Or, with PowerShell 5 or later or PowerShellGet:
    Install-Module AutoWebCreds

# Import the module.
    Import-Module AutoWebCreds    # Alternatively, Import-Module <PathToModuleFolder>

# Get commands in the module
    Get-Command -Module AutoWebCreds

# Get help
    Get-Help <AutoWebCreds Function> -Full
    Get-Help about_AutoWebCreds
```

## Examples

### Scenario 1

```powershell
powershell code
```

## Notes

* PSGallery: 
