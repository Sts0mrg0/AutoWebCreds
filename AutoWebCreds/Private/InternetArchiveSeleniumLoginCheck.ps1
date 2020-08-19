function InternetArchiveSeleniumLoginCheck {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$false)]
        [ValidatePattern('[0-9]')]
        $ChromeProfileNumber = '0'
    )

    $ServiceName = "InternetArchive"
    $SiteUrl = "https://archive.org/details/audio"

    $ChromeUserData = "$HOME\AppData\Local\Google\Chrome\User Data"
    $AvailableProfiles = $(Get-ChildItem -Path $ChromeUserData -Directory -Filter "Profile *").Name
    $ProfileDirName = 'Profile ' + $ChromeProfileNumber
    $ChromeProfile = @($AvailableProfiles) -match $ProfileDirName
    if (!$ChromeProfile) {
        Write-Error "Unable to find Chrome Profile '$ProfileDirName'. Halting!"
        return
    }

    # Make sure we can connect to the Url
    try {
        $HttpClient = [System.Net.Http.HttpClient]::new()
        $HttpClient.Timeout = [timespan]::FromSeconds(10)
        $HttpResponse = $HttpClient.GetAsync($SiteUrl)
        
        $i = 0
        while ($(-not $HttpResponse.IsCompleted) -and $i -lt 10) {
            Start-Sleep -Seconds 1
            $i++
        }

        if ($HttpResponse.Status.ToString() -eq "Canceled") {
            throw "Cannot connect to '$SiteUrl'! Halting!"
        }

    } catch {
        Write-Error $_
        return
    }

    try {
        $null = ChromeDriverAndEventGhostCheck -ErrorAction Stop
    } catch {
        Write-Error $_
    }

    try {
        $Driver = Start-SeChrome -Arguments @("window-size=1200x600", "user-data-dir=$ChromeUserData", "profile-directory=$ChromeProfile")
        # The below Tab + Enter will clear either the "Chrome was not shutdown properly" message or the "Chrome is being controlled by automated software" message
        #[OpenQA.Selenium.Interactions.Actions]::new($Driver).SendKeys([OpenQA.Selenium.Keys]::Tab).Perform()
        #[OpenQA.Selenium.Interactions.Actions]::new($Driver).SendKeys([OpenQA.Selenium.Keys]::Enter).Perform()
        & "C:\Program Files (x86)\EventGhost\EventGhost.exe" -event ClearChromeRestoreMsg

        # For Internet Archive, we cannot get Selenium to identify the Log In button/link, so we should just directly navigate to https://archive.org/account/login
        # If we are redirected to archive.org, then we are already logged in. If not, then we should be able to find the UserName/Email field
        Enter-SeUrl 'https://archive.org/account/login' -Driver $Driver

        # Determine if we see a "Sign In" button. If we do, then we need to login
        $UserNameField = Get-SeElement -By XPath -Selection '//*[@id="maincontent"]/div/div/div[2]/section[2]/form/label[1]/input' -Target $Driver
    } catch {
        Write-Error $_
        return
    }

    if ($UserNameField) {
        # Have the user provide Credentials
        try {
            [pscredential]$PSCreds = GetAnyBoxPSCreds -ServiceName $ServiceName
        } catch {
            Write-Error $_
            return
        }

        ### Basic UserName and Password Login ####
        try {
            $null = InternetArchiveUserNamePwdLogin -SeleniumDriver $Driver -PSCreds $PSCreds
        } catch {
            Write-Error $_
            return
        }

        # So we need to check the webpage for an indication that we are actually logged in now
        try {
            Enter-SeUrl 'https://archive.org/account/login' -Driver $Driver
            $SuccessfulLoginIndicator = $UserNameField = Get-SeElement -By XPath -Selection '//*[@id="maincontent"]/div/div/div[2]/section[2]/form/label[1]/input' -Target $Driver
            if ($SuccessfulLoginIndicator) {
                throw "Did not successfully login with $LoginService! Halting!"
            }
        } catch {
            Write-Error $_
            return
        }
    }

    Enter-SeUrl $SiteUrl -Driver $Driver

    $Driver

    <#
    $Driver.Close()
    $Driver.Dispose()
    #>
}