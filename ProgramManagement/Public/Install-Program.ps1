<#
    .SYNOPSIS
        Install a Program using PowerShellGet/PackageManagement Modules OR the Chocolatey CmdLine.

    .DESCRIPTION
        This function was written to make program installation on Windows as easy and generic
        as possible by leveraging existing solutions such as PackageManagement/PowerShellGet
        and the Chocolatey CmdLine.

        For any scenario in which the Chocolatey CmdLine is used, if Chocolatey is not aleady installed
        on the machine, it will be installed.

        Default behavior for this function (using only the -ProgramName parameter) is to:
        - Try installation via Chocolatey as long as the program isn't already installed via PSGet.
        - If the program is already installed via PSGet and the update via PSGet fails, then
        the program will be uninstalled via PSGet and reinstalled via Chocolatey

        If you explicitly specify -UsePowerShellGet, then:
        - PSGet will be used for the install
        - If PSGet fails, then the function will give up

        If you explicitly specify -UseChocolateyCmdLine, then:
        - The Chocolatey CmdLine will be used for the install
        - If Chocolatey fails, then the function will give up

    .NOTES

    .PARAMETER ProgramName
        This parameter is MANDATORY.

        This paramter takes a string that represents the name of the program that you'd like to install.

    .PARAMETER CommandName
        This parameter is OPTIONAL.

        This parameter takes a string that represents the name of the main executable for the installed
        program. For example, if you are installing 'openssh', the value of this parameter should be 'ssh'.

    .PARAMETER PreRelease
        This parameter is OPTIONAL.

        This parameter is a switch. If used, the latest version of the program in the pre-release branch
        (if one exists) will be installed.

    .PARAMETER GetPenultimateVersion
        This parameter is OPTIONAL.

        This parameter is a switch. If used, the version preceding the latest version of the program will
        be installed - unless Chocolatey is being used, in which case this switch will be ignored.

    .PARAMETER UsePowerShellGet
        This parameter is OPTIONAL.

        This parameter is a switch. If used the function will attempt program installation using ONLY
        PackageManagement/PowerShellGet Modules. If installation using those modules fails, the function
        halts and returns the relevant error message(s).

        Installation via the Chocolatey CmdLine will NOT be attempted.

    .PARAMETER UseChocolateyCmdLine
        This parameter is OPTIONAL.

        This parameter is a switch. If used the function will attempt installation using ONLY
        the Chocolatey CmdLine. (The Chocolatey CmdLine will be installed if it is not already).
        If installation via the Chocolatey CmdLine fails for whatever reason,
        the function halts and returns the relevant error message(s).

    .PARAMETER ExpectedInstallLocation
        This parameter is OPTIONAL.

        This parameter takes a string that represents the full path to a directory that will contain
        main executable associated with the program to be installed. This directory should be the
        immediate parent directory of the .exe.

        If you are **absolutely certain** you know where the Main Executable for the program to be installed
        will be, then use this parameter. STDOUT (i.e. Write-Host) will provide instructions on adding this
        location to the system PATH and PowerShell's $env:Path.

    .PARAMETER ScanCommonInstallDirs
        This parameter is OPTIONAL.

        This parameter is a switch. If used, common install locations will be searched for the Program's main .exe.
        If found, STDOUT (i.e. Write-Host) will provide instructions on adding this location to the system PATH and
        PowerShell's $env:Path.

    .PARAMETER Force
        This parameter is OPTIONAL.

        This parameter is a switch. If used, install will be attempted for the specified -ProgramName even if it is
        already installed.

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Install-Program -ProgramName kubernetes-cli -CommandName kubectl.exe

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Install-Program -ProgramName awscli -CommandName aws.exe -UsePowerShellGet

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Install-Program -ProgramName VisualStudioCode -CommandName Code.exe -UseChocolateyCmdLine

    .EXAMPLE
        # If the Program Name and Main Executable are the same, then this is all you need for the function to find the Main Executable
        
        PS C:\Users\zeroadmin> Install-Program -ProgramName vagrant

