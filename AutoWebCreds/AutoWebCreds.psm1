$ThisModule = $(Get-Item $PSCommandPath).BaseName

<#
if (!$IsWindows) {
    Write-Error "This $ThisModule must be run on PowerShell 6 or higher on a Windows operating system! Halting!"
    return
}
#>

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

# Get public and private function definition files.
[array]$Public  = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
[array]$Private = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue


# Dot source the Private functions
foreach ($import in $Private) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

[System.Collections.Arraylist]$ModulesToInstallAndImport = @()
if (Test-Path "$PSScriptRoot\module.requirements.psd1") {
    $ModuleManifestDataPrep = Import-PowerShellDataFile "$PSScriptRoot\module.requirements.psd1"
    $ModuleManifestDataPrep.Keys | Where-Object {$_ -ne "PSDependOptions"} | foreach {$null = $ModulesToinstallAndImport.Add($_)}
    $ModuleManifestData = $($ModuleManifestDataPrep.GetEnumerator()) | Where-Object {$_.Name -ne "PSDependOptions"}
}

if ($ModulesToInstallAndImport.Count -gt 0) {
    # Set $env:PSModulePath correctly
    # Determine installed PowerShell Core Versions
    $PSCoreDirItems = @(Get-ChildItem -Path "$env:ProgramFiles\Powershell" -Directory | Where-Object {$_.Name -match "[0-9]"})
    $LatestPSCoreDirPath = $($PSCoreDirItems | Sort-Object -Property CreationTime)[-1].FullName
    $PSCoreUserDocsModulePath = "$HOME\Documents\PowerShell\Modules"
    $WinPSUserDocsModulePath = "$HOME\Documents\WindowsPowerShell\Modules"
    $LatestPSCoreSystemPath = "$LatestPSCoreDirPath\Modules"
    $LatestWinPSSystemPath = "$env:ProgramFiles\WindowsPowerShell\Modules"

    $AllPSModulePaths = @(
        #$PSCoreUserDocsModulePath
        $WinPSUserDocsModulePath
        #$($LatestPSCoreDirPath | Split-Path -Parent)
        #$LatestPSCoreSystemPath
        $LatestWinPSSystemPath
        "$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"
    )

    foreach ($ModPath in $AllPSModulePaths) {
        if (![bool]$($($env:PSModulePath -split ";") -match [regex]::Escape($ModPath))) {
            $env:PSModulePath = "$ModPath;$env:PSModulePath"
        }
    }

    # Attempt to import the Module Dependencies
    foreach ($ModuleData in $ModuleManifestData) {
        $ModuleName = $ModuleData.Name

        # Make sure it's installed
        $GetModResult = @(Get-Module -ListAvailable -Name $ModuleName)
        if ($GetModResult.Count -eq 0) {
            try {
                $null = Install-Module -Name $ModuleName -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop -WarningAction SilentlyContinue
            }
            catch {
                # Try Manual Install
                $DLDir = $([IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName()) -split [regex]::Escape('.'))[0]
                $null = [IO.Directory]::CreateDirectory($DLDir)

                $InstallSplatParams = @{
                    ModuleName          = $ModuleName
                    DownloadDirectory   = $DLDir
                    ErrorAction         = 'Stop'
                    WarningAction       = 'SilentlyContinue'
                }
                
                try {
                    $null = ManualPSGalleryModuleInstall @InstallSplatParams
                }
                catch {
                    try {
                        # It might be a PreRelease
                        $InstallSplatParams.Add('PreRelease',$True)
                        $null = ManualPSGalleryModuleInstall @InstallSplatParams
                    }
                    catch {
                        Write-Error "Problem installing Module dependency $ModuleName ! Halting!"
                        return
                    }
                }
            }

            $GetModResult = @(Get-Module -ListAvailable -Name $ModuleName)
            if ($GetModResult.Count -eq 0) {
                Write-Error "Problem installing Module dependency $ModuleName ! Halting!"
                return
            }
        }
        
        # Import the Module
        if ($ModuleData.Value.PSVersion -eq "WinPS") {
            powershell.exe -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module $ModuleName -Force"
            try {
                if ($PSVersionTable.PSEdition -eq 'Core') {
                    Import-Module $ModuleName -UseWindowsPowerShell -ErrorAction Stop
                } else {
                    Import-Module $ModuleName -ErrorAction Stop
                }
            } catch {
                Write-Error "Problem importing Module dependency $ModuleName ! Halting!"
                return
            }
        }
        else {
            try {
                Import-Module -Name $ModuleName -ErrorAction Stop
            }
            catch {
                Write-Error "Problem importing Module dependency $ModuleName ! Halting!"
                return
            }
        }

        # Alternate Module Import Logic (that assumes $ThisModule is compatible with WinPS and PSCore)
        <#
        try {
            Import-Module -Name $ModuleName -ErrorAction Stop
        }
        catch {
            # If we're in PSCore, then we need to potentially try the -UseWindowsPowerShell switch
            if ($PSVersionTable.PSEdition -eq "Core") {
                try {
                    Import-Module -Name $ModuleName -UseWindowsPowerShell -ErrorAction Stop
                }
                catch {
                    Write-Error "Problem importing Module dependency $ModuleName ! Halting!"
                    return
                }
            }
            else {
                Write-Error "Problem importing Module dependency $ModuleName ! Halting!"
                return
            }
        }
        #>
    }
}

