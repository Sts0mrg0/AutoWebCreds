function TidalSeleniumLoginCheck {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$false)]
        [ValidatePattern('[0-9]')]
        [int]$ChromeProfileNumber = '0',

        [parameter(Mandatory=$true)]
        [ValidateSet("UserNamePwd","Apple","Facebook","Twitter")]
        [string]$LoginType
    )

    $ServiceName = "Tidal"
    $SiteUrl = "https://listen.tidal.com/"

    $ChromeUserData = "$HOME\AppData\Local\Google\Chrome\User Data"
    $AvailableProfiles = $(Get-ChildItem -Path $ChromeUserData -Directory -Filter "Profile *").Name
    $ProfileDirName = 'Profile ' + $ChromeProfileNumber
    $ChromeProfile = @($AvailableProfiles) -match $ProfileDirName
    if (!$ChromeProfile) {
        Write-Error "Unable to find Chrome Profile '$ProfileDirName'. Halting!"
        return
    }

    switch ($LoginType) {
        'UserNamePwd'   {$Message = "Login to $ServiceName with a dedicated $ServiceName UserName and Password"}
        'Apple'         {$Message = "Login to $ServiceName using your $LoginType account UserName and Password"}
        'Facebook'      {$Message = "Login to $ServiceName using your$LoginType account UserName and Password"}
        'Twitter'       {$Message = "Login to $ServiceName using your $LoginType account UserName and Password"}
    }

    # Make sure we can connect to the Url
    try {
        $null = CheckUrlStatus -SiteUrl $SiteUrl
    } catch {
        Write-Error $_
        return
    }

    try {
        $null = ChromeDriverAndEventGhostCheck -ErrorAction Stop
    } catch {
        Write-Error $_
        return
    }

    try {
        $Driver = Start-SeChrome -Arguments @("window-size=1200x600", "user-data-dir=$ChromeUserData", "profile-directory=$ChromeProfile")
        # The below Tab + Enter will clear either the "Chrome was not shutdown properly" message or the "Chrome is being controlled by automated software" message
        #[OpenQA.Selenium.Interactions.Actions]::new($Driver).SendKeys([OpenQA.Selenium.Keys]::Tab).Perform()
        #[OpenQA.Selenium.Interactions.Actions]::new($Driver).SendKeys([OpenQA.Selenium.Keys]::Enter).Perform()
        #& "C:\Program Files (x86)\EventGhost\EventGhost.exe" -event ClearChromeRestoreMsg
        $EventGhostProcess = Get-Process eventghost -ErrorAction SilentlyContinue
        if ($EventGhostProcess) {$null = $EventGhostProcess | Stop-Process -ErrorAction SilentlyContinue}
        $EventGhostConfigFilePath = $(Get-Module AutoWebCreds).ModuleBase + '\' + 'EventGhost' + '\' + 'ConfigurationFiles' + '\' + 'eventghosttreett.xml'
        $null = Start-Process -FilePath "C:\Program Files (x86)\EventGhost\EventGhost.exe" -ArgumentList "-file `"$EventGhostConfigFilePath`""
        Start-Sleep -Seconds 1
        $null = Start-Process -FilePath "C:\Program Files (x86)\EventGhost\EventGhost.exe" -ArgumentList "-event `"MinimizeEventGhost`""
        Start-Sleep -Seconds 1
        $null = Start-Process -FilePath "C:\Program Files (x86)\EventGhost\EventGhost.exe" -ArgumentList "-event `"ClearChromeRestoreMsg`""
        Enter-SeUrl $SiteUrl -Driver $Driver

        # Determine if we see a "Sign In" button. If we do, then we need to login
        $LoginButton = Get-SeElement -By XPath -Selection '//*[@id="sidebar"]/section[1]/button[2]' -Target $Driver
        if (!$LoginButton) {
            throw "Unable to find the SignIn button! Halting!"
        }
    } catch {
        Write-Error $_
        return
    }

    if ($LoginButton) {
        if ([System.Environment]::OSVersion.Version.Build -lt 10240) {
            try {
                # Have the user provide Credentials
                [pscredential]$PSCreds = GetAnyBoxPSCreds -ServiceName $ServiceName
            } catch {
                Write-Error $_
                return
            }
        } else {
            try {
                [pscredential]$PSCreds = UWPCredPrompt -ServiceName $ServiceName -SiteUrl $SiteUrl -Message $Message
            } catch {
                Write-Error $_
                return
            }
        }

        # We need to actually Login
        try {
            Send-SeClick -Element $SignInButton -Driver $Driver
        } catch {
            Write-Error $_
            return
        }

        
        ### Basic UserName and Password Login ####
        if ($LoginType -eq "UserNamePwd") {
            try {
                $null = TidalUserNamePwdLogin -SeleniumDriver $Driver -PSCreds $PSCreds
            } catch {
                Write-Error $_
                return
            }
        }
        

        ### Login With Twitter ###
        if ($LoginType -eq "Twitter") {
            try {
                # Get "Twitter" Button
                $TwitterButton = Get-SeElement -By XPath -Selection "//button[contains(@class, 'btn-client-twitter')]" -Target $Driver
                if (!$TwitterButton) {
                    throw "Cannot find 'Twitter' button! Halting!"
                }
                Send-SeClick -Element $TwitterButton -Driver $Driver
            } catch {
                Write-Error $_
                return
            }

            # Even if the below fails, we might be okay if the Chrome Browser is already signed into a Google Account
            try {
                $null = TwitterAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
            } catch {
                Write-Warning $_.Exception.Message
            }
        }


        ### Login With Facebook ###
        if ($LoginType -eq "Facebook") {
            try {
                # Get "Continue With Facebook" Link
                $ContinueWithFacebookLink = Get-SeElement -By XPath -Selection '//button[contains(@class, 'btn-client-facebook')]' -Target $SeleniumDriver
                if (!$ContinueWithFacebookLink) {
                    throw "Cannot find 'Continue With Facebook' link! Halting!"
                }
                Send-SeClick -Element $ContinueWithFacebookLink -Driver $SeleniumDriver
            } catch {
                Write-Error $_
                return
            }

            try {
                $null = FacebookAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
            } catch {
                Write-Warning $_.Exception.Message
            }
        }


        ### Login with Apple ###
        if ($LoginType -eq "Apple") {
            try {
                # Get "Continue With Apple" Link
                $ContinueWithAppleLink = Get-SeElement -By XPath -Selection '//*[@id="appleid-signin"]' -Target $SeleniumDriver
                if (!$ContinueWithAppleLink) {
                    throw "Cannot find 'Continue With Apple' link! Halting!"
                }
                Send-SeClick -Element $ContinueWithAppleLink -Driver $SeleniumDriver
            } catch {
                Write-Error $_
                return
            }

            try {
                $null = AppleAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
            } catch {
                Write-Warning $_.Exception.Message
            }
        }
        

        # So we need to check the webpage for an indication that we are actually logged in now
        try {
            $SuccessfulLoginIndicator = Get-SeElement -By XPath -Selection "//span[contains(text(),'My Mix')]" -Target $Driver
            if (!$SuccessfulLoginIndicator) {
                throw 'Unable to determine login was successful!'
            }
        } catch {
            Write-Warning $_.Exception.Message
        }

    }

    $Driver

    <#
    $Driver.Close()
    $Driver.Dispose()
    #>
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUKOtAANdvrPuksHb+o5FJndLL
# 9O+gggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBTPp74cZ0O35nWv9c2EdGbjdOW5rzANBgkqhkiG9w0BAQEFAASCAQCxgY/L
# qtvfjyw7+RAhGkj4qKAxXT1XG2386o3lmIeTDew6uIVD4PdPwmA51H2AdavIxogp
# ueE9CSYi+dXh6KC78L984SU3NNtcmvSnMh66+TBiopGAuJ0tc03b/k0IlgxmRsMa
# yhXJfo1qGcZoxbkak33IKWoOAY0LBNF9nKyM3qLl1ruKvhVe3yGvYI06yHfAwV0S
# ZusmRs2eXTcsY1ZGIHcl90Bv5bnlVr/Hlt6Cs3IT2dqu4rb73dTLTYx6mVXeuOIv
# UJC5/YyQZS8OhBZN8SK4BpMbBMN/+RiQekSiD6Q3jR2rPAVt2mpaF1XibliA/h7z
# uBWIRlB8kVQhwCMT
# SIG # End signature block