#>
function Install-Program {
    [CmdletBinding()]
    Param (
        [Parameter(
            Mandatory=$True,
            Position=0
        )]
        [string]$ProgramName,

        [Parameter(Mandatory=$False)]
        [string]$CommandName,

        [Parameter(Mandatory=$False)]
        [switch]$PreRelease,

        [Parameter(Mandatory=$False)]
        [switch]$GetPenultimateVersion,

        [Parameter(Mandatory=$False)]
        [switch]$UsePowerShellGet,

        [Parameter(Mandatory=$False)]
        [switch]$UseChocolateyCmdLine,

        [Parameter(Mandatory=$False)]
        [string]$ExpectedInstallLocation,

        [Parameter(Mandatory=$False)]
        [switch]$ScanCommonInstallDirs,

        [Parameter(Mandatory=$False)]
        [switch]$Force
    )

    ##### BEGIN Native Helper Functions #####

    # The below function adds Paths from System PATH that aren't present in $env:Path (this probably shouldn't
    # be an issue, because $env:Path pulls from System PATH...but sometimes profile.ps1 scripts do weird things
    # and also $env:Path wouldn't necessarily be updated within the same PS session where a program is installed...)
    function Synchronize-SystemPathEnvPath {
        $SystemPath = $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
        
        $SystemPathArray = $SystemPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
        $EnvPathArray = $env:Path -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
        
        # => means that $EnvPathArray HAS the paths but $SystemPathArray DOES NOT
        # <= means that $SystemPathArray HAS the paths but $EnvPathArray DOES NOT
        $PathComparison = Compare-Object $SystemPathArray $EnvPathArray
        [System.Collections.ArrayList][Array]$SystemPathsThatWeWantToAddToEnvPath = $($PathComparison | Where-Object {$_.SideIndicator -eq "<="}).InputObject

        if ($SystemPathsThatWeWantToAddToEnvPath.Count -gt 0) {
            foreach ($NewPath in $SystemPathsThatWeWantToAddToEnvPath) {
                if ($env:Path[-1] -eq ";") {
                    $env:Path = "$env:Path$NewPath"
                }
                else {
                    $env:Path = "$env:Path;$NewPath"
                }
            }
        }
    }

    ##### END Native Helper Functions #####

    ##### BEGIN Variable/Parameter Transforms and PreRun Prep #####

    [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

    if (!$(GetElevation)) {
        Write-Error "The $($MyInvocation.MyCommand.Name) function must be ran from an elevated PowerShell Session (i.e. 'Run as Administrator')! Halting!"
        $global:FunctionResult = "1"
        return
    }

    # Need to make sure we are on Windows
    if (-not $($PSVersionTable.PSEdition -eq "Desktop" -or $PSVersionTable.Platform -eq "Win32NT")) {
        Write-Error "The $($MyInvocation.MyCommand.Name) function must only be used on Windows! Halting"
    }

    # Make sure use is not using both -UsePowerShellGet and -UseChocolateyCmdLine
    if ($UsePowerShellGet -and $UseChocolateyCmdLine) {
        Write-Error "Please only use either the -UsePowerShellGet switch or the -UseChocolateyCmdLine switch, not both. Halting!"
        return
    }

    if ($GetPenultimateVersion -and !$UsePowerShellGet) {
        Write-Error "The get -PenultimateVersion switch must be used with the -UsePowerShellGet switch. Halting!"
        return
    }

    if ($CommandName -match "\.exe") {
        $CommandName = $CommandName -replace "\.exe",""
    }
    $FinalCommandName = if ($CommandName) {$CommandName} else {$ProgramName}

    # Save the original System PATH and $env:Path before we do anything, just in case
    $OriginalSystemPath = $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
    $OriginalEnvPath = $env:Path
    Synchronize-SystemPathEnvPath

    try {
        if ($PSVersionTable.PSEdition -ne "Core") {
            $null = Install-PackageProvider -Name Nuget -Force -Confirm:$False
            $null = Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

            # We're not going to attempt to use Chocolatey Resources with PSGet - it becomes a mess, so commenting out the below 2 lines
            #$null = Install-PackageProvider -Name Chocolatey -Force -Confirm:$False
            #$null = Set-PackageSource -Name chocolatey -Trusted -Force
        }
        else {
            $null = Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }

    # If a package provider is *not* specified or if -UseChocolateyCmdLine is explicitly specified, then we are just
    # going to use choco.exe because it is the most reliable method of getting things installed properly.
    if ($UseChocolateyCmdLine -or $(!$UsePowerShellGet -and !$UseChocolateyCmdLine)) {
        try {
            # NOTE: The Install-ChocolateyCmdLine function performs checks to see if Chocolatey is already installed, so don't worry about that
            $null = Install-ChocolateyCmdLine -ErrorAction Stop
        }
        catch {
            Write-Error "The Install-ChocolateyCmdLine function failed with the following error: $($_.Exception.Message)"
            return
        }

        try {
            if (![bool]$(Get-Command choco -ErrorAction SilentlyContinue)) {
                # The above install.ps1 probably already updated PATH, but it may not be updated in this particular PowerShell session
                # So, start a new PowerShell session and see if choco is available
                $ChocoCheck = Start-Job -Name ChocoPathTest -ScriptBlock {Get-Command choco} | Wait-Job | Receive-Job
        
                # $ChocoCheck.Source should return C:\ProgramData\chocolatey\bin\choco.exe
                if (!$ChocoCheck) {
                    try {
                        Write-Host "Refreshing `$env:Path..."
                        $null = Update-ChocolateyEnv -ErrorAction Stop
                    }
                    catch {
                        Write-Warning $_.Exception.Message
                        Write-Warning "Please start another PowerShell session in order to use the Chocolatey cmdline."
                    }
                }
        
                # If we STILL can't find choco.exe, then give up...
                if (![bool]$(Get-Command choco -ErrorAction SilentlyContinue)) {
                    Write-Error "Please start another PowerShell session in order to use the Chocolatey cmdline."
                    return
                }
            }
        }
        catch {
            Write-Error $_
            return
        }
    }

    try {
        $PackageManagerInstallObjects = Get-AllPackageInfo -ProgramName $ProgramName -ErrorAction SilentlyContinue
        [array]$ChocolateyInstalledProgramObjects = $PackageManagerInstallObjects.ChocolateyInstalledProgramObjects
        [array]$PSGetInstalledPackageObjects = $PackageManagerInstallObjects.PSGetInstalledPackageObjects
        [array]$RegistryProperties = $PackageManagerInstallObjects.RegistryProperties
        [array]$AppxInstalledPackageObjects = $PackageManagerInstallObjects.AppxAvailablePackages
    }
    catch {
        Write-Error $_
        return
    }

    # If PSGet says that a Program with a similar name is installed, get $PackageManagementCurrentVersion, $PackageManagementLatestVersion, and $PackageManagementPreviousVersion
    if ($PSGetInstalledPackageObjects.Count -eq 1) {
        $PackageManagementCurrentVersion = $PSGetInstalledPackageObjects
        $PackageManagementLatestVersion = $(Find-Package -Name $PSGetInstalledPackageObjects.Name -AllVersions | Sort-Object -Property Version -EA SilentlyContinue)[-1]
        $PackageManagementPreviousVersion = $(Find-Package -Name $PSGetInstalledPackageObjects.Name -AllVersions | Sort-Object -Property Version -EA SilentlyContinue)[-2]
    }
    if ($PSGetInstalledPackageObjects.Count -gt 1) {
        $ExactMatchCheck = $PSGetInstalledPackageObjects | Where-Object {$_.Name -eq $ProgramName}
        if (!$ExactMatchCheck) {
            Write-Warning "The following Programs are currently installed and match the string '$ProgramName':"
            for ($i=0; $i -lt $PSGetInstalledPackageObjects.Count; $i++) {
                Write-Host "$i) $($PSGetInstalledPackageObjects[$i].Name)"
            }
            $ValidChoiceNumbers = 0..$($PSGetInstalledPackageObjects.Count-1)
            $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
            while ($ValidChoiceNumbers -notcontains $ProgramChoiceNumber) {
                Write-Warning "'$ProgramChoiceNumber' is not a valid option. Please choose: $($ValidChoicenumbers -join ", ")"
                $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
            }

            $UpdatedProgramName = $PSGetInstalledPackageObjects[$ProgramChoiceNumber].Name
            $PackageManagementCurrentVersion = Get-Package -Name $UpdatedProgramName
            $PackageManagementLatestVersion = $(Find-Package -Name $UpdatedProgramName -AllVersions | Sort-Object -Property Version -EA SilentlyContinue)[-1]
            $PackageManagementPreviousVersion = $(Find-Package -Name $UpdatedProgramName -AllVersions | Sort-Object -Property Version -EA SilentlyContinue)[-2]
        }
        else {
            $PackageManagementCurrentVersion = Get-Package -Name $ProgramName
            $PackageManagementLatestVersion = $(Find-Package -Name $ProgramName -AllVersions | Sort-Object -Property Version)[-1]
            $PackageManagementPreviousVersion = $(Find-Package -Name $ProgramName -AllVersions | Sort-Object -Property Version -EA SilentlyContinue)[-2]
        }
    }

    # If Chocolatey says that a Program with a similar name is installed, get $ChocoCurrentVersion and $ChocoLatestVersion
    # Currently it's not possible to figure out $ChocoPreviousVersion reliably
    if ($ChocolateyInstalledProgramObjects.Count -gt 0) {
        if ($ChocolateyInstalledProgramObjects.Count -eq 1) {
            $ChocoCurrentVersion = $ChocolateyInstalledProgramObjects.Version
        }
        if ($ChocolateyInstalledProgramObjects.Count -gt 1) {
            $ExactMatchCheck = $ChocolateyInstalledProgramObjects | Where-Object {$_.ProgramName -eq $ProgramName}
            if (!$ExactMatchCheck) {
                Write-Warning "The following Programs are currently installed and match the string '$ProgramName':"
                for ($i=0; $i -lt $ChocolateyInstalledProgramObjects.Count; $i++) {
                    Write-Host "$i) $($ChocolateyInstalledProgramObjects[$i].ProgramName)"
                }
                $ValidChoiceNumbers = 0..$($ChocolateyInstalledProgramObjects.Count-1)
                $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
                while ($ValidChoiceNumbers -notcontains $ProgramChoiceNumber) {
                    Write-Warning "'$ProgramChoiceNumber' is not a valid option. Please choose: $($ValidChoicenumbers -join ", ")"
                    $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
                }

                $ProgramName = $ChocolateyInstalledProgramObjects[$ProgramChoiceNumber].ProgramName

                $ChocoCurrentVersion = $ChocolateyInstalledProgramObjects[$ProgramChoiceNumber].Version
            }
        }

        # Also get a list of outdated packages in case this Install-Program function is used to update a package
        $ChocolateyOutdatedProgramsPrep = choco outdated
        $UpperLineMatch = $ChocolateyOutdatedProgramsPrep -match "Output is package name"
        $LowerLineMatch = $ChocolateyOutdatedProgramsPrep -match "Chocolatey has determined"
        $UpperIndex = $ChocolateyOutdatedProgramsPrep.IndexOf($UpperLineMatch) + 2
        $LowerIndex = $ChocolateyOutdatedProgramsPrep.IndexOf($LowerLineMatch) - 2
        $ChocolateyOutdatedPrograms = $ChocolateyOutdatedProgramsPrep[$UpperIndex..$LowerIndex]

        [System.Collections.ArrayList]$ChocolateyOutdatedProgramsPSObjects = @()
        foreach ($line in $ChocolateyOutdatedPrograms) {
            $ParsedLine = $line -split "\|"
            $Program = $ParsedLine[0]
            $CurrentInstalledVersion = $ParsedLine[1]
            $LatestAvailableVersion = $ParsedLine[2]

            $PSObject = [pscustomobject]@{
                ProgramName                 = $Program
                CurrentInstalledVersion     = $CurrentInstalledVersion
                LatestAvailableVersion      = $LatestAvailableVersion
            }

            $null = $ChocolateyOutdatedProgramsPSObjects.Add($PSObject)
        }

        # Get all available Chocolatey Versions
        $AllChocoVersions = choco list $ProgramName -e --all

        # Get the latest version of $ProgramName from chocolatey
        $ChocoLatestVersion = $($AllChocoVersions[1] -split "[\s]")[1].Trim()

        # Also get the previous version of $ProgramName in case we want the previous version
        #$ChocoPreviousVersion = $($AllChocoVersions[2] -split "[\s]")[1].Trim()
    }

    ##### END Variable/Parameter Transforms and PreRun Prep #####


    ##### BEGIN Main Body #####

    $CheckLatestVersion = $(
        $PackageManagementCurrentVersion.Version -ne $PackageManagementLatestVersion.Version -or
        $ChocolateyOutdatedProgramsPSObjects.ProgramName -contains $ProgramName
    )
    $CheckPreviousVersion = $(
        $PackageManagementCurrentVersion.Version -ne $PackageManagementPreviousVersion.Version
    )
    if ($GetPenultimateVersion) {
        $VersionCheck = $CheckPreviousVersion
        $PackageManagementRequiredVersion = $PackageManagementPreviousVersion.Version
        $ChocoRequiredVersion = $ChocoLatestVersion
    }
    else {
        $VersionCheck = $CheckLatestVersion
        $PackageManagementRequiredVersion = $PackageManagementLatestVersion.Version
        $ChocoRequiredVersion = $ChocoLatestVersion
    }

    # Install $ProgramName if it's not already or if it's not the right/specified version...
    if ($($PSGetInstalledPackageObjects.Name -notcontains $ProgramName -and
    $ChocolateyInstalledProgramsPSObjects.ProgramName -notcontains $ProgramName) -or
    $VersionCheck -or $Force
    ) {
        $UsePSGetCheck = $($UsePowerShellGet -or $($PSGetInstalledPackageObjects.Name -contains $ProgramName -and $ChocolateyInstalledProgramsPSObjects.ProgramName -notcontains $ProgramName)) -and !$UseChocolateyCmdLine
        if ($UsePSGetCheck) {
            $PreInstallPackagesList = $(Get-Package).Name

            $InstallPackageSplatParams = @{
                Name            = $ProgramName
                Force           = $True
                ErrorAction     = "SilentlyContinue"
                ErrorVariable   = "InstallError"
                WarningAction   = "SilentlyContinue"
            }
            if ([bool]$PackageManagementRequiredVersion) {
                $InstallPackageSplatParams.Add("RequiredVersion",$PackageManagementRequiredVersion)
            }
            if ($PreRelease) {
                try {
                    $LatestVersion = $(Find-Package $ProgramName -AllVersions -ErrorAction Stop)[-1].Version
                    $InstallPackageSplatParams.Add("MinimumVersion",$LatestVersion)
                }
                catch {
                    Write-Verbose "Unable to find latest PreRelease version...Proceeding with 'Install-Package' without the '-MinimumVersion' parameter..."
                }
            }
            # NOTE: The PackageManagement install of $ProgramName is unreliable, so just in case, fallback to the Chocolatey cmdline for install
            $null = Install-Package @InstallPackageSplatParams
            if ($InstallError.Count -gt 0 -or $($(Get-Package).Name -match $ProgramName).Count -eq 0) {
                if ($($(Get-Package).Name -match $ProgramName).Count -gt 0) {
                    $null = Uninstall-Package $ProgramName -Force -ErrorAction SilentlyContinue
                }
                Write-Warning "There was a problem installing $ProgramName via PackageManagement/PowerShellGet!"
                
                if ($UsePowerShellGet) {
                    Write-Error "One or more errors occurred during the installation of $ProgramName via the the PackageManagement/PowerShellGet Modules failed! Installation has been rolled back! Halting!"
                    Write-Host "Errors for the Install-Package cmdlet are as follows:"
                    Write-Error $($InstallError | Out-String)
                    $global:FunctionResult = "1"
                    return
                }
                else {
                    Write-Host "Trying install via Chocolatey CmdLine..."
                    $PMInstall = $False
                }
            }
            else {
                $PMInstall = $True

                # Since Installation via PackageManagement/PowerShellGet was succesful, let's update $env:Path with the
                # latest from System PATH before we go nuts trying to find the main executable manually
                Synchronize-SystemPathEnvPath
                $env:Path = $($(Update-ChocolateyEnv -ErrorAction SilentlyContinue) -split ";" | foreach {
                    if (-not [System.String]::IsNullOrWhiteSpace($_) -and $(Test-Path $_ -ErrorAction SilentlyContinue)) {$_}
                }) -join ";"
            }
        }

        $UseChocoCheck = $(!$PMInstall -or $UseChocolateyCmdLine -or $ChocolateyInstalledProgramsPSObjects.ProgramName -contains $ProgramName) -and !$UsePowerShellGet
        if ($UseChocoCheck) {
            # Since choco installs can hang indefinitely, we're starting another powershell process and giving it a time limit
            try {
                if ($PreRelease) {
                    $CupArgs = "--pre -y"
                }
                elseif ([bool]$ChocoRequiredVersion) {
                    $CupArgs = "--version=$ChocoRequiredVersion -y"
                }
                else {
                    $CupArgs = "-y"
                }
                <#
                $ChocoPrepScript = @(
                    "`$ChocolateyResourceDirectories = Get-ChildItem -Path '$env:ProgramData\chocolatey\lib' -Directory | Where-Object {`$_.BaseName -match 'chocolatey'}"
                    '$ModulesToImport = foreach ($ChocoResourceDir in $ChocolateyResourceDirectories) {'
                    "    `$(Get-ChildItem -Path `$ChocoResourceDir.FullName -Recurse -Filter '*.psm1').FullName"
                    '}'
                    'foreach ($ChocoModulePath in $($ModulesToImport | Where-Object {$_})) {'
                    '    Import-Module $ChocoModulePath -Global'
                    '}'
                    "cup $ProgramName $CupArgs"
                )
                #>
                $ChocoPrepScript = $ChocoPrepScript -join "`n"
                $FinalArguments = "-NoProfile -NoLogo -Command `"cup $ProgramName $CupArgs`""
                
                $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
                #$ProcessInfo.WorkingDirectory = $BinaryPath | Split-Path -Parent
                $ProcessInfo.FileName = $(Get-Command powershell).Source
                $ProcessInfo.RedirectStandardError = $true
                $ProcessInfo.RedirectStandardOutput = $true
                $ProcessInfo.UseShellExecute = $false
                $ProcessInfo.Arguments = $FinalArguments
                $Process = New-Object System.Diagnostics.Process
                $Process.StartInfo = $ProcessInfo
                $Process.Start() | Out-Null
                # Below $FinishedInAlottedTime returns boolean true/false
                # Give it 120 seconds to finish installing, otherwise, kill choco.exe
                $FinishedInAlottedTime = $Process.WaitForExit(120000)
                if (!$FinishedInAlottedTime) {
                    $Process.Kill()
                }
                $stdout = $Process.StandardOutput.ReadToEnd()
                $stderr = $Process.StandardError.ReadToEnd()
                $AllOutputA = $stdout + $stderr

                #$AllOutput | Export-CliXml "$HOME\CupInstallOutput.ps1"
                
                if (![bool]$($(clist --local-only $ProgramName) -match $ProgramName)) {
                    throw "'cup $ProgramName $CupArgs' failed with the following Output:`n$AllOutputA`n$AllOutputB"
                }

                # Since Installation via the Chocolatey CmdLine was succesful, let's update $env:Path with the
                # latest from System PATH before we go nuts trying to find the main executable manually
                Synchronize-SystemPathEnvPath
                $env:Path = Update-ChocolateyEnv -ErrorAction SilentlyContinue
            }
            catch {
                Write-Warning $_.Exception.Message

                Write-Host "Trying 'cup $ProgramName $CupArgs' within this powershell process ($PID)..." -ForegroundColor Yellow

                if (Get-Command cup -ErrorAction SilentlyContinue) {
                    cup $ProgramName -y
                }
                else {
                    Write-Warning "Please start a new PowerShell session and update Chocolatey via:`n    cup chocolatey -y"
                    Write-Error "'cup $ProgramName -y' failed! Halting!"
                    return
                }

                if (![bool]$($(clist --local-only $ProgramName) -match $ProgramName)) {
                    Write-Warning "Please start a new PowerShell session and update Chocolatey via:`n    cup chocolatey -y"
                    Write-Error "'cup $ProgramName -y' failed! Halting!"
                    return
                }
            }
        }
    }
    else {
        if ($ChocolateyInstalledProgramsPSObjects.ProgramName -contains $ProgramName) {
            Write-Warning "$ProgramName is already installed via the Chocolatey CmdLine!"
            $AlreadyInstalled = $True
        }
        elseif ([bool]$(Get-Package $ProgramName -ErrorAction SilentlyContinue)) {
            Write-Warning "$ProgramName is already installed via PackageManagement/PowerShellGet!"
            $AlreadyInstalled = $True
        }
    }

    ## BEGIN Try to Find Main Executable Post Install ##

    # Remove any conflicting Aliases
    if ($(Get-Command $FinalCommandName -ErrorAction SilentlyContinue).CommandType -eq "Alias") {
        while (Test-Path Alias:\$FinalCommandName -ErrorAction SilentlyContinue) {
            Remove-Item Alias:\$FinalCommandName
        }
    }
    
    # If we can't find the main executable...
    if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue)) {
        # Try to find where the new .exe is by either using the user-provided $ExpectedInstallLocation or by comparing $OriginalSystemPath and $OriginalEnvPath to
        # the current PATH and $env:Path. THis is what the Get-ExePath function does

        $GetExePathSplatParams = @{
            GetProgramName          = $ProgramName
            OriginalSystemPath      = $OriginalSystemPath
            OriginalEnvPath         = $OriginalEnvPath
            FinalCommandName        = $FinalCommandName
        }
        if ($ExpectedInstallLocation) {
            if (Test-Path $ExpectedInstallLocation -ErrorAction SilentlyContinue) {
                $GetExePathSplatParams.Add('ExpectedInstallLocation',$ExpectedInstallLocation)
            }
        }

        [System.Collections.ArrayList][Array]$ExePath = Get-ExePath @GetExePathSplatParams

        if ($ExePath.Count -ge 1) {
            # Look for an exact match 
            if ([bool]$($ExePath -match "\\$FinalCommandName\.exe$")) {
                $FinalExeLocation = $ExePath -match "\\$FinalCommandName\.exe$"
            }
            else {
                $FinalExeLocation = $ExePath
            }
        }
    }

    # If we weren't able to find the main executable (or any potential main executables) for
    # $ProgramName, offer the option to scan the whole C:\ drive (with some obvious exceptions)
    if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue) -and @($FinalExeLocation).Count -eq 0 -and $PSBoundParameters['ScanCommonInstallDirs']) {
        # Let's seach some common installation locations for directories that match $ProgramName

        $DirectoriesToSearch = @('C:\', $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LocalAppData\Programs")

        [System.Collections.ArrayList]$ExePath = @()
        # Try to find a directory that matches the $ProgramName
        [System.Collections.ArrayList]$FoundMatchingDirs = @()
        foreach ($DirName in $DirectoriesToSearch) {
            $DirectoriesIndex = Get-ChildItem -Path $DirName -Directory
            foreach ($SubDirItem in $DirectoriesIndex) {
                if ($SubDirItem.Name -match $ProgramName) {
                    $null = $FoundMatchingDirs.Add($SubDirItem)
                }
            }
        }
        foreach ($MatchingDirItem in $FoundMatchingDirs) {
            $FilesIndex = Get-ChildItem -Path $MatchingDirItem.FullName -Recurse -File
            foreach ($FilePath in $FilesIndex.FullName) {
                if ($FilePath -match "(.*?)$FinalCommandName([^\\]+)") {
                    $null = $ExePath.Add($FilePath)
                }
            }
        }

        $FinalExeLocation = $ExePath
    }

    if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue)) {
        Write-Host "The command '$FinalCommandName' is not currently available in PATH or env:Path, however, the following locations might contain the desired command:"
        @($FinalExeLocation) | foreach {Write-Host $_}

        Write-Host "Update System PATH and PowerShell $env:Path via:"
        Write-Host "Update-SystemPathNow -PathToAdd <PathToDirectoryContainingCommand>"
    }

    if ($UseChocoCheck) {
        $InstallManager = "choco.exe"
        $InstallCheck = $(clist --local-only $ProgramName)[1]
    }
    if ($PMInstall -or [bool]$(Get-Package $ProgramName -ErrorAction SilentlyContinue)) {
        $InstallManager = "PowerShellGet"
        $InstallCheck = Get-Package $ProgramName -ErrorAction SilentlyContinue
    }

    if ($AlreadyInstalled) {
        $InstallAction = "AlreadyInstalled"
    }
    elseif (!$AlreadyInstalled -and $VersionCheck) {
        $InstallAction = "Updated"
    }
    else {
        $InstallAction = "FreshInstall"
    }

    if ($InstallAction -match "Updated|FreshInstall") {
        Write-Host "The program '$ProgramName' was installed successfully!" -ForegroundColor Green
    }
    elseif ($InstallAction -eq "AlreadyInstalled") {
        Write-Host "The program '$ProgramName' is already installed!" -ForegroundColor Green
    }

    $OutputHT = [ordered]@{
        InstallManager      = $InstallManager
        InstallAction       = $InstallAction
        InstallCheck        = $InstallCheck
    }
    if ([array]$($FinalExeLocation).Count -gt 1) {
        $OutputHT.Add("PossibleMainExecutables",$FinalExeLocation)
    }
    else {
        $OutputHT.Add("MainExecutable",$FinalExeLocation)
    }
    $OutputHT.Add("OriginalSystemPath",$OriginalSystemPath)
    $OutputHT.Add("CurrentSystemPath",$(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path)
    $OutputHT.Add("OriginalEnvPath",$OriginalEnvPath)
    $OutputHT.Add("CurrentEnvPath",$env:Path)
    
    [pscustomobject]$OutputHT

    ##### END Main Body #####
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUWqrt4eqPuliG57EZU/OWcPOh
# KIGgggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
# 9w0BAQsFADAwMQwwCgYDVQQGEwNMQUIxDTALBgNVBAoTBFpFUk8xETAPBgNVBAMT
# CFplcm9EQzAxMB4XDTE5MTEyODEyMjgyNloXDTIxMTEyODEyMzgyNlowPTETMBEG
# CgmSJomT8ixkARkWA0xBQjEUMBIGCgmSJomT8ixkARkWBFpFUk8xEDAOBgNVBAMT
# B1plcm9TQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC0crvKbqlk
# 77HGtaVMWpZBOKwb9eSHzZjh5JcfMJ33A9ORwelTAzpRP+N0k/rAoQkauh3qdeQI
# fsqdcrEiingjiOvxaX3lHA5+fVGe/gAnZ+Cc7iPKXJVhw8jysCCld5zIG8x8eHuV
# Z540iNXdI+g2mustl+l5q4kcWukj+iQwtCYEaCgAXB9qlkT33sX0k/07JoSYcGJx
# ++0SHnF0HBw7Gs/lHlyt4biIGtJleOw0iIN2yVD9UrVWMtKrghKPaW31mjYYeN5k
# ckYzBit/Kokxo0m54B4M3aLRPBQdXH1wL6A894BAlUlPM7vrozU2cLrZgcFuEvwM
# 0cLN8mfGKbo5AgMBAAGjggEqMIIBJjASBgkrBgEEAYI3FQEEBQIDAgADMCMGCSsG
# AQQBgjcVAgQWBBQIf0JBlAvGtUeDPLbljq9G8OOkkzAdBgNVHQ4EFgQUkNLPVlgd
# vV0pNGjQxY8gU/mxzMIwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDgYDVR0P
# AQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUdpW6phL2RQNF
# 7AZBgQV4tgr7OE0wMQYDVR0fBCowKDAmoCSgIoYgaHR0cDovL3BraS9jZXJ0ZGF0
# YS9aZXJvREMwMS5jcmwwPAYIKwYBBQUHAQEEMDAuMCwGCCsGAQUFBzAChiBodHRw
# Oi8vcGtpL2NlcnRkYXRhL1plcm9EQzAxLmNydDANBgkqhkiG9w0BAQsFAAOCAQEA
# WObmEzp48rKuXiJ628N7F/clqVVG+dl6UNCrPGK/fr+TbEE3RFpsPfd166gTFF65
# 5ZEbas8qW11makxfIL41GykCZSHMCJBhFhh68xnBSsplemm2CAb06+j2dkuvmOR3
# Aa9+ujtW8eSgNcSr3dkYa3fZfV3siTaY+9FmEWH8D0tglEUuUv1+KPAwXRvdNN7f
# pAsyL5qq/canjqR6/BmLSXdoD3LPISDH/iZpboBwCrhy+imupusnxjZdYFP/Siox
# g7dbvcSkr05t6jlr8xABrU+zzK3yUol/WHOnE70krG3JONBO3kN+Jv/hktIt5pd6
# imtXSPImm4BUPGa7ppeVNDCCBa8wggSXoAMCAQICE1gAAAJQw22Yn6op/pMAAwAA
# AlAwDQYJKoZIhvcNAQELBQAwPTETMBEGCgmSJomT8ixkARkWA0xBQjEUMBIGCgmS
# JomT8ixkARkWBFpFUk8xEDAOBgNVBAMTB1plcm9TQ0EwHhcNMTkxMTI4MTI1MDM2
# WhcNMjExMTI3MTI1MDM2WjBJMUcwRQYDVQQDEz5aZXJvQ29kZTEzLE9VPURldk9w
# cyxPPVRlY2ggVGFyZ2V0cywgTExDLEw9QnJ5biBNYXdyLFM9UEEsQz1VUzCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAPYULq1HCD/SgqTajXuWjnzVedBE
# Nc3LQwdDFmOLyrVPi9S9FF3yYDCTywA6wwgxSQGhI8MVWwF2Xdm+e6pLX+957Usk
# /lZGHCNwOMP//vodJUhxcyDZG7sgjjz+3qBl0OhUodZfqlprcVMQERxlIK4djDoP
# HhIBHBm6MZyC9oiExqytXDqbns4B1MHMMHJbCBT7KZpouonHBK4p5ObANhGL6oh5
# GnUzZ+jOTSK4DdtulWsvFTBpfz+JVw/e3IHKqHnUD4tA2CxxA8ofW2g+TkV+/lPE
# 9IryeA6PrAy/otg0MfVPC2FKaHzkaaMocnEBy5ZutpLncwbwqA3NzerGmiMCAwEA
# AaOCApowggKWMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQUW0DvcuEW1X6BD+eQ
# 2AJHO2eur9UwHwYDVR0jBBgwFoAUkNLPVlgdvV0pNGjQxY8gU/mxzMIwgekGA1Ud
# HwSB4TCB3jCB26CB2KCB1YaBrmxkYXA6Ly8vQ049WmVyb1NDQSgyKSxDTj1aZXJv
# U0NBLENOPUNEUCxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNl
# cyxDTj1Db25maWd1cmF0aW9uLERDPXplcm8sREM9bGFiP2NlcnRpZmljYXRlUmV2
# b2NhdGlvbkxpc3Q/YmFzZT9vYmplY3RDbGFzcz1jUkxEaXN0cmlidXRpb25Qb2lu
# dIYiaHR0cDovL3BraS9jZXJ0ZGF0YS9aZXJvU0NBKDIpLmNybDCB5gYIKwYBBQUH
# AQEEgdkwgdYwgaMGCCsGAQUFBzAChoGWbGRhcDovLy9DTj1aZXJvU0NBLENOPUFJ
# QSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25m
# aWd1cmF0aW9uLERDPXplcm8sREM9bGFiP2NBQ2VydGlmaWNhdGU/YmFzZT9vYmpl
# Y3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5MC4GCCsGAQUFBzAChiJodHRw
# Oi8vcGtpL2NlcnRkYXRhL1plcm9TQ0EoMykuY3J0MD0GCSsGAQQBgjcVBwQwMC4G
# JisGAQQBgjcVCIO49D+Em/J5g/GPOIOwtzKG0c14gSeh88wfj9lVAgFkAgEFMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMBsGCSsGAQQBgjcVCgQOMAwwCgYIKwYBBQUHAwMw
# DQYJKoZIhvcNAQELBQADggEBAEfjH/emq+TnlhFss6cNor/VYKPoEeqYgFwzGbul
# dzPdPEBFUNxcreN0b61kxfenAHifvI0LCr/jDa8zGPEOvo8+zB/GWp1Huw/xLMB8
# rfZHBCox3Av0ohjzO5Ac5yCHijZmrwaXV3XKpBncWdC6pfr/O0bIoRMbvV9EWkYG
# fpNaFvR8piUGJ47cLlC+NFTOQcmESOmlsy+v8JeG9OPsnvZLsD6sydajrxRnNlSm
# zbK64OrbSM9gQoA6bjuZ6lJWECCX1fEYDBeZaFrtMB/RTVQLF/btisfDQXgZJ+Tw
# Tjy+YP39D0fwWRfAPSRJ8NcnRw4Ccj3ngHz7e0wR6niCtsMxggH1MIIB8QIBATBU
# MD0xEzARBgoJkiaJk/IsZAEZFgNMQUIxFDASBgoJkiaJk/IsZAEZFgRaRVJPMRAw
# DgYDVQQDEwdaZXJvU0NBAhNYAAACUMNtmJ+qKf6TAAMAAAJQMAkGBSsOAwIaBQCg
# eDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEE
# AYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJ
# BDEWBBSBCv91eLjnX4AzNEsrP70ClgNNgTANBgkqhkiG9w0BAQEFAASCAQBoxbVa
# rKEoD7jQQTiRnycfEL899e9Ge737SOnEyAjxozcA+5Sh5FX1D4wg0HrqF2ghh6ii
# 4cFnnKo9FdDzU3kcTVONyRCXNbvow88vcFb2zk4EtEmf2oxw1qCvvdeM2r2a66sS
# 99pElQl5AFZVibfe0tVpk9WS1k0WqVgwjWwqbLcwH+08TFjqp0Ulmswr2wibe9Jd
# mwI13pUPpoQ51ge9B60Outi+dSaCzbVZkGonh4dh+ymI5JjLjGeW8G3QBks8llhD
# Yigz3nC49pCIdFJxHilwgKCNBjjhD9HBOzaWzReojFJzCY/6OnmFtzFXAbD66Ura
# LMPiNVa+4u8uzRII
# SIG # End signature block