# Public Functions



function New-WebLogin {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("AmazonMusic","Audible","GooglePlay","InternetArchive","NPR","Pandora","ReelGood","Spotify","Tidal","TuneIn","YouTube","YouTubeMusic")]
        [string]$ServiceName,

        [parameter(Mandatory=$false)]
        [string]$ChromeProfileNumber
    )

    $PSCmdString = $ServiceName + 'SeleniumLoginCheck'

    if ($ChromeProfileNumber) {
        $PSCmdString = $PSCmdString + ' ' + '-ChromeProfileNumber' + ' ' + $ChromeProfileNumber
    }

    Invoke-Expression -Command $PSCmdString

}


[System.Collections.ArrayList]$script:FunctionsForSBUse = @(
    ${Function:AddPath}.Ast.Extent.Text
    ${Function:AmazonAccountLogin}.Ast.Extent.Text
    ${Function:AmazonMusicSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:AmazonMusicUserNamePwdLogin}.Ast.Extent.Text
    ${Function:AppleAccountLogin}.Ast.Extent.Text
    ${Function:AudibleSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:CheckUrlStatus}.Ast.Extent.Text
    ${Function:ChromeDriverAndEventGhostCheck}.Ast.Extent.Text
    ${Function:FacebookAccountLogin}.Ast.Extent.Text
    ${Function:GetAnyBoxPSCreds}.Ast.Extent.Text
    ${Function:GetElevation}.Ast.Extent.Text
    ${Function:GoogleAccountLogin}.Ast.Extent.Text
    ${Function:GooglePlayMusicSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:InstallEventGhost}.Ast.Extent.Text
    ${Function:InternetArchiveSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:InternetArchiveUserNamePwdLogin}.Ast.Extent.Text
    ${Function:NPRSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:NPRUserNamePwdLogin}.Ast.Extent.Text
    ${Function:PandoraSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:PandoraUserNamePwdLogin}.Ast.Extent.Text
    ${Function:ReelGoodSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:ReelGoodUserNamePwdLogin}.Ast.Extent.Text
    ${Function:SeleniumDriverSetup}.Ast.Extent.Text
    ${Function:SetupEventGhost}.Ast.Extent.Text
    ${Function:SpotifySeleniumLoginCheck}.Ast.Extent.Text
    ${Function:SpotifyUserNamePwdLogin}.Ast.Extent.Text
    ${Function:TidalSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:TidalUserNamePwdLogin}.Ast.Extent.Text
    ${Function:TuneInSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:TuneInUserNamePwdLogin}.Ast.Extent.Text
    ${Function:TwitterAccountLogin}.Ast.Extent.Text
    ${Function:UpdateSystemPathNow}.Ast.Extent.Text
    ${Function:YouTubeSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:YouTubeMusicSeleniumLoginCheck}.Ast.Extent.Text
    ${Function:New-WebLogin}.Ast.Extent.Text
)

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUO84pBVHphKdgOUqivqSep99s
# Z6igggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBS/ZsYiyIFkh8mx+q5FgutA9kPUcTANBgkqhkiG9w0BAQEFAASCAQB63dRe
# 2mkpavPViiuaaZKobHEes1/f2Rk0tIhfB1fS/4LO2XOb86OrK4r1aqlDAQyg5rRe
# Te60qhc73+9U18oPGEdFSCz4HjwfyJ7JnyYor9TbTvGu0c2iVOqTypW/o+5GQ1nZ
# a4WyJIT4i8nEQD+Rg+C3qheoxzklMC1iDFOhfhIkRxllZbotO3168haH51YHbq7Y
# LlSNlFN0sl/nmpU6hvJb8h1pQuNtdMbhzhIpMxZHrkckU6TQgPjt5u0SDSs4KpUF
# kgg0DAtNWbTO6Rr50Nq9DZqe/Uwd7yvaqnXQpIF8FypV9V0XXih+jhokLl6Ywczo
# 3sUDkz919VlIcqlF
# SIG # End signature block
