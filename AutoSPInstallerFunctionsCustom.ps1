# ===================================================================================
# CUSTOM FUNCTIONS - Put your new or overriding functions here
# ===================================================================================

# ===================================================================================
# Func: CreateWebApp
# Desc: Create the web application
# ===================================================================================
Function CreateWebApp([System.Xml.XmlElement]$webApp)
{
    Get-MajorVersionNumber $xmlinput
    # Look for a managed account that matches the web app type, e.g. "Portal" or "MySiteHost"
    $webAppPoolAccount = Get-SPManagedAccountXML $xmlinput $webApp.Type
    # If no managed account is found matching the web app type, just use the Portal managed account
    if (!$webAppPoolAccount)
    {
        $webAppPoolAccount = Get-SPManagedAccountXML $xmlinput -CommonName "Portal"
        if ([string]::IsNullOrEmpty($webAppPoolAccount.username)) {throw " - `"Portal`" managed account not found! Check your XML."}
    }
    $webAppName = $webApp.name
    $appPool = $webApp.applicationPool
    $dbPrefix = Get-DBPrefix $xmlinput
    $database = $dbPrefix+$webApp.Database.Name
    $dbServer = $webApp.Database.DBServer
    # Check for an existing App Pool
    $existingWebApp = Get-SPWebApplication | Where-Object { ($_.ApplicationPool).Name -eq $appPool }
    $appPoolExists = ($existingWebApp -ne $null)
    # If we haven't specified a DB Server then just use the default used by the Farm
    If ([string]::IsNullOrEmpty($dbServer))
    {
        $dbServer = $xmlinput.Configuration.Farm.Database.DBServer
    }
    $url = ($webApp.url).TrimEnd("/")
    $port = $webApp.port
    $useSSL = $false
    $installedOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\$env:spVer.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
    # Strip out any protocol value
    If ($url -like "https://*") {$useSSL = $true}
    $hostHeader = $url -replace "http://","" -replace "https://",""
    if (((Get-WmiObject Win32_OperatingSystem).Version -like "6.2*" -or (Get-WmiObject Win32_OperatingSystem).Version -like "6.3*") -and ($env:spVer -eq "14"))
    {
        Write-Host -ForegroundColor White " - Skipping setting the web app directory path name (not currently working on Windows 2012 w/SP2010)..."
        $pathSwitch = @{}
    }
    else
    {
        # Set the directory path for the web app to something a bit more friendly
        ImportWebAdministration
        # Get the default root location for web apps (first from IIS itself, then failing that, from the registry)
        $iisWebDir = (Get-ItemProperty "IIS:\Sites\Default Web Site\" -Name physicalPath -ErrorAction SilentlyContinue) -replace ("%SystemDrive%","$env:SystemDrive")
        if ([string]::IsNullOrEmpty($iisWebDir))
        {
            $iisWebDir = (Get-Item -Path HKLM:\SOFTWARE\Microsoft\InetStp).GetValue("PathWWWRoot") -replace ("%SystemDrive%","$env:SystemDrive")
        }
        if (!([string]::IsNullOrEmpty($iisWebDir)))
        {
            $pathSwitch = @{Path = "$iisWebDir\wss\VirtualDirectories\$webAppName-$port"}
        }
        else {$pathSwitch = @{}}
    }
    # Only set $hostHeaderSwitch to blank if the UseHostHeader value exists has explicitly been set to false
    if (!([string]::IsNullOrEmpty($webApp.UseHostHeader)) -and $webApp.UseHostHeader -eq $false)
    {
        $hostHeaderSwitch = @{}
    }
    else {$hostHeaderSwitch = @{HostHeader = $hostHeader}}
    if (!([string]::IsNullOrEmpty($webApp.useClaims)) -and $webApp.useClaims -eq $false)
    {
        # Create the web app using Classic mode authentication
        $authProviderSwitch = @{}
    }
    else # Configure new web app to use Claims-based authentication
    {
        If ($($webApp.useBasicAuthentication) -eq $true)
        {
            $authProvider = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication -UseBasicAuthentication
        }
        Else
        {
            $authProvider = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication
        }
        $authProviderSwitch = @{AuthenticationProvider = $authProvider}
        If ((Gwmi Win32_OperatingSystem).Version -like "6.0*") # If we are running Win2008 (non-R2), we may need the claims hotfix
        {
            [bool]$claimsHotfixRequired = $true
            Write-Host -ForegroundColor Yellow " - Web Applications using Claims authentication require an update"
            Write-Host -ForegroundColor Yellow " - Apply the http://go.microsoft.com/fwlink/?LinkID=184705 update after setup."
        }
    }
    if ($appPoolExists)
    {
        $appPoolAccountSwitch = @{}
    }
    else
    {
        $appPoolAccountSwitch = @{ApplicationPoolAccount = $($webAppPoolAccount.username)}
    }
    $getSPWebApplication = Get-SPWebApplication | Where-Object {$_.DisplayName -eq $webAppName}
    If ($getSPWebApplication -eq $null)
    {
        Write-Host -ForegroundColor White " - Creating Web App `"$webAppName`""
        New-SPWebApplication -Name $webAppName -ApplicationPool $appPool -DatabaseServer $dbServer -DatabaseName $database -Url $url -Port $port -SecureSocketsLayer:$useSSL @hostHeaderSwitch @appPoolAccountSwitch @authProviderSwitch @pathSwitch | Out-Null
        If (-not $?) { Throw " - Failed to create web application" }
    }
    Else {Write-Host -ForegroundColor White " - Web app `"$webAppName`" already provisioned."}
    SetupManagedPaths $webApp
    If ($useSSL)
    {
        $SSLHostHeader = $hostHeader
        $SSLPort = $port
        $SSLSiteName = $webAppName
        if (((Get-WmiObject Win32_OperatingSystem).Version -like "6.2*" -or (Get-WmiObject Win32_OperatingSystem).Version -like "6.3*") -and ($env:spVer -eq "14"))
        {
            Write-Host -ForegroundColor White " - Assigning certificate(s) in a separate PowerShell window..."
            Start-Process -FilePath "$PSHOME\powershell.exe" -Verb RunAs -ArgumentList "-Command `". $env:dp0\AutoSPInstallerFunctions.ps1`; AssignCert $SSLHostHeader $SSLPort $SSLSiteName; Start-Sleep 10`"" -Wait
        }
        else {AssignCert $SSLHostHeader $SSLPort $SSLSiteName}
    }

    # If we are provisioning any Office Web Apps, Visio, Excel, Access or PerformancePoint services, we need to grant the generic app pool account access to the newly-created content database
    # Per http://technet.microsoft.com/en-us/library/ff829837.aspx and http://autospinstaller.codeplex.com/workitem/16224 (thanks oceanfly!)
    If ((ShouldIProvision $xmlinput.Configuration.OfficeWebApps.ExcelService -eq $true) -or `
        (ShouldIProvision $xmlinput.Configuration.OfficeWebApps.PowerPointService -eq $true) -or `
        (ShouldIProvision $xmlinput.Configuration.OfficeWebApps.WordViewingService -eq $true) -or `
        (ShouldIProvision $xmlinput.Configuration.EnterpriseServiceApps.VisioService -eq $true) -or `
        (ShouldIProvision $xmlinput.Configuration.EnterpriseServiceApps.ExcelServices -eq $true) -or `
        (ShouldIProvision $xmlinput.Configuration.EnterpriseServiceApps.AccessService -eq $true) -or `
        (ShouldIProvision $xmlinput.Configuration.EnterpriseServiceApps.AccessServices -eq $true) -or `
        (ShouldIProvision $xmlinput.Configuration.EnterpriseServiceApps.PerformancePointService -eq $true))
    {
        $spservice = Get-SPManagedAccountXML $xmlinput -CommonName "spservice"
        Write-Host -ForegroundColor White " - Granting $($spservice.username) rights to `"$webAppName`"..." -NoNewline
        $wa = Get-SPWebApplication | Where-Object {$_.DisplayName -eq $webAppName}
        $wa.GrantAccessToProcessIdentity("$($spservice.username)")
        Write-Host -ForegroundColor White "OK."
    }
    if ($webApp.GrantCurrentUserFullControl -eq $true)
    {
        $currentUser = "$env:USERDOMAIN\$env:USERNAME"
        $wa = Get-SPWebApplication | Where-Object {$_.DisplayName -eq $webAppName}
        if ($wa.UseClaimsAuthentication -eq $true) {$currentUser = 'i:0#.w|' + $currentUser}
        Set-WebAppUserPolicy $wa $currentUser "$env:USERNAME" "Full Control"
    }
    ## Start Changes Paul Fuller ##
	## Adding Logic for mounting existing ContentDatabases.
	WriteLine
	MountDatabases $webApp
	
	
	## End Changes Paul Fuller ##
	
	WriteLine
    ConfigureObjectCache $webApp

    if ($webApp.SiteCollections) # Only go through these steps if we actually have a site collection to create
    {
        ForEach ($siteCollection in $webApp.SiteCollections.SiteCollection)
        {
            $dbPrefix = Get-DBPrefix $xmlinput
            $getSPSiteCollection = $null
            $siteCollectionName = $siteCollection.Name
            $siteURL = ($siteCollection.siteURL).TrimEnd("/")
			If ($useSSL)
			{
				$siteURL = $siteURL -replace "http://","https://"
			}
            $CompatibilityLevel = $siteCollection.CompatibilityLevel
            if (!([string]::IsNullOrEmpty($CompatibilityLevel))) # Check the Compatibility Level if it's been specified
            {
                $CompatibilityLevelSwitch = @{CompatibilityLevel = $CompatibilityLevel}
            }
            else {$CompatibilityLevelSwitch = @{}}
            if (!([string]::IsNullOrEmpty($($siteCollection.CustomDatabase)))) # Check if we have specified a non-default content database for this site collection
            {
                $siteDatabase = $dbPrefix+$siteCollection.CustomDatabase
            }
            else # Just use the first, default content database for the web application
            {
                $siteDatabase = $database
            }
            # If an OwnerAlias has been specified, make it the primary, and the currently logged-in account the secondary. Otherwise, make the app pool account for the web app the primary owner
            if (!([string]::IsNullOrEmpty($($siteCollection.Owner))))
            {
                $ownerAlias = $siteCollection.Owner
            }
            else
            {
                $ownerAlias = $webAppPoolAccount.username
            }
            $LCID = $siteCollection.LCID
            $siteCollectionLocale = $siteCollection.Locale
            $siteCollectionTime24 = $siteCollection.Time24
            # If a template has been pre-specified, use it when creating the Portal site collection; otherwise, leave it blank so we can select one when the portal first loads
            $template = $siteCollection.template
            If (($template -ne $null) -and ($template -ne ""))
            {
                $templateSwitch = @{Template = $template}
            }
            else {$templateSwitch = @{}}
            if ($siteCollection.HostNamedSiteCollection -eq $true)
            {
                $hostHeaderWebAppSwitch = @{HostHeaderWebApplication = $(($webApp.url).TrimEnd("/"))+":"+$($webApp.port)}
            }
            else {$hostHeaderWebAppSwitch = @{}}
            Write-Host -ForegroundColor White " - Checking for Site Collection `"$siteURL`"..."
            $getSPSiteCollection = Get-SPSite -Identity $siteURL -ErrorAction SilentlyContinue
            If (($getSPSiteCollection -eq $null) -and ($siteURL -ne $null))
            {
                # Verify that the Language we're trying to create the site in is currently installed on the server
                $culture = [System.Globalization.CultureInfo]::GetCultureInfo(([convert]::ToInt32($LCID)))
                $cultureDisplayName = $culture.DisplayName
                If (!($installedOfficeServerLanguages | Where-Object {$_ -eq $culture.Name}))
                {
                    Write-Warning "You must install the `"$culture ($cultureDisplayName)`" Language Pack before you can create a site using LCID $LCID"
                }
                Else
                {
                    $siteDatabaseExists = Get-SPContentDatabase -Identity $siteDatabase -ErrorAction SilentlyContinue
                    if (!$siteDatabaseExists)
                    {
                        Write-Host -ForegroundColor White " - Creating new content database `"$siteDatabase`"..."
                        New-SPContentDatabase -Name $siteDatabase -WebApplication (Get-SPWebApplication $webApp.url) | Out-Null
                    }
                    Write-Host -ForegroundColor White " - Creating Site Collection `"$siteURL`"..."
                    $site = New-SPSite -Url $siteURL -OwnerAlias $ownerAlias -SecondaryOwner $env:USERDOMAIN\$env:USERNAME -ContentDatabase $siteDatabase -Description $siteCollectionName -Name $siteCollectionName -Language $LCID @templateSwitch @hostHeaderWebAppSwitch @CompatibilityLevelSwitch -ErrorAction Stop

                    # JDM Not all Web Templates greate the default SharePoint Croups that are made by the UI
                    # JDM These lines will insure that the the approproprate SharePoint Groups, Owners, Members, Visitors are created
                    $primaryUser = $site.RootWeb.EnsureUser($ownerAlias)
                    $secondaryUser = $site.RootWeb.EnsureUser("$env:USERDOMAIN\$env:USERNAME")
                    $title = $site.RootWeb.title
                    Write-Host -ForegroundColor White " - Ensuring default groups are created..."
                    $site.RootWeb.CreateDefaultAssociatedGroups($primaryUser, $secondaryUser, $title)

                    # Add the Portal Site Connection to the web app, unless of course the current web app *is* the portal
                    # Inspired by http://www.toddklindt.com/blog/Lists/Posts/Post.aspx?ID=264
                    $portalWebApp = $xmlinput.Configuration.WebApplications.WebApplication | Where {$_.Type -eq "Portal"} | Select-Object -First 1
                    $portalSiteColl = $portalWebApp.SiteCollections.SiteCollection | Select-Object -First 1
                    If ($site.URL -ne $portalSiteColl.siteURL)
                    {
                        Write-Host -ForegroundColor White " - Setting the Portal Site Connection for `"$siteCollectionName`"..."
                        $site.PortalName = $portalSiteColl.Name
                        $site.PortalUrl = $portalSiteColl.siteUrl
                    }
                    If ($siteCollectionLocale)
                    {
                        Write-Host -ForegroundColor White " - Updating the locale for `"$siteCollectionName`" to `"$siteCollectionLocale`"..."
                        $site.RootWeb.Locale = [System.Globalization.CultureInfo]::CreateSpecificCulture($siteCollectionLocale)
                    }
                    If ($siteCollectionTime24)
                    {
                        Write-Host -ForegroundColor White " - Updating 24 hour time format for `"$siteCollectionName`" to `"$siteCollectionTime24`"..."
                        $site.RootWeb.RegionalSettings.Time24 = $([System.Convert]::ToBoolean($siteCollectionTime24))
                    }
                    $site.RootWeb.Update()
                }
            }
            Else {Write-Host -ForegroundColor White " - Skipping creation of site `"$siteCollectionName`" - already provisioned."}
            if ($siteCollection.HostNamedSiteCollection -eq $true)
            {
                Add-LocalIntranetURL ($siteURL)
                # Updated so that we don't add URLs to the local hosts file of a server that's not been specified to run the Foundation Web Application service, or the Search MinRole
                if ($xmlinput.Configuration.WebApplications.AddURLsToHOSTS -eq $true -and !(ShouldIProvision ($xmlinput.Configuration.Farm.ServerRoles.Search)) -and !(($xmlinput.Configuration.Farm.Services.SelectSingleNode("FoundationWebApplication")) -and !(ShouldIProvision $xmlinput.Configuration.Farm.Services.FoundationWebApplication -eq $true)))
                {
                    # Add the hostname of this host header-based site collection to the local HOSTS so it's immediately resolvable locally
                    # Strip out any protocol and/or port values
                    $hostname,$null = $siteURL -replace "http://","" -replace "https://","" -split ":"
                    AddToHOSTS $hostname
                }
            }
            WriteLine
        }
    }
    else
    {
        Write-Host -ForegroundColor Yellow " - No site collections specified for $($webapp.url) - skipping."
    }
}
# ===================================================================================
# Func: MountDatabases
# Desc: Mount Existing Databases 
# ===================================================================================
#<ExistingContentDatabases>
#				<UpgradetoCliaims>true</UpgradetoCliaims>
#				<UpgradeSiteCollections>true</UpgradeSiteCollections>
#				<ContentDatabase>
#					<DBName>WSS_Content_Root</DBName>
#					<DBState>Disabled</DBState>
#				</ContentDatabase>
#</ExistingContentDatabases>
Function MountDatabases([System.Xml.XmlElement]$webApp) 
{
	If ($webApp.ExistingContentDatabases)
	{
		Write-Host -ForegroundColor White "--------------------------------------------------------------"
		Write-Host -ForegroundColor White " - Start Mounting Databases in $($webApp.name)"
		ForEach ($ContentDatabase in $webApp.ExistingContentDatabases.ContentDatabase)
		{
			If (!(Get-SPContentDatabase -Identity $ContentDatabase.DBName))
			{
				#Test mounting Content Database
				Test-SPContentDatabase -Name $ContentDatabase.DBName -WebApplication $webApp.name
				#Mount Content Database
				Mount-SPContentDatabase -Name $ContentDatabase.DBName -WebApplication $webApp.name
				Write-Host -ForegroundColor Green "   - Done Mounting Databases: $($ContentDatabase.DBName)"
				If ($ContentDatabase.DBState -eq "Disabled") 
				{
					Set-SPContentDatabase -Identity $ContentDatabase.DBName -Status $ContentDatabase.DBState
				}
			}
		}
		Write-Host -ForegroundColor White " - Done Mounting Databases in $($webApp.name)"
		
		If ((Get-Website -Name "SharePoint Web Services").state -ne "Started"){Start-Website -Name "SharePoint Web Services"} #Start SharePoint Web Services if stopped
		#Upgrade Legacy Authentication to Claims 
		If ($webApp.ExistingContentDatabases.UpgradetoCliaims -eq "true")
		{
			# Check for Legacy Authentication
			If ((Get-SPWebApplication $webApp.name).UseClaimsAuthentication -ne "true" )
			{
				Write-Host -ForegroundColor White " - Start Converting to Claims Authentication for $($webApp.name)"
				Convert-SPWebApplication -Identity ($webApp.name) -From Legacy -To Claims -RetainPermissions  -Force
				Write-Host -ForegroundColor White " - Done Converting to Claims Authentication for $($webApp.name)"
			}
		}
		#Upgrade Site Collections
		If ($webApp.ExistingContentDatabases.UpgradeSiteCollections -eq "true")
		{
			
			#Test to see if their are site to upgrade
			If ((Get-SPWebApplication $webApp.name).sites | Where-Object {$_.CompatibilityLevel -lt ($env:spVer)})
			{
				Write-Host -ForegroundColor White " - Start upgrading site collections for $($webApp.name)"
				(Get-SPWebApplication $webApp.name).sites| Where-Object {$_.CompatibilityLevel -lt ($env:spVer)} | Upgrade-SPSite -VersionUpgrade
				Write-Host -ForegroundColor White " - Done upgrading site collections for $($webApp.name)"
			}
		}
		If ((Get-Website -Name "SharePoint Web Services").state -ne "Started"){Start-Website -Name "SharePoint Web Services"} #Start SharePoint Web Services if stopped
		Write-Host -ForegroundColor White "--------------------------------------------------------------"
	}
}