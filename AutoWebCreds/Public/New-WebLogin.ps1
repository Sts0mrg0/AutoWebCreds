<#
    .SYNOPSIS
        This function uses chromedriver.exe via Selenium to log you into web service specified by the -ServiceName parameter.

    .DESCRIPTION
        See .SYNOPSIS

    .NOTES

    .PARAMETER ServiceName
        This parameter is MANDATORY.

        This parameter takes a string that represents the name of the service that you would like to log into via
        Google Chrome (chromedriver.exe). Currently, supported services are:

        AmazonMusic, Audible, GooglePlay, InternetArchive, NPR, Pandora, ReelGood, Spotify, Tidal, TuneIn, YouTube,
        and YouTubeMusic

    .PARAMETER ChromeProfileNumber
        This parameter is OPTIONAL.

        This parameter is takes an int that represents the Chrome Profile that you would like to use when
        launching Google Chrome via chromedriver.exe. Use the following PowerShell one-liner to list all available
        Chrome Profiles under the current Windows user:
        
        (Get-ChildItem -Path "$HOME\AppData\Local\Google\Chrome\User Data" -Directory -Filter "Profile *").Name

    .EXAMPLE
        # Open an PowerShell session, import the module, and -
        
        PS C:\Users\zeroadmin> New-WebLogin -ServiceName AmazonMusic -ChromeProfileNumber 1
#>
function New-WebLogin {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("AmazonMusic","Audible","GooglePlay","InternetArchive","NPR","Pandora","ReelGood","Spotify","Tidal","TuneIn","YouTube","YouTubeMusic")]
        [string]$ServiceName,

        [parameter(Mandatory=$false)]
        [ValidatePattern('[0-9]')]
        [int]$ChromeProfileNumber = '0'

        #[parameter(Mandatory=$true)]
        #[ValidateSet("UserNamePwd","Google","Amazon","Apple","Facebook","Twitter")]
        #[string]$LoginType
    )
    DynamicParam {
        # Need dynamic parameters for LoginType
        # Set the dynamic parameters' name
        $paramLoginType = 'LoginType'
        # Create the collection of attributes
        $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
        # Create and set the parameters' attributes
        $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
        $ParameterAttribute.Mandatory = $true
        #$ParameterAttribute.Position = 1
        # Add the attributes to the attributes collection
        $AttributeCollection.Add($ParameterAttribute)
        # Create the dictionary 
        $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
        # Generate and set the ValidateSet
        $ParameterValidateSet = switch ($ServiceName) {
            'AmazonMusic'       {@("Amazon")}
            'Audible'           {@("Amazon")}
            'GooglePlay'        {@("Google")}
            'InternetArchive'   {@("UserNamePwd")}
            'NPR'               {@("UserNamePwd","Google","Facebook","Apple")}
            'Pandora'           {@("UserNamePwd")}
            'ReelGood'          {@("UserNamePwd","Google","Facebook")}
            'Spotify'           {@("UserNamePwd","Apple","Facebook")}
            'Tidal'             {@("UserNamePwd","Apple","Facebook","Twitter")}
            'TuneIn'            {@("UserNamePwd","Apple","Facebook","Google")}
            'YouTube'           {@("Google")}
            'YouTubeMusic'      {@("Google")}
        }
        $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($ParameterValidateSet)
        # Add the ValidateSet to the attributes collection
        $AttributeCollection.Add($ValidateSetAttribute) 
        # Create and return the dynamic parameter
        $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($paramLoginType, [string], $AttributeCollection)
        $RuntimeParameterDictionary.Add($paramLoginType, $RuntimeParameter) 
    
        return $RuntimeParameterDictionary
    }

    Begin {
        $LoginType = $PSBoundParameters[$paramLoginType]

        $PSCmdString = $ServiceName + 'SeleniumLoginCheck'
        
        if ($ChromeProfileNumber) {
            $PSCmdString = $PSCmdString + ' ' + '-ChromeProfileNumber' + ' ' + $ChromeProfileNumber
        }

        if ($LoginType) {
            $PSCmdString = $PSCmdString + ' ' + '-LoginType' + ' ' + $LoginType
        }
    }

    Process {
        $global:SuccessfulLogin = $False
        
        try {
            Invoke-Expression -Command $PSCmdString -ErrorAction Stop
        } catch {
            $Msg = "Problem with private function" + $($ServiceName + 'SeleniumLoginCheck') + ': ' + $_.Exception.Message
            Write-Error $Msg
            return
        }
    }
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU7xFASxUWnSB08guT8Egol9LX
# BhigggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBReZMYY+gaO2B2hjn/qroQM/olkFjANBgkqhkiG9w0BAQEFAASCAQAUv42P
# rvqviB5dv+1vImGV/RZxu+eWOGVb3nefv65GP6ndFCsgGXmZdZL1eMHGFnDeyF9C
# NstmnwuBGR2YvD0T5+MAs/Fd7FuMAFM1mPNoVVdchJlZa9Z63xa3pnZ8xmhp3W+S
# KXlNQi9MYsnTIFlW7P1gRRh0kzvD0F03MIpsqg8v0dOiAepOMOnEHYGwkPVfjUoW
# wlAKsUtoP2Ph0eI34Jg9XlqqY6bHy10epp7TLY7s0rph9X42vMcbEGyCqNiCdftl
# Lp1v2RlHaf5w69hWBWKu4kAy0QbfnTnvPO49IYzi6daaaC8gnAownciE3wtfeBhI
# E4zlojjU0egEwBh0
# SIG # End signature block
