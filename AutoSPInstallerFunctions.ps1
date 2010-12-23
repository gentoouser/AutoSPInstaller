# ===================================================================================
# EXTERNAL FUNCTIONS
# ===================================================================================

#Region Start logging to user's desktop
Function StartTracing
{
    $script:LogTime = Get-Date -Format yyyy-MM-dd_h-mm
    $script:LogFile = "$env:USERPROFILE\Desktop\AutoSPInstaller-$LogTime.rtf"
    Start-Transcript -Path $LogFile -Force
    
    $script:StartDate = Get-Date
    Write-Host -ForegroundColor White "-----------------------------------"
    Write-Host -ForegroundColor White "| Automated SP2010 install script |"
    Write-Host -ForegroundColor White "| Started on: $StartDate |"
    Write-Host -ForegroundColor White "-----------------------------------"
}
#EndRegion

#Region Check Configuration File 
Function CheckConfig
{
    # Check that the config file exists.
    if (-not $(Test-Path -Path $InputFile -Type Leaf))
    {
    	Write-Error -message ("Configuration file '" + $InputFile + "' does not exist.")
    }
}
#EndRegion

#Region Check Operating System
Function CheckOS
{
	$QueryOS = Gwmi Win32_OperatingSystem
	$QueryOS = $QueryOS.Version 
	If ($QueryOS.contains("6.1")) {$script:OS = "Win2008R2"}
	ElseIf ($QueryOS.contains("6.0")) {$script:OS = "Win2008"}
	Write-Host -ForegroundColor White "- Running on $OS."
}
#EndRegion

#Region Check Installation Account
# ===================================================================================
# Func: CheckInstallAccount
# Desc: Check the install account and 
# ===================================================================================
Function CheckInstallAccount([xml]$xmlinput)
{
    ## Check if we are running under Farm Account credentials
    If ($env:USERDOMAIN+"\"+$env:USERNAME -eq $FarmAcct) 
    {
        Write-Host  -ForegroundColor Yellow "WARNING: Running install using Farm Account: $FarmAcct"
    }
}
#EndRegion

#Region Disable Loopback Check and Services
# ===================================================================================
# Func: DisableLoopbackCheck
# Desc: Disable Loopback Check
# ===================================================================================
Function DisableLoopbackCheck([xml]$xmlinput)
{
    ## Disable the Loopback Check on stand alone demo servers.  
    ## This setting usually kicks out a 401 error when you try to navigate to sites that resolve to a loopback address e.g.  127.0.0.1 
    if ($xmlinput.Configuration.Install.Disable.Loopback -eq "1")
    {
    	Write-Host -ForegroundColor White " --------------------------------------------------------------"
        Write-Host -ForegroundColor White " - Disabling Loopback Check"

        $LsaPath = "HKLM:\System\CurrentControlSet\Control\Lsa"
        $LsaPathValue = Get-ItemProperty -path $LsaPath
        If (-not ($LsaPathValue.DisableLoopbackCheck -eq "1"))
        {
            New-ItemProperty HKLM:\System\CurrentControlSet\Control\Lsa -Name "DisableLoopbackCheck" -value "1" -PropertyType dword -Force | Out-Null
        }
    	Write-Host -ForegroundColor White " --------------------------------------------------------------"    
    }
}

# ===================================================================================
# Func: DisableServices
# Desc: Disable Unused Services or set status to Manual
# ===================================================================================
Function DisableServices([xml]$xmlinput)
{        
    if ($xmlinput.Configuration.Install.Disable.UnusedServices -eq "1")
    {
    	Write-Host -ForegroundColor White " --------------------------------------------------------------"
        Write-Host -ForegroundColor White " - Setting unused services Spooler, AudioSrv and TabletInputService to Manual..."

        $ServicesToSetManual = "Spooler","AudioSrv","TabletInputService"
        ForEach ($SvcName in $ServicesToSetManual)
        {
            $Svc = get-wmiobject win32_service | where-object {$_.Name -eq $SvcName} 
            $SvcStartMode = $Svc.StartMode
            $SvcState = $Svc.State
            If (($SvcState -eq "Running") -and ($SvcStartMode -eq "Auto"))
            {
                Stop-Service -Name $SvcName
                Set-Service -name $SvcName -startupType Manual
                Write-Host -ForegroundColor White " - Service $SvcName is now set to Manual start"
            }
            Else 
            {
                Write-Host -ForegroundColor White " - $SvcName is already stopped and set Manual, no action required."
            }
        }
    	
        Write-Host -ForegroundColor White " --------------------------------------------------------------"
        Write-Host -ForegroundColor White " - Setting unused services WerSvc to Disabled..."
        $ServicesToDisable = "WerSvc"
        ForEach ($SvcName in $ServicesToDisable) 
        {
            $Svc = get-wmiobject win32_service | where-object {$_.Name -eq $SvcName} 
            $SvcStartMode = $Svc.StartMode
            $SvcState = $Svc.State
            If (($SvcState -eq "Running") -and (($SvcStartMode -eq "Auto") -or ($SvcStartMode -eq "Manual")))
            {
                Stop-Service -Name $SvcName
                Set-Service -name $SvcName -startupType Disabled
                Write-Host -ForegroundColor White " - Service $SvcName is now stopped and disabled."
            }
            Else 
            {
                Write-Host -ForegroundColor White " - $SvcName is already stopped and disabled, no action required."
            }
        }
        Write-Host -ForegroundColor White " - Finished disabling services."
        Write-Host -ForegroundColor White " --------------------------------------------------------------"
    }
    
}
#EndRegion

#Region Install Prerequisites
# ===================================================================================
# Func: Install Prerequisites
# Desc: If SharePoint is not already installed install the Prerequisites
# ===================================================================================
Function InstallPrerequisites([xml]$xmlinput)
{
    If (Test-Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\BIN\stsadm.exe") #Crude way of checking if SP2010 is already installed
    {
    	Write-Host -ForegroundColor White " - SP2010 prerequisites appear be already installed - skipping installation."
    }
    Else
    {
    	Write-Host -ForegroundColor White " - Installing Prerequisite Software:"
    	Write-Host -ForegroundColor White " - Running Prerequisite Installer..."

    	Try 
    	{
			If ($xmlinput.Configuration.Install.OfflineInstall -eq "1") ## Install all prerequisites from local folder
    		{
    			Start-Process "$bits\PrerequisiteInstaller.exe" -Wait -ArgumentList "/unattended `
    																				/SQLNCli:`"$bits\PrerequisiteInstallerFiles\sqlncli.msi`" `
    																				/ChartControl:`"$bits\PrerequisiteInstallerFiles\MSChart.exe`" `
    																				/NETFX35SP1:`"$bits\PrerequisiteInstallerFiles\dotnetfx35.exe`" `
    																				/PowerShell:`"$bits\PrerequisiteInstallerFiles\Windows6.0-KB968930-x64.msu`" `
    																				/KB976394:`"$bits\PrerequisiteInstallerFiles\Windows6.0-KB976394-x64.msu`" `
    																				/KB976462:`"$bits\PrerequisiteInstallerFiles\Windows6.1-KB976462-v2-x64.msu`" `
    																				/IDFX:`"$bits\PrerequisiteInstallerFiles\Windows6.0-KB974405-x64.msu`" `
    																				/IDFXR2:`"$bits\PrerequisiteInstallerFiles\Windows6.1-KB974405-x64.msu`" `
    																				/Sync:`"$bits\PrerequisiteInstallerFiles\Synchronization.msi`" `
    																				/FilterPack:`"$bits\PrerequisiteInstallerFiles\FilterPack\FilterPack.msi`" `
    																				/ADOMD:`"$bits\PrerequisiteInstallerFiles\SQLSERVER2008_ASADOMD10.msi`" `
    																				/ReportingServices:`"$bits\PrerequisiteInstallerFiles\rsSharePoint.msi`" `
    																				/Speech:`"$bits\PrerequisiteInstallerFiles\SpeechPlatformRuntime.msi`" `
    																				/SpeechLPK:`"$bits\PrerequisiteInstallerFiles\MSSpeech_SR_en-US_TELE.msi`""																		
    			If (-not $?) {throw}
    		}
    		Else ## Regular prerequisite install - download required files
    		{
    			Start-Process "$bits\PrerequisiteInstaller.exe" -Wait -ArgumentList "/unattended" -WindowStyle Minimized
    			If (-not $?) {throw}
    		}
    	}
    	Catch 
    	{
    		Write-Host -ForegroundColor Red "- Error: $LastExitCode"
    		If ($LastExitCode -eq "1") {throw "- Another instance of this application is already running"}
    		ElseIf ($LastExitCode -eq "2") {throw "- Invalid command line parameter(s)"}
    		ElseIf ($LastExitCode -eq "1001") {throw "- A pending restart blocks installation"}
    		ElseIf ($LastExitCode -eq "3010") {throw "- A restart is needed"}
    		Else {throw "- An unknown error occurred installing prerequisites"}
    	}
    	## Parsing most recent PreRequisiteInstaller log for errors or restart requirements, since $LastExitCode doesn't seem to work...
    	$PreReqLog = get-childitem $env:TEMP | ? {$_.Name -like "PrerequisiteInstaller.*"} | Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
    	If ($PreReqLog -eq $null) 
    	{
    		Write-Warning " - Could not find PrerequisiteInstaller log file"
    	}
    	Else 
    	{
    		## Get error(s) from log
    		$PreReqLastError = $PreReqLog | select-string -SimpleMatch -Pattern "Error" -Encoding Unicode | ? {$_.Line  -notlike "*Startup task*"}
    		If ($PreReqLastError)
    		{
    			Write-Warning $PreReqLastError.Line
    			$PreReqLastReturncode = $PreReqLog | select-string -SimpleMatch -Pattern "Last return code" -Encoding Unicode | Select-Object -Last 1
    			If ($PreReqLastReturnCode) {Write-Warning $PreReqLastReturncode.Line}
    			Write-Host -ForegroundColor White " - Review the log file and try to correct any error conditions."
    			Pause
    			Invoke-Item $env:TEMP\$PreReqLog
    			break
    		}
    		## Look for restart requirement in log
    		$PreReqRestartNeeded = $PreReqLog | select-string -SimpleMatch -Pattern "0XBC2=3010" -Encoding Unicode
    		If ($PreReqRestartNeeded)
    		{
    			Write-Warning " - One or more of the prerequisites requires a restart."
    			Write-Host -ForegroundColor White " - Run the script again after restarting to continue."
    			Pause
    			break
    		}
    	}
        
    	Write-Host -ForegroundColor White "- All Prerequisite Software installed successfully."	
    }
}
#EndRegion

#Region Install SharePoint
# ===================================================================================
# Func: Install SharePoint
# Desc: If SharePoint is not already installed install SharePoint
# ===================================================================================
Function InstallSharePoint([xml]$xmlinput)
{
    If  (Test-Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\BIN\stsadm.exe") #Crude way of checking if SP2010 is already installed
    {
    	Write-Host -ForegroundColor White " - SP2010 binaries to be appear be already installed - skipping installation."
    }
    Else
    {
    	## Install SharePoint Binaries
        $config = $dp0 + "\" + $xmlinput.Configuration.Install.ConfigFile
    	If (Test-Path "$bits\setup.exe")
    	{
    		Write-Host -ForegroundColor White "- Installing SharePoint binaries..."
      		try
    		{
    			Start-Process "$bits\setup.exe" -ArgumentList "/config `"$config`"" -WindowStyle Minimized -Wait
    			If (-not $?) {throw}
    		}
    		catch 
    		{
    			Write-Warning "- Error $LastExitCode occurred running $bits\setup.exe"
    			break
    		}
    		
    		## Parsing most recent SharePoint Server Setup log for errors or restart requirements, since $LastExitCode doesn't seem to work...
    		$SetupLog = get-childitem $env:TEMP | ? {$_.Name -like "SharePoint Server Setup*"} | Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
    		If ($SetupLog -eq $null) 
    		{
    			Write-Warning " - Could not find SharePoint Server Setup log file!"
    			Pause
    			break
    		}
    		Else 
    		{
    			## Get error(s) from log
    			$SetupLastError = $SetupLog | select-string -SimpleMatch -Pattern "Error:" | Select-Object -Last 1 #| ? {$_.Line  -notlike "*Startup task*"}
    			If ($SetupLastError)
    			{
    				Write-Warning $SetupLastError.Line
    				Write-Host -ForegroundColor White " - Review the log file and try to correct any error conditions."
    				Pause
    				Invoke-Item $env:TEMP\$SetupLog
    				break
    			}
    			## Look for restart requirement in log
    			$SetupRestartNotNeeded = $SetupLog | select-string -SimpleMatch -Pattern "System reboot is not pending."
    			If (!($SetupRestartNotNeeded))
    			{
    				Write-Host -ForegroundColor White " - SharePoint setup requires a restart."
    				Write-Host -ForegroundColor White " - Run the script again after restarting to continue."
    				Pause
    				break
    			}
    		}
    		Write-Host -ForegroundColor Blue "- Waiting for SharePoint Products and Technologies Wizard to launch..." -NoNewline
    		While ((Get-Process |?{$_.ProcessName -like "psconfigui*"}) -eq $null)
    		{
    			Write-Host -ForegroundColor Blue "." -NoNewline
    			sleep 1
    		}
    		Write-Host -ForegroundColor Blue "Done."
      		Write-Host -ForegroundColor White "- Exiting Products and Technologies Wizard - using Powershell instead!"
    		Stop-Process -Name psconfigui
    	}
    	Else
    	{
    	  	Write-Host -ForegroundColor Red "- Install path $bits Not found!!"
    	  	Pause
    		break
    	}
    }
}
#EndRegion

#Region Install Language Packs
# ===================================================================================
# Func: Install Language Packs
# Desc: Install language packs and report on any languages installed
# ===================================================================================
Function InstallLanguagePacks([xml]$xmlinput)
{
    #[string]$config = Get-Location 
    #$bits = Get-Location | Split-Path -Parent          

    ## Look for Server language packs
    $ServerLanguagePacks = (Get-ChildItem "$bits\LanguagePacks" -Name -Include ServerLanguagePack*.exe -ErrorAction SilentlyContinue)
    If ($ServerLanguagePacks)
    {
    	Write-Host -ForegroundColor White "- Installing SharePoint (Server) Language Packs:"
    	## Get installed languages from registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Office Server\14.0\InstalledLanguages)
        $InstalledOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\14.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
    <#
    	## Another way to get installed languages, thanks to Anders Rask (@AndersRask)!
    	##$InstalledOfficeServerLanguages = [Microsoft.SharePoint.SPRegionalSettings]::GlobalInstalledLanguages
    #>
    	ForEach ($LanguagePack in $ServerLanguagePacks)
    	{
            ## Slightly convoluted check to see if language pack is already installed, based on name of language pack file.
            ## This only works if you've renamed your language pack(s) to follow the convention "ServerLanguagePack_XX-XX.exe" where <XX-XX> is a culture such as <en-us>.
    		$Language = $InstalledOfficeServerLanguages | ? {$_ -eq (($LanguagePack -replace "ServerLanguagePack_","") -replace ".exe","")}
            If (!$Language)
            {
    	        Write-Host -ForegroundColor Blue " - Installing $LanguagePack..." -NoNewline
    	        Start-Process -FilePath "$bits\LanguagePacks\$LanguagePack" -ArgumentList "/quiet /norestart"
    	        While (Get-Process -Name ($LanguagePack -replace ".exe", "") -ErrorAction SilentlyContinue)
    	        {
    	        	Write-Host -ForegroundColor Blue "." -NoNewline
    	        	sleep 5
    	        }
       		    Write-Host -BackgroundColor Blue -ForegroundColor Black "Done."
            }
            Else
            {
                Write-Host -ForegroundColor White " - Language $Language already appears to be installed, skipping."
            }
    	}
    	Write-Host -ForegroundColor White " - Language Pack installation complete."
    }
    Else 
    {
        Write-Host -ForegroundColor White " - No language packs found in $bits\LanguagePacks, skipping."
    }

    ## Document installed languages
    $InstalledOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\14.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
    Write-Host -ForegroundColor White " - Currently installed languages:" 
    ForEach ($Language in $InstalledOfficeServerLanguages)
    {
    	Write-Host "  -" ([System.Globalization.CultureInfo]::GetCultureInfo($Language).DisplayName)
    }
}
#EndRegion

#Region Configure Farm Account
# ===================================================================================
# Func: ConfigureFarmAdmin
# Desc: Sets up the farm account and adds to Local admins if needed
# ===================================================================================
Function ConfigureFarmAdmin([xml]$xmlinput)
{        
    if ($xmlinput.Configuration.Farm.Account.getAttribute("AddToLocalAdminsDuringSetup") -eq "1")
    {
        #Add to Admins Group
        $FarmAcct = $xmlinput.Configuration.Farm.Account.Username
        Write-Host -ForegroundColor White " - Adding $FarmAcct to local Administrators for the duration of setup..."
        $FarmAcctDomain,$FarmAcctUser = $FarmAcct -Split "\\"
        try
    	{
    		([ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group").Add("WinNT://$FarmAcctDomain/$FarmAcctUser")
            If (-not $?) {throw}
    	}
        catch 
        {
            Write-Host -ForegroundColor White " - $FarmAcct is already an Administrator, continuing."
        }
    }
}

# ===================================================================================
# Func: GetFarmCredentials
# Desc: Return the credentials for the farm account, prompt the user if need more info
# ===================================================================================
Function GetFarmCredentials([xml]$xmlinput)
{        
    $farmAcc = $xmlinput.Configuration.Farm.Account.getAttribute("Username")
    $farmAccPassword = $xmlinput.Configuration.Farm.Account.getAttribute("Password")
    If (!($farmAcc) -or $farmAcc -eq "" -or !($farmAccPassword) -or $farmAccPassword -eq "") 
    {
        Write-Host -BackgroundColor Gray -ForegroundColor DarkBlue "- Prompting for Farm Account:"
    	$farmCredential = $host.ui.PromptForCredential("Farm Setup", "Enter Farm Account Credentials:", "$FarmAcct", "NetBiosUserName" )
    } 
    else
    {
        $secPassword = ConvertTo-SecureString "$farmAccPassword" –AsPlaintext –Force 
        $script:farmCredential = New-Object System.Management.Automation.PsCredential $farmAcc,$secPassword
    }
    return $farmCredential
}
#EndRegion

#Region Get Secure Farm Passphrase
# ===================================================================================
# Func: GetFarmPhrase
# Desc: Return the Farm Phrase as a secure string
# ===================================================================================
Function GetFarmPassphrase([xml]$xmlinput)
{        
    $script:FarmPassphrase = $xmlinput.Configuration.Farm.Passphrase

    If (!($FarmPassphrase) -or $FarmPassphrase -eq "")
    {
    	$FarmPassphrase = Read-Host -Prompt " - Please enter the farm passphrase now" -AsSecureString
    	If (!($FarmPassphrase) -or $FarmPassphrase -eq "") {Write-Warning " - Farm passphrase is required!" ; Pause; break}
    	Else {$SecPhrase = "$FarmPassphrase"} ## Quotes around $FarmPassphrase in case it has spaces or special characters
    }
    Else
    {
    	$SecPhrase = ConvertTo-SecureString "$FarmPassphrase" –AsPlaintext –Force
    }
	return $SecPhrase
}
#EndRegion

#Region Create or Join Farm
# ===================================================================================
# Func: CreateOrJoinFarm
# Desc: Check if the farm is created 
# ===================================================================================
Function CreateOrJoinFarm([xml]$xmlinput, $SecPhrase, $farmCredential)
{
    #Region Create/Join Farm
    Start-SPAssignment -Global | Out-Null

    $DBPrefix = $xmlinput.Configuration.Farm.Database.DBPrefix
	If (($DBPrefix -ne "") -and ($DBPrefix -ne $null)) {$DBPrefix = $DBPrefix+"_"}
	If ($DBPrefix -like "*localhost*") {$DBPrefix = $DBPrefix -replace "localhost","$env:COMPUTERNAME"}
    $configDB = $DBPrefix+$xmlinput.Configuration.Farm.Database.ConfigDB
    
    ## Look for an existing farm and join the farm if not already joined, or create a new farm
    try
    {
    	Write-Host -ForegroundColor White " - Checking farm membership for $env:COMPUTERNAME in `"$configDB`"..."
    	$SPFarm = Get-SPFarm | Where-Object {$_.Name -eq $configDB} -ErrorAction SilentlyContinue
    }
    catch {""}
    If ($SPFarm -eq $null)
    {
    	try
    	{
            #$DBServer = Get-DBServer $xmlinput
            $CentralAdminContentDB = $DBPrefix+$xmlinput.Configuration.Farm.CentralAdmin.CentralAdminContentDB
            
    		Write-Host -ForegroundColor White " - Attempting to join farm on `"$ConfigDB`"..."
    		$connectFarm = Connect-SPConfigurationDatabase -DatabaseName "$configDB" -Passphrase $SecPhrase -DatabaseServer "$DBServer" -ErrorAction SilentlyContinue
    		If (-not $?)
    		{
    			Write-Host -ForegroundColor White " - No existing farm found.`n - Creating config database `"$configDB`"..."
    			## Waiting a few seconds seems to help with the Connect-SPConfigurationDatabase barging in on the New-SPConfigurationDatabase command; not sure why...
    			sleep 5
    			New-SPConfigurationDatabase –DatabaseName "$configDB" –DatabaseServer "$DBServer" –AdministrationContentDatabaseName "$CentralAdminContentDB" –Passphrase $SecPhrase –FarmCredentials $farmCredential
    			If (-not $?) {throw}
    			Else {$FarmMessage = " - Done creating configuration database for farm."}
    		}
    		Else 
            {
                $FarmMessage = " - Done joining farm."
            }
    	}
    	catch 
    	{
    		Write-Output $_
    		Pause
    		break
    	}
    }
    Else 
    {
        $FarmMessage = "- $env:COMPUTERNAME is already joined to farm on `"$configDB`"."
    }
    
    Write-Host -ForegroundColor White $FarmMessage
}
#EndRegion

#Region Configure Farm
# ===================================================================================
# Func: ConfigureFarm
# Desc: Setup Central Admin Web Site, Check the topology of an existing farm, and configure the farm as required.
# ===================================================================================

Function CreateCentralAdmin([xml]$xmlinput)
{
	try
	{
		## Create Central Admin
		$CentralAdminPort =  $xmlinput.Configuration.Farm.CentralAdmin.CentralAdminPort
		Write-Host -ForegroundColor White " - Creating Central Admin site..."
		$NewCentralAdmin = New-SPCentralAdministration -Port $CentralAdminPort -WindowsAuthProvider "NTLM" -ErrorVariable err
		If (-not $?) {throw}
		Write-Host -ForegroundColor Blue " - Waiting for Central Admin site to provision..." -NoNewline
		$CentralAdmin = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Url -like "http://$($env:COMPUTERNAME):$CentralAdminPort*"}
		While ($CentralAdmin.Status -ne "Online") 
		{
			Write-Host -ForegroundColor Blue "." -NoNewline
			sleep 1
			$CentralAdmin = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Url -like "http://$($env:COMPUTERNAME):$CentralAdminPort*"}
		}
		Write-Host -BackgroundColor Blue -ForegroundColor Black "Done!"
	}
	catch	
	{
   		If ($err -like "*update conflict*")
		{
			Write-Warning " - A concurrency error occured, trying again."
			CreateCentralAdmin
		}
		Else 
		{
			Write-Output $_
			Pause
			break
		}
	}
}

Function CheckFarmTopology
{
	## Check if there is already more than one server in the farm (not including the database server)
	$SPFarm = Get-SPFarm | Where-Object {$_.Name -eq $ConfigDB}
	ForEach ($Srv in $SPFarm.Servers) {If (($Srv -like "*$DBServer*") -and ($DBServer -ne $env:COMPUTERNAME)) {[bool]$DBLocal = $false}}
	If (($($SPFarm.Servers.Count) -gt 1) -and ($DBLocal -eq $false)) {[bool]$FirstServer = $false}
	Else {[bool]$FirstServer = $true}
}

Function ConfigureFarm([xml]$xmlinput)
{
	Write-Host -ForegroundColor White "- Configuring the SharePoint farm/server..."
	## Force a full configuration if this is the first web/app server in the farm
	If ((!($FarmExists)) -or ($FirstServer -eq $true)) {[bool]$DoFullConfig = $true}
	try
	{
		If ($DoFullConfig)
		{
			## Install Help Files
			$SPHelpTimer = Get-SPTimerJob | ? {$_.TypeName -eq "Microsoft.SharePoint.Help.HelpCollectionInstallerJob"} | Select-Object -Last 1
			#If (!($SPHelpTimer.Status -eq "Online")) ## Install help collection if there isn't already a timer job created & running
			#{
				Write-Host -ForegroundColor White " - Installing Help Collection..."
				Install-SPHelpCollection -All
			#}
			## Wait for the SP Help Collection timer job to complete
			<#Write-Host -ForegroundColor Blue " - Waiting for Help Collection Installation timer job to complete..." -NoNewline
			While ($SPHelpTimer.Status -eq "Online")
			{
				Write-Host -ForegroundColor Blue "." -NoNewline
		  		Start-Sleep 1
		  		$SPHelpTimer = Get-SPTimerJob | ? {$_.TypeName -eq "Microsoft.SharePoint.Help.HelpCollectionInstallerJob"} | Select-Object -Last 1
			}
	    	Write-Host -BackgroundColor Blue -ForegroundColor Black "Done."
			#>
		}
		## Secure resources
		Write-Host -ForegroundColor White " - Securing Resources..."
		Initialize-SPResourceSecurity
		## Install Services
		Write-Host -ForegroundColor White " - Installing Services..."
		Install-SPService
		If ($DoFullConfig)
		{
			## Install (all) features
			Write-Host -ForegroundColor White " - Installing Features..."
			$Features = Install-SPFeature –AllExistingFeatures -Force
		}
		##Detect if Central Admin URL already exists, i.e. if Central Admin web app is already provisioned on the local computer
		$CentralAdmin = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Status -eq "Online"} | ? {$_.Url -like "http://$($env:COMPUTERNAME):$CentralAdminPort*"}
		
		##Provision CentralAdmin if indicated in AutoSPInstallerInput.xml and the CA web app doesn't already exist
		If (($CreateCentralAdmin -eq "1") -and (!($CentralAdmin))) {CreateCentralAdmin}
		##Install application content if this is a new farm
		If ($DoFullConfig)
		{
			Write-Host -ForegroundColor White " - Installing Application Content..."
			Install-SPApplicationContent
		}
	}
	catch	
	{
	    If ($err -like "*update conflict*")
		{
			Write-Warning " - A concurrency error occured, trying again."
			CreateCentralAdmin
		}
		Else 
		{
			Write-Output $_
			Pause
			break
		}
	}
	Write-Host -ForegroundColor White "- Completed initial farm/server config."
	
	## If there were language packs installed we need to run psconfig to configure them
	If (($InstalledOfficeServerLanguages.Count -gt 1))
	{
		Write-Host -ForegroundColor White "- Configuring language packs..."
		## Run PSConfig.exe per http://technet.microsoft.com/en-us/library/cc262108.aspx
		Start-Process -FilePath $PSConfig -ArgumentList "-cmd upgrade -inplace v2v -passphrase $FarmPassphrase -force -wait" -NoNewWindow -Wait
	}
}

#EndRegion

#Region Get DB Server
# ===================================================================================
# Func: Get-DBServer
# Desc: Get Database server, if localhost resolve to the machine name 
# TODO: Globally replace all instances of localhost in the input file with $env:COMPUTERNAME
# ===================================================================================
Function Get-DBServer([xml]$xmlinput)
{
    $DBServer =  $xmlinput.Configuration.Farm.Database.DBServer
    If ($DBServer -like "*localhost*") {$DBServer = $DBServer -replace "localhost","$env:COMPUTERNAME"}
    return $DBServer
}
#EndRegion

#Region Add Managed Accounts
# ===================================================================================
# FUNC: AddManagedAccounts
# DESC: Adds existing accounts to SharePoint managed accounts
# ===================================================================================
Function AddManagedAccounts([xml]$xmlinput)
{
	Write-Host " - Adding Managed Accounts" -ForegroundColor White 	
	if ($xmlinput.Configuration.Farm.ManagedAccounts)
	{
		foreach ($account in $xmlinput.Configuration.Farm.ManagedAccounts.ManagedAccount)
		{
            $username = $account.username
            $password = $account.password
            $password =  ConvertTo-SecureString "$password" –AsPlaintext –Force 

            $ManagedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $username}
            If ($ManagedAccountGen -eq $NULL) 
            { 
            	Write-Host -ForegroundColor White " - Registering managed account" $username
     
                If ($username -eq $null -or $password -eq $null) 
                {
                    Write-Host -BackgroundColor Gray -ForegroundColor DarkBlue " - Prompting for Account: "
                	$credAccount = $host.ui.PromptForCredential("Managed Account", "Enter Account Credentials:", "", "NetBiosUserName" )
                } 
                else
                {
                    $credAccount = New-Object System.Management.Automation.PsCredential $username,$password
                }
          
            	New-SPManagedAccount -Credential $credAccount | Out-Null 
            }
            Else 
            {
                Write-Host -ForegroundColor White " - Managed account $username already exists, continuing."
            }

        }
	}

	Write-Host " - Completed Adding Managed Accounts" -ForegroundColor blue 	
}
#EndRegion

#Region Sandboxed Code Service
# ===================================================================================
# Func: InstallSandboxSolutionService
# Desc: Starts the Sandbox solution service
# ===================================================================================
Function InstallSandboxSolutionService
{
    $SandboxedCodeService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Administration.SPUserCodeServiceInstance"} 
    If ($SandboxedCodeService.Status -eq "Disabled") 
    {
    	try
    	{
    		Write-Host -ForegroundColor White " - Starting Microsoft SharePoint Foundation Sandboxed Code Service..."
    		$SandboxedCodeService | Start-SPServiceInstance | Out-Null
    		If (-not $?) {throw " - Failed to start Sandboxed Code Service"}
    	}
    	catch 
        {
            " - An error occurred starting the Microsoft SharePoint Foundation Sandboxed Code Service"
        }
    	#Wait
        Write-Host -ForegroundColor Blue " - Waiting for Sandboxed Code service to start" -NoNewline
        While ($SandboxedCodeService.Status -ne "Online") 
        {
			Write-Host -ForegroundColor Blue "." -NoNewline
			sleep 1
			$SandboxedCodeService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Administration.SPUserCodeServiceInstance"}
		}
		Write-Host -BackgroundColor Blue -ForegroundColor Black "Started!"
    }
}
#EndRegion

#Region Not sure what this is
Function Get-spserviceaccountxml([xml]$xmlinput)
{
    $script:spservice = $xmlinput.Configuration.Farm.ManagedAccounts.ManagedAccount | Where-Object { $_.CommonName -match "spservice" }
    return $spservice
}
#EndRegion

#Region Create Metadata Service App
# ===================================================================================
# Func: CreateMetadataServiceApp
# Desc: Managed Metadata Service Application
# ===================================================================================
Function CreateMetadataServiceApp([xml]$xmlinput)
{
    If ($xmlinput.Configuration.Farm.Services.ManagedMetadataService.create -eq "1") 
    {
    	try
    	{
            $spservice = Get-spserviceaccountxml $xmlinput
            $username = $spservice.username

          	## Managed Account
          	$ManagedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq ($username)}
          	If ($ManagedAccountGen -eq $NULL) { throw "- Managed Account $username not found" }      

    	    ## App Pool
    		Write-Host -ForegroundColor White " - Getting Hosted Services Application Pool, creating if necessary..."
        	$ApplicationPool = Get-SPServiceApplicationPool "SharePoint Hosted Services" -ea SilentlyContinue
        	if($ApplicationPool -eq $null)
    	  	{ 
                $ApplicationPool = New-SPServiceApplicationPool "SharePoint Hosted Services" -account $username
                If (-not $?) { throw " - Failed to create an application pool" }
          	}
            
     	    ## Create a Metadata Service Application
          	If((Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceApplication"}) -eq $null)
    	  	{      
    			Write-Host -ForegroundColor White " - Creating Managed Metadata Service:"
                ## Get the service instance
                $MetadataServiceInstance = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceInstance"}
                If (-not $?) { throw "- Failed to find Metadata service instance" }

                ## Start Service instance
                if($MetadataserviceInstance.Status -eq "Disabled")
    			{ 
                      Write-Host -ForegroundColor White " - Starting Metadata Service Instance..."
                      $MetadataServiceInstance | Start-SPServiceInstance | Out-Null
                      If (-not $?) { throw "- Failed to start Metadata service instance" }
                } 

                ## Wait
    			Write-Host -ForegroundColor Blue " - Waiting for Metadata service to start" -NoNewline
    			While ($MetadataServiceInstance.Status -ne "Online") 
    			{
    				Write-Host -ForegroundColor Blue "." -NoNewline
    				sleep 1
    				$MetadataServiceInstance = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceInstance"}
    			}
    			Write-Host -BackgroundColor Blue -ForegroundColor Black "Started!"

    			## Create Service App
       			Write-Host -ForegroundColor White " - Creating Metadata Service Application..."
                $MetaDataDB = $xmlinput.Configuration.Farm.Services.ManagedMetadataService.Database
                $FarmAcct = $xmlinput.Configuration.Farm.Account.Username
                
                $MetaDataServiceApp  = New-SPMetadataServiceApplication -Name "Metadata Service Application" -ApplicationPool $ApplicationPool -DatabaseName $MetaDataDB -AdministratorAccount $FarmAcct -FullAccessAccount $FarmAcct
                If (-not $?) { throw "- Failed to create Metadata Service Application" }

                ## create proxy
    			Write-Host -ForegroundColor White " - Creating Metadata Service Application Proxy..."
                $MetaDataServiceAppProxy  = New-SPMetadataServiceApplicationProxy -Name "Metadata Service Application Proxy" -ServiceApplication $MetaDataServiceApp -DefaultProxyGroup
                If (-not $?) { throw "- Failed to create Metadata Service Application Proxy" }
                
    			Write-Host -ForegroundColor White " - Granting rights to Metadata Service Application..."
    			## Get ID of "Managed Metadata Service"
    			$MetadataServiceAppToSecure = Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceApplication"}
    			$MetadataServiceAppIDToSecure = $MetadataServiceAppToSecure.Id
    			## Create a variable that contains the list of administrators for the service application 
    			$MetadataServiceAppSecurity = Get-SPServiceApplicationSecurity $MetadataServiceAppIDToSecure
                
        		foreach ($account in ($xmlinput.Configuration.Farm.ManagedAccounts.ManagedAccount | Where-Object { $_.CommonName -match "content" }))
        		{
        			## Create a variable that contains the claims principal for app pool and farm user accounts
        			$AccountPrincipal = New-SPClaimsPrincipal -Identity $account.username -IdentityType WindowsSamAccountName			
        			## Give permissions to the claims principal you just created
        			Grant-SPObjectSecurity $MetadataServiceAppSecurity -Principal $AccountPrincipal -Rights "Full Access to Term Store"

                }    			
    			## Apply the changes to the Metadata Service application
    			Set-SPServiceApplicationSecurity $MetadataServiceAppIDToSecure -objectSecurity $MetadataServiceAppSecurity
                
    			Write-Host -ForegroundColor White " - Done creating Managed Metadata Service."
          	}
    	  	Else {Write-Host -ForegroundColor White " - Managed Metadata Service already exists."}
    	}
    	catch
    	{
    		Write-Output $_ 
    	}
    }
}
#EndRegion

#Region Assign Certificate
# ===================================================================================
# Func: AssignCert
# Desc: Assign SSL certification
# TODO - Not tested
# ===================================================================================
Function AssignCert([xml]$xmlinput)
{
	## Load IIS WebAdministration Snapin/Module
	## Inspired by http://stackoverflow.com/questions/1924217/powershell-load-webadministration-in-ps1-script-on-both-iis-7-and-iis-7-5
    #Region Query OS Type
    $QueryOS = Gwmi Win32_OperatingSystem
    $QueryOS = $QueryOS.Version 
    $OS = ""
    If ($QueryOS.contains("6.1")) {$OS = "Win2008R2"}
    ElseIf ($QueryOS.contains("6.0")) {$OS = "Win2008"}
    Write-Host -ForegroundColor White " - Running on $OS."
    #EndRegion
    
	Try
	{
		If ($OS -eq "Win2008")
		{
			If (!(Get-PSSnapin WebAdministration -ErrorAction SilentlyContinue))
			{	 
  				If (!(Test-Path $env:ProgramFiles\IIS\PowerShellSnapin\IIsConsole.psc1)) 
				{
					Start-Process -Wait -NoNewWindow -FilePath msiexec.exe -ArgumentList "/i `"$bits\PrerequisiteInstallerFiles\iis7psprov_x64.msi`" /passive /promptrestart"
				}
				Add-PSSnapin WebAdministration
			}
		}
		Else ## Win2008R2
		{ 
  			Import-Module WebAdministration
		}
	}
	Catch
	{
		Write-Host -ForegroundColor White " - Could not load IIS Administration module."
	}
	Write-Host -ForegroundColor White " - Assigning certificate to site `"https://$SSLHostHeader`:$SSLPort`""
	Write-Host -ForegroundColor White " - Looking for existing `"$SSLHostHeader`" certificate to use..."
	$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -eq "CN=$SSLHostHeader"}
	If (!$Cert)
	{
		Write-Host -ForegroundColor White " - None found."
		If (Test-Path "$dp0\makecert.exe")
		{
			Write-Host -ForegroundColor White " - Creating new self-signed certificate..."
			Start-Process -NoNewWindow -Wait -FilePath "$dp0\makecert.exe" -ArgumentList "-r -pe -n `"CN=$SSLHostHeader`" -eku 1.3.6.1.5.5.7.3.1 -ss My -sr localMachine -sky exchange -sp `"Microsoft RSA SChannel Cryptographic Provider`" -sy 12"
			$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -eq "CN=$SSLHostHeader"}
			$CertSubject = $Cert.Subject
		}
		Else 
		{
			Write-Host -ForegroundColor White " - `"$dp0\makecert.exe`" not found."
			Write-Host -ForegroundColor White " - Looking for any machine-named certificates we can use..."
			## Select the first certificate with the most recent valid date
			$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -like "*$env:COMPUTERNAME"} | Sort-Object NotBefore -Desc | Select-Object -First 1
			If (!$Cert)
			{
				Write-Host -ForegroundColor White " - None found, skipping certificate creation."
			}
			Else {$CertSubject = $Cert.Subject}
		}
	}
	Else
	{
		$CertSubject = $Cert.Subject
		Write-Host -ForegroundColor White " - Certificate `"$CertSubject`" found."
	}
	If ($Cert)
	{
		## Export our certificate to a file, then import it to the Trusted Root Certification Authorites store so we don't get nasty browser warnings
		## This will actually only work if the Subject and the host part of the URL are the same
		## Borrowed from https://www.orcsweb.com/blog/james/powershell-ing-on-windows-server-how-to-import-certificates-using-powershell/
		Write-Host -ForegroundColor White " - Exporting `"$CertSubject`" to `"$SSLHostHeader.cer`"..."
		$Cert.Export("Cert") | Set-Content "$env:TEMP\$SSLHostHeader.cer" -Encoding byte
		$Pfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
		Write-Host -ForegroundColor White " - Importing `"$SSLHostHeader.cer`" to Local Machine\Root..."
		$Pfx.Import("$env:TEMP\$SSLHostHeader.cer")
		$Store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
		$Store.Open("MaxAllowed")
		$Store.Add($Pfx)
		$Store.Close()
		Write-Host -ForegroundColor White " - Assigning certificate `"$CertSubject`" to SSL-enabled site..."
		#Set-Location IIS:\SslBindings -ErrorAction Inquire
		$Cert | New-Item IIS:\SslBindings\0.0.0.0!$SSLPort -ErrorAction Inquire | Out-Null
		Write-Host -ForegroundColor White "- Certificate has been assigned to site `"https://$SSLHostHeader`:$SSLPort`""
	}
	Else {Write-Host -ForegroundColor White " - No certificates were found, and none could be created."}
	$Cert = $null
}
#EndRegion

#Region Create Web Applications
# ===================================================================================
# Func: CreateWebApplications
# Desc: Create and  configure the required web applications
# ===================================================================================
Function CreateWebApplications([xml]$xmlinput)
{

	if ($xmlinput.Configuration.WebApplications)
	{
		Write-Host "Creating web applications" -ForegroundColor blue 
        foreach ($webApp in $xmlinput.Configuration.WebApplications.WebApplication)
        {
            CreateWebApp $webApp
            SetupManagedPaths $webApp
        }
    }
}
# ===================================================================================
# Func: CreateWebApp
# Desc: Create the web application
# ===================================================================================
Function CreateWebApp([System.Xml.XmlElement]$webApp)
{
        $account = $webApp.applicationPoolAccount
        $name = $webApp.name
        $apppool = $webApp.applicationPool
        $database = $webApp.databaseName
        $url = $webApp.url
        $port = $webApp.port
        $useSSL = $false
        If ($url -like "https://*") {$useSSL = $true}        
        If ($url -like "*localhost*") {$url = $url -replace "localhost","$env:COMPUTERNAME"}
        If ($url -like "https://*") {$hostheader = $url -replace "https://",""}
        Else {$hostheader = $url -replace "http://",""}

        #Region Create Content Web Apps
        $GetSPWebApplication = Get-SPWebApplication | Where-Object {$_.DisplayName -eq $name}
        If ($GetSPWebApplication -eq $Null)
        {
            Write-Host -ForegroundColor White " - Creating Web App $name"
        	If ($webApp.useClaims -eq "1")
        	{
        		## Configure new web app to use Claims-based authentication
        		$PortalAuthProvider = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication
        		New-SPWebApplication -Name $name -ApplicationPoolAccount $account -ApplicationPool $apppool -DatabaseName $database -HostHeader $hostheader -Url $url -Port $port -SecureSocketsLayer:$useSSL -AuthenticationProvider $PortalAuthProvider | Out-Null
        	}
        	Else
        	{
        		## Create the web app using Classic mode authentication
        		New-SPWebApplication -Name $name -ApplicationPoolAccount $account -ApplicationPool $apppool -DatabaseName $database -HostHeader $hostheader -Url $url -Port $port -SecureSocketsLayer:$useSSL | Out-Null
        	}
        }
        Else
        {
        	Write-Host -ForegroundColor White "- Web app $name already exists, continuing..."
        }
        #EndRegion
}
#EndRegion

#Region Setup Managed Paths
# ===================================================================================
# Func: SetupManagedPaths
# Desc: Sets up managed paths for a given web application
# ===================================================================================
Function SetupManagedPaths([System.Xml.XmlElement]$webApp)
{
    $url = $webApp.url + ":" + $webApp.port
    If ($url -like "*localhost*") {$url = $url -replace "localhost","$env:COMPUTERNAME"}
	Write-Host "Setting up managed paths for $url" -ForegroundColor blue

	if ($webApp.ManagedPaths)
	{
	    foreach ($managedPath in $webApp.ManagedPaths.ManagedPath)
		{
            if ($managedPath.Delete -eq "true")
            {
                Write-Host " - Deleting managed path $($managedPath.RelativeUrl) at $url " -ForegroundColor blue            
                Remove-SPManagedPath -Identity $managedPath.RelativeUrl -WebApplication $url -Confirm:$false -ErrorAction SilentlyContinue                
            }
            else
            {
    			if ($managedPath.Explicit -eq "true")
    			{
    				Write-Host " - Setting up explicit managed path $($managedPath.RelativeUrl) at $url " -ForegroundColor blue
    			    New-SPManagedPath -RelativeUrl $managedPath.RelativeUrl -WebApplication $url -Explicit -ErrorAction SilentlyContinue
    			}
    			else
    			{
    				Write-Host " - Setting up managed path $($managedPath.RelativeUrl) at $url " -ForegroundColor blue
    			    New-SPManagedPath -RelativeUrl $managedPath.RelativeUrl -WebApplication $url -ErrorAction SilentlyContinue
    			}
            }
		}
	}

	Write-Host "Completed setting up managed paths at $url" -ForegroundColor blue
}
#EndRegion

#Region Create User Profile Service Application
# ===================================================================================
# Func: CreateUserProfileServiceApplication
# Desc: Create the User Profile Service Application
# ===================================================================================
Function CreateUserProfileServiceApplication([xml]$xmlinput)
{
    ## Based on http://sharepoint.microsoft.com/blogs/zach/Lists/Posts/Post.aspx?ID=50
	try
	{   
        $UserProfile = $xmlinput.Configuration.Farm.Services.UserProfileService
		$MySiteWebApp = $xmlinput.Configuration.WebApplications.WebApplication | Where {$_.type -eq "MySiteHost"} 
		$MySiteName = $MySiteWebApp.name
		$MySiteURL = $MySiteWebApp.url
		$MySitePort = $MySiteWebApp.port
		$MySiteDB = $MySiteWebApp.databaseName
		$MySiteAppPoolAcct = $MySiteWebApp.applicationPoolAccount
        $FarmAcct = $xmlinput.Configuration.Farm.Account.Username
		$FarmAcctPWD = $xmlinput.Configuration.Farm.Account.Password
		$MySiteTemplate = $MySiteWebApp.SiteCollections.SiteCollection.Template
		$MySiteLCID = $MySiteWebApp.SiteCollections.SiteCollection.LCID
		$UserProfileServiceName = $UserProfile.Name
		$ProfileDB = $UserProfile.ProfileDB
		$SyncDB = $UserProfile.SyncDB
		$SocialDB = $UserProfile.SocialDB
		If ([bool]$($UserProfile.Provision) -eq $true) 
        {        
          	Write-Host -ForegroundColor White "- Provisioning $($UserProfile.Name)"

            $spservice = Get-spserviceaccountxml $xmlinput
            $username = $spservice.username

    	  	## Managed Account
          	$ManagedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $spservice.username}
          	If ($ManagedAccountGen -eq $NULL) { throw " - Managed Account $AppPoolAcct not found" }      
          	## App Pool
    	  	Write-Host -ForegroundColor White " - Getting Hosted Services Application Pool, creating if necessary..."
          	$ApplicationPool = Get-SPServiceApplicationPool "SharePoint Hosted Services" -ea SilentlyContinue
          	If ($ApplicationPool -eq $null)
    	  	{ 
                $ApplicationPool = New-SPServiceApplicationPool "SharePoint Hosted Services" -account $ManagedAccountGen 
                If (-not $?) { throw " - Failed to create the application pool" }
          	}

          	## Create a Profile Service Application
          	If ((Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.UserProfileApplication"}) -eq $null)
    	  	{      
                ## get the service instance
                $ProfileServiceInstance = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.UserProfileServiceInstance"}
                If (-not $?) { throw " - Failed to find User Profile Service instance" }

                ## Start Service instance
    			Write-Host -ForegroundColor White " - Starting User Profile Service instance..."
                If (($ProfileServiceInstance.Status -eq "Disabled") -or ($ProfileServiceInstance.Status -ne "Online"))
    			{  
                    $ProfileServiceInstance | Start-SPServiceInstance | Out-Null
                    If (-not $?) { throw " - Failed to start User Profile Service instance" }

                    ## Wait
       				Write-Host -ForegroundColor Blue " - Waiting for User Profile Service to start" -NoNewline
    			    While ($ProfileServiceInstance.Status -ne "Online") 
    			    {
    					Write-Host -ForegroundColor Blue "." -NoNewline
    					sleep 1
    				    $ProfileServiceInstance = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.UserProfileServiceInstance"}
    			    }
    				Write-Host -BackgroundColor Blue -ForegroundColor Black "Started!"
                }

    			## Create MySites Web Application
    			$GetSPWebApplication = Get-SPWebApplication | Where-Object {$_.DisplayName -eq $MySiteName}
    			If ($GetSPWebApplication -eq $Null)
    			{
    			    Write-Host -ForegroundColor White " - Creating Web App `"$MySiteName`"..."
    				New-SPWebApplication -Name $MySiteName -ApplicationPoolAccount $MySiteAppPoolAcct -ApplicationPool $MySiteAppPool -DatabaseName $MySiteDB -HostHeader $MySiteHostHeader -Url $MySiteURL -Port $MySitePort -SecureSocketsLayer:$MySiteUseSSL | Out-Null
    			}
    			Else
    			{
    				Write-Host -ForegroundColor White " - Web app `"$MySiteName`" already exists, continuing..."
    			}
    			
                ## Create MySites Site Collection
    			If ((Get-SPContentDatabase | Where-Object {$_.Name -eq $MySiteDB})-eq $null)
    			{
    				Write-Host -ForegroundColor White " - Creating My Sites content DB..."
    				$NewMySitesDB = New-SPContentDatabase -Name $MySiteDB -WebApplication "$MySiteURL`:$MySitePort"
    				If (-not $?) { throw " - Failed to create My Sites content DB" }
    			}
    			If ((Get-SPSite | Where-Object {$_.Url -eq "$MySiteURL`:$MySitePort"})-eq $null)
    			{
    				Write-Host -ForegroundColor White " - Creating My Sites site collection $MySiteURL`:$MySitePort..."
    				## Verify that the Language we're trying to create the site in is currently installed on the server
                    $MySiteCulture = [System.Globalization.CultureInfo]::GetCultureInfo(([convert]::ToInt32($MySiteLCID)))
    		        $MySiteCultureDisplayName = $MySiteCulture.DisplayName
					$InstalledOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\14.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
					If (!($InstalledOfficeServerLanguages | Where-Object {$_ -eq $MySiteCulture.Name}))
    				{
    		            Write-Warning " - You must install the `"$MySiteCulture ($MySiteCultureDisplayName)`" Language Pack before you can create a site using LCID $MySiteLCID"
                        Pause
                        break
    	            }
    	            Else
    	            {
        				$NewMySitesCollection = New-SPSite -Url "$MySiteURL`:$MySitePort" -OwnerAlias $FarmAcct -SecondaryOwnerAlias $env:USERDOMAIN\$env:USERNAME -ContentDatabase $MySiteDB -Description $MySiteName -Name $MySiteName -Template $MySiteTemplate -Language $MySiteLCID | Out-Null
    				    If (-not $?) {throw " - Failed to create My Sites site collection"}
                        ## Assign SSL certificate, if required
    			        If ($MySiteUseSSL)
    			        {
    				    	$SSLHostHeader = $MySiteHostHeader
    				    	$SSLPort = $MySitePort
    				    	AssignCert
    			        }
                    }
    			}
    			## Create Service App
    			Write-Host -ForegroundColor White " - Creating $UserProfileServiceName..."
				## This is essentially the workaround by @harbars & @glapointe http://www.harbar.net/archive/2010/10/30/avoiding-the-default-schema-issue-when-creating-the-user-profile.aspx
				## Modified to work within AutoSPInstaller (to pass our script variables to the Farm Account credential's Powershell session)
				$ScriptFile = "$env:TEMP\AutoSPInstaller-ScriptBlock.ps1"
				## Write the script block, with expanded variables to a temporary script file that the Farm Account can get at
				Write-Output "`$ProfileServiceApp = New-SPProfileServiceApplication -Name `"$UserProfileServiceName`" -ApplicationPool `"$($ApplicationPool.DisplayName)`" -ProfileDBName $ProfileDB -ProfileSyncDBName $SyncDB -SocialDBName $SocialDB -MySiteHostLocation `"$MySiteURL`:$MySitePort`"; If (-not `$?) {throw `" - Failed to create $UserProfileServiceName`"}" | Out-File $ScriptFile -Width 300
				## Start a job under the Farm Account's credentials and execute the script file to create the UPS
				$CreateProfileServiceAppJob = Start-Job -Name CreateProfileServiceAppJob -Credential $FarmCredential -FilePath $ScriptFile -Verbose -InitializationScript {Add-PsSnapin Microsoft.SharePoint.PowerShell} | Wait-Job
				Receive-Job -Name CreateProfileServiceAppJob -Verbose
				## Delete the temporary script file
				Remove-Item -Path "$env:TEMP\AutoSPInstaller-ScriptBlock.ps1"

				## Get our new Profile Service App
				$ProfileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $UserProfileServiceName}

				## Create Proxy
    			Write-Host -ForegroundColor White " - Creating $UserProfileServiceName Proxy..."
                $ProfileServiceAppProxy  = New-SPProfileServiceApplicationProxy -Name "$UserProfileServiceName Proxy" -ServiceApplication $ProfileServiceApp -DefaultProxyGroup
                If (-not $?) { throw " - Failed to create $UserProfileServiceName Proxy" }
    			
    			## Get ID of $UserProfileServiceName
    			#Write-Host -ForegroundColor White " - Get ID of $UserProfileServiceName..."
				# $ProfileServiceApp = Get-SPServiceApplication |?{$_.TypeName -eq $UserProfileServiceName}
				# $ProfileServiceAppID = $ProfileServiceApp.Id

    			Write-Host -ForegroundColor White " - Granting rights to $UserProfileServiceName..."
    			## Create a variable that contains the guid for the User Profile service for which you want to delegate Full Control
				$ServiceAppIDToSecure = Get-SPServiceApplication $($ProfileServiceApp.Id)

    			## Create a variable that contains the list of administrators for the service application 
				$ProfileServiceAppSecurity = Get-SPServiceApplicationSecurity $ServiceAppIDToSecure -Admin

    			## Create a variable that contains the claims principal for app pool and farm user accounts
    			$MySiteAppPoolAcctPrincipal = New-SPClaimsPrincipal -Identity $MySiteAppPoolAcct -IdentityType WindowsSamAccountName
    			$FarmAcctPrincipal =  New-SPClaimsPrincipal -Identity $FarmAcct -IdentityType WindowsSamAccountName

    			## Give Full Control permissions to the claims principal you just created, and the Farm Account
    			Grant-SPObjectSecurity $ProfileServiceAppSecurity -Principal $MySiteAppPoolAcctPrincipal -Rights "Full Control"
    			Grant-SPObjectSecurity $ProfileServiceAppSecurity -Principal $FarmAcctPrincipal -Rights "Full Control"

    			## Apply the changes to the User Profile service application
				Set-SPServiceApplicationSecurity $ServiceAppIDToSecure -objectSecurity $ProfileServiceAppSecurity -Admin
    			
    			## Launch My Site host
    			Write-Host -ForegroundColor White " - Launching $MySiteURL`:$MySitePort..."
    			Start-Process "$MySiteURL`:$MySitePort" -WindowStyle Minimized
    			
    			Write-Host -ForegroundColor White "- Done creating $UserProfileServiceName."
          	}
            
    		## Start User Profile Synchronization Service
    		## Get User Profile Service
    		$ProfileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $UserProfileServiceName}
    		If ($ProfileServiceApp)
    		{
    			## Get User Profile Synchronization Service
    			Write-Host -ForegroundColor White "- Checking User Profile Synchronization Service..." -NoNewline
    			$ProfileSyncService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance"}
				##Attempt to start if there's only 1 Profile Sync Service instance in the farm as we probably don't want to start multiple Sync instances in the farm (running against the same Profile Service at least)
				If (!($ProfileSyncService.Count -gt 1) -and ($ProfileSyncService.Status -ne "Online"))
    			{
    				## Inspired by http://technet.microsoft.com/en-us/library/ee721049.aspx
    				If (!($FarmAcct)) {$FarmAcct = (Get-SPFarm).DefaultServiceAccount}
    				If (!($FarmAcctPWD)) 
    				{
    					Write-Host -ForegroundColor White "`n"
    					$FarmAcctPWD = Read-Host -Prompt " - Please (re-)enter the Farm Account Password" -AsSecureString
    				}
    				Write-Host -ForegroundColor White "`n"
    				Write-Host -ForegroundColor White " - Starting User Profile Synchronization Service..." -NoNewline
    				$ProfileServiceApp.SetSynchronizationMachine($env:COMPUTERNAME, $ProfileSyncService.Id, $FarmAcct, (ConvertTo-PlainText $FarmAcctPWD))
    				If (($ProfileSyncService.Status -ne "Provisioning") -and ($ProfileSyncService.Status -ne "Online")) {Write-Host -ForegroundColor Blue " - Waiting for User Profile Synchronization Service to be started..." -NoNewline}
    				Else ## Monitor User Profile Sync service status
    				{
    				While ($ProfileSyncService.Status -ne "Online")
    				{
    					While ($ProfileSyncService.Status -ne "Provisioning")
    					{
    						Write-Host -ForegroundColor Blue ".`a" -NoNewline
    						Sleep 1
    						$ProfileSyncService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance"}
    					}
    					If ($ProfileSyncService.Status -eq "Provisioning")
    					{
    						Write-Host -BackgroundColor Blue -ForegroundColor Black "Started!`a`a"
                			Write-Host -ForegroundColor Blue " - Provisioning User Profile Sync Service, please wait (up to 15 minutes)..." -NoNewline
    					}
    					While($ProfileSyncService.Status -eq "Provisioning" -and $ProfileSyncService.Status -ne "Disabled")
    					{
    						Write-Host -ForegroundColor Blue ".`a" -NoNewline
    						sleep 1
    						$ProfileSyncService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance"}
    					}
    					If ($ProfileSyncService.Status -ne "Online")
    					{
    						Write-Host -ForegroundColor Red ".`a`a`a`a`a`a`a`a" 
    						Write-Host -BackgroundColor Red -ForegroundColor Black "- User Profile Synchronization Service could not be started!"
    						break
    					}
    					Else
    					{
    						Write-Host -BackgroundColor Blue -ForegroundColor Black "Started!`a`a"
    						## Need to restart IIS before we can do anything with the User Profile Sync Service
    						Write-Host -ForegroundColor White " - Restarting IIS..."
    						Start-Process -FilePath iisreset.exe -ArgumentList "-noforce" -Wait -NoNewWindow
    					}
    				}
    				}
    			}
    			Else {Write-Host -ForegroundColor White "Already started."}
    		}
    		Else 
    		{
    			Write-Host "`n"
    			Write-Host -ForegroundColor Red "- Could not get User Profile Service"
    		}
        }
	}
	catch
    {
        Write-Output $_ 
    }
}
#EndRegion

#Region Create State Service Application
Function CreateStateServiceApp([xml]$xmlinput)
{
    $StateService = $xmlinput.Configuration.Services.StateService
	If ([bool]$($StateService.Provision) -eq $true) 
	{
		try
		{
			$StateServiceDB = $StateService.StateServiceDB
			$GetSPStateServiceApplication = Get-SPStateServiceApplication
			If ($GetSPStateServiceApplication -eq $Null)
			{
				Write-Host -ForegroundColor White "- Creating State Service Application..."
				New-SPStateServiceDatabase -Name $StateServiceDB | Out-Null
				New-SPStateServiceApplication -Name "State Service Application" -Database $StateServiceDB | Out-Null
				Get-SPStateServiceDatabase | Initialize-SPStateServiceDatabase | Out-Null
				Write-Host -ForegroundColor White " - Creating State Service Application Proxy..."
				Get-SPStateServiceApplication | New-SPStateServiceApplicationProxy -Name "State Service Application Proxy" -DefaultProxyGroup | Out-Null
				Write-Host -ForegroundColor White "- Done creating State Service Application."
			}
			Else {Write-Host -ForegroundColor White "- State Service Application exists, continuing..."}
		}
		catch
		{
			Write-Output $_
		}
	}
}
#EndRegion

#Region Create WSS Usage Application
Function CreateWSSUsageApp([xml]$xmlinput)
{
    If ([bool]$($xmlinput.Configuration.Services.WSSUsageService.Provision) -eq $true) 
	{
		try
		{
			$WSSUsageApplication = $xmlinput.Configuration.Services.WSSUsageService.Name
			$WSSUsageDB = $xmlinput.Configuration.Services.WSSUsageService.WSSUsageDB
			$GetSPUsageApplication = Get-SPUsageApplication
			If ($GetSPUsageApplication -eq $Null)
			{
				Write-Host -ForegroundColor White "- Creating WSS Usage Application..."
				New-SPUsageApplication -Name $WSSUsageApplication -DatabaseServer $DBServer -DatabaseName $WSSUsageDB | Out-Null
				## Need this to resolve a known issue with the Usage Application Proxy not automatically starting/provisioning
				## Thanks and credit to Jesper Nygaard Schiøtt (jesper@schioett.dk) per http://autospinstaller.codeplex.com/Thread/View.aspx?ThreadId=237578 ! 
				Write-Host -ForegroundColor White " - Fixing Usage and Health Data Collection Proxy..."
				$SPUsageApplicationProxy = Get-SPServiceApplicationProxy | where {$_.DisplayName -eq $WSSUsageApplication}
				$SPUsageApplicationProxy.Provision()
				## End Usage Proxy Fix
				Write-Host -ForegroundColor White "- Done Creating WSS Usage Application."
			}
			Else {Write-Host -ForegroundColor White "- WSS Usage Application exists, continuing..."}
		}
		catch
		{
			Write-Output $_
		}
	}
}
#EndRegion

#Region Create Web Analytics Service Application
## Thanks and credit to Jesper Nygaard Schiøtt (jesper@schioett.dk) per http://autospinstaller.codeplex.com/Thread/View.aspx?ThreadId=237578 !

Function CreateWebAnalyticsApp([xml]$xmlinput)
{
	If ([bool]$($xmlinput.Configuration.Services.WebAnalyticsService.Provision) -eq $true) 
	{
		try
		{
			$WebAnalyticsReportingDB = $xmlinput.Configuration.Services.WebAnalyticsService.ReportingDB
			$WebAnalyticsStagingDB = $xmlinput.Configuration.Services.WebAnalyticsService.StagingDB
			$WebAnalyticsService = $xmlinput.Configuration.Services.WebAnalyticsService.Name
			$AppPoolAcct = $spservice.username
			$GetWebAnalyticsServiceApplication = Get-SPWebAnalyticsServiceApplication $WebAnalyticsService -ea SilentlyContinue
			If ($GetWebAnalyticsServiceApplication -eq $null)
			{
				$StagerSubscription = "<StagingDatabases><StagingDatabase ServerName='$DBServer' DatabaseName='$WebAnalyticsStagingDB'/></StagingDatabases>"
				$WarehouseSubscription = "<ReportingDatabases><ReportingDatabase ServerName='$DBServer' DatabaseName='$WebAnalyticsReportingDB'/></ReportingDatabases>" 
	
		    	## Managed Account
		    	$ManagedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $AppPoolAcct}
		    	if ($ManagedAccountGen -eq $NULL) { throw "- Managed Account $AppPoolAcct not found" }      
				## App Pool
				Write-Host -ForegroundColor White "- Getting Hosted Services Application Pool, creating if necessary..."
		    	$ApplicationPool = Get-SPServiceApplicationPool "SharePoint Hosted Services" -ea SilentlyContinue
		    	If ($ApplicationPool -eq $null)
				{ 
			    	$ApplicationPool = New-SPServiceApplicationPool "SharePoint Hosted Services" -account $ManagedAccountGen
		        	If (-not $?) { throw "Failed to create an application pool" }
		    	}	 
					
				Write-Host -ForegroundColor White "- Creating Web Analytics Service Application"
		    	$ServiceApplication = New-SPWebAnalyticsServiceApplication -Name $WebAnalyticsService -ReportingDataRetention 20 -SamplingRate 100 -ListOfReportingDatabases $WarehouseSubscription -ListOfStagingDatabases $StagerSubscription -ApplicationPool $ApplicationPool 
	
		    	## Create Web Analytics Service Application Proxy
				Write-Host -ForegroundColor White " - Creating Web Analytics Service Application Proxy"
				$NewWebAnalyticsServiceApplicationProxy = New-SPWebAnalyticsServiceApplicationProxy  -Name $WebAnalyticsService -ServiceApplication $ServiceApplication.Name
			     
		    	## Start Analytics service instances
				Write-Host -ForegroundColor White " - Starting Analytics Service instances ..."
				$AnalyticsDataProcessingInstance = Get-SPServiceInstance | where-object {$_.Name -eq "WebAnalyticsServiceInstance"}
				$AnalyticsWebServiceInstance = Get-SPServiceInstance | where-object {$_.TypeName -eq "Web Analytics Web Service"}
			     
		    	$AnalyticsDataProcessingInstance | Start-SPServiceInstance | Out-Null
		    	$AnalyticsWebServiceInstance | Start-SPServiceInstance | Out-Null
			}
			Else {Write-Host -ForegroundColor White " - Web Analytics Service Application exists, continuing..."}
		}
		catch
		{
			Write-Output $_
		}
	}
}
#EndRegion

#Region Create Secure Store Service Application
Function CreateSecureStoreServiceApp
{
    If ([bool]$($xmlinput.Configuration.Services.SecureStoreService.Provision) -eq $true) 
	{
		try
		{
			$SecureStoreDB = $xmlinput.Configuration.Services.SecureStoreService.SecureStoreDB
	        Write-Host -ForegroundColor White "- Creating Secure Store Service..."
			$GetSPSecureStoreServiceApplication = Get-SPServiceApplication | ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplication])}
			If ($GetSPSecureStoreServiceApplication -eq $Null)
			{
				## Get the service instance
            	$SecureStoreServiceInstance = Get-SPServiceInstance | ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceInstance])}
            	if (-not $?) { throw "- Failed to find Secure Store service instance" }
	
            	## Start Service instance
            	if($SecureStoreServiceInstance.Status -eq "Disabled")
				{ 
	                Write-Host -ForegroundColor White " - Starting Secure Store Service Instance..."
                	$SecureStoreServiceInstance | Start-SPServiceInstance | Out-Null
                	if (-not $?) { throw "- Failed to start Secure Store service instance" }
                	## Wait
			    	Write-Host -ForegroundColor Blue " - Waiting for Secure Store service to start" -NoNewline
					While ($SecureStoreServiceInstance.Status -ne "Online") 
			    	{
						Write-Host -ForegroundColor Blue "." -NoNewline
						sleep 1
				    	$SecureStoreServiceInstance = Get-SPServiceInstance | ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceInstance])}
			    	}
					Write-Host -BackgroundColor Blue -ForegroundColor Black "Started!"
            	}
	
				Write-Host -ForegroundColor White " - Creating Secure Store Service Application..."
				New-SPSecureStoreServiceApplication -Name "Secure Store Service" -PartitionMode:$false -Sharing:$false -DatabaseName $SecureStoreDB -ApplicationPool "SharePoint Web Services System" -AuditingEnabled:$true -AuditLogMaxSize 30 | Out-Null
				Write-Host -ForegroundColor White " - Creating Secure Store Service Application Proxy..."
				Get-SPServiceApplication | ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplication])} | New-SPSecureStoreServiceApplicationProxy -Name "Secure Store Service Proxy" -DefaultProxyGroup | Out-Null
				Write-Host -ForegroundColor White " - Done creating Secure Store Service Application."
			}
			Else {Write-Host -ForegroundColor White " - Secure Store Service Application exists, continuing..."}
			
			$secureStore=Get-SPServiceApplicationProxy | Where {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplicationProxy])} 
			Write-Host -ForegroundColor White " - Creating the Master Key..."
 			Update-SPSecureStoreMasterKey -ServiceApplicationProxy $secureStore.Id -Passphrase "$FarmPassPhrase"
			Write-Host -ForegroundColor White " - Creating the Application Key..."
			Update-SPSecureStoreApplicationServerKey -ServiceApplicationProxy $secureStore.Id -Passphrase "$FarmPassPhrase" -ErrorAction SilentlyContinue
			If (!$?)
			{
				## Try again...
				Write-Host -ForegroundColor White " - Creating the Application Key (2nd attempt)..."
				Update-SPSecureStoreApplicationServerKey -ServiceApplicationProxy $secureStore.Id -Passphrase "$FarmPassPhrase"
			}
			Write-Host -ForegroundColor White " - Setting the unattended account for Performance Point Services..."
			Get-SPPerformancePointServiceApplication | Set-SPPerformancePointSecureDataValues -DataSourceUnattendedServiceAccount $FarmCredential
		}
		catch
		{
			Write-Output $_
		}
		Write-Host -ForegroundColor White "- Done creating/configuring Secure Store Service."
	}
}
#EndRegion

#Region Start Search Query and Site Settings Service
Function StartSearchQueryAndSiteSettingsService
{
try
{
	## Get the service instance
    $SearchQueryAndSiteSettingsService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance"}
    If (-not $?) { throw "- Failed to find Search Query and Site Settings service instance" }

    ## Start Service instance
    Write-Host -ForegroundColor White "- Starting Search Query and Site Settings Service Instance..."
    if($SearchQueryAndSiteSettingsService.Status -eq "Disabled")
	{ 
        $SearchQueryAndSiteSettingsService | Start-SPServiceInstance | Out-Null
        If (-not $?) { throw " - Failed to start Search Query and Site Settings service instance" }

        ## Wait
    	Write-Host -ForegroundColor Blue " - Waiting for Search Query and Site Settings service to start" -NoNewline
		While ($SearchQueryAndSiteSettingsService.Status -ne "Online") 
	    {
			Write-Host -ForegroundColor Blue "." -NoNewline
		  	start-sleep 1
		  	$SearchQueryAndSiteSettingsService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance"}
	    }
		Write-Host -BackgroundColor Blue -ForegroundColor Black "Started!"
    }
    Else {Write-Host -ForegroundColor White "- Search Query and Site Settings Service already started, continuing..."}
}
catch
{
	Write-Output $_ 
}
}
If ($StartSearchQueryAndSiteSettingsService -eq "1") {StartSearchQueryAndSiteSettingsService}
#EndRegion

#Region Setup Enterprise Search

## Original script for SharePoint 2010 beta2 by Gary Lapointe ()
##
## Modified by Søren Laurits Nielsen (soerennielsen.wordpress.com):
##
## Modified to fix some errors since some cmdlets have changed a bit since beta 2 and added support for "ShareName" for 
## the query component. It is required for non DC computers. 
## 
## Modified to support "localhost" moniker in config file. 
##
## Note: Accounts, Shares and directories specified in the config file must be setup beforehand.

function Start-EnterpriseSearch([string]$settingsFile = "$InputFile") {
    Write-Host -ForegroundColor White "- Setting up Enterprise Search..."
	## SLN: Added support for local host
    [xml]$config = (Get-Content $settingsFile) -replace( "localhost", $env:computername )
    $svcConfig = $config.SP2010Config.Services.EnterpriseSearchService
 
    $searchSvc = Get-SPEnterpriseSearchServiceInstance -Local
    If ($searchSvc -eq $null) {
        throw " - Unable to retrieve search service."
    }

    ##SLN: Does NOT set the service account, uses the default as Set-SPEnterpriseSearchService 
    ## have a hard time understanding it without an actual secure password (which you don't have by looking up the 
    ## manager service account).
    
    #Write-Host -ForegroundColor White "Getting $($svcConfig.Account) account for search service..."
    #$searchSvcManagedAccount = (Get-SPManagedAccount -Identity $svcConfig.Account -ErrorVariable err -ErrorAction SilentlyContinue)
    #if ($err) {
    #    $searchSvcAccount = Get-Credential $svcConfig.Account 
    #    $searchSvcManagedAccount = New-SPManagedAccount -Credential $searchSvcAccount
    #}

    Get-SPEnterpriseSearchService | Set-SPEnterpriseSearchService  `
      -ContactEmail $svcConfig.ContactEmail -ConnectionTimeout $svcConfig.ConnectionTimeout `
      -AcknowledgementTimeout $svcConfig.AcknowledgementTimeout -ProxyType $svcConfig.ProxyType `
      -IgnoreSSLWarnings $svcConfig.IgnoreSSLWarnings -InternetIdentity $svcConfig.InternetIdentity -PerformanceLevel $svcConfig.PerformanceLevel
   
    Write-Host -ForegroundColor White " - Setting default index location on search service..."

    $searchSvc | Set-SPEnterpriseSearchServiceInstance -DefaultIndexLocation $svcConfig.IndexLocation -ErrorAction SilentlyContinue -ErrorVariable err

    $svcConfig.EnterpriseSearchServiceApplications.EnterpriseSearchServiceApplication | ForEach-Object {
        $appConfig = $_

        ## Try and get the application pool if it already exists
        $pool = Get-ApplicationPool $appConfig.ApplicationPool
        $adminPool = Get-ApplicationPool $appConfig.AdminComponent.ApplicationPool

        $searchApp = Get-SPEnterpriseSearchServiceApplication -Identity $appConfig.Name -ErrorAction SilentlyContinue

        If ($searchApp -eq $null) {
            Write-Host -ForegroundColor White " - Creating enterprise search service application..."
            $searchApp = New-SPEnterpriseSearchServiceApplication -Name $appConfig.Name `
                -DatabaseServer $appConfig.DatabaseServer `
                -DatabaseName $($DBPrefix+$appConfig.DatabaseName) `
                -FailoverDatabaseServer $appConfig.FailoverDatabaseServer `
                -ApplicationPool $pool `
                -AdminApplicationPool $adminPool `
                -Partitioned:([bool]::Parse($appConfig.Partitioned)) `
                -SearchApplicationType $appConfig.SearchServiceApplicationType
        } else {
            Write-Host -ForegroundColor White " - Enterprise search service application already exists, skipping creation."
        }

        $installCrawlSvc = (($appConfig.CrawlServers.Server | where {$_.Name -eq $env:computername}) -ne $null)
        $installQuerySvc = (($appConfig.QueryServers.Server | where {$_.Name -eq $env:computername}) -ne $null)
        $installAdminCmpnt = (($appConfig.AdminComponent.Server | where {$_.Name -eq $env:computername}) -ne $null)
        $installSyncSvc = (($appConfig.SearchQueryAndSiteSettingsServers.Server | where {$_.Name -eq $env:computername}) -ne $null)

        If ($searchSvc.Status -ne "Online" -and ($installCrawlSvc -or $installQuerySvc)) {
            $searchSvc | Start-SPEnterpriseSearchServiceInstance
        }

        If ($installAdminCmpnt) {
            Write-Host -ForegroundColor White " - Setting administration component..."
            Set-SPEnterpriseSearchAdministrationComponent -SearchApplication $searchApp -SearchServiceInstance $searchSvc
        }

        $crawlTopology = Get-SPEnterpriseSearchCrawlTopology -SearchApplication $searchApp | where {$_.CrawlComponents.Count -gt 0 -or $_.State -eq "Inactive"}

        If ($crawlTopology -eq $null) {
            Write-Host -ForegroundColor White " - Creating new crawl topology..."
            $crawlTopology = $searchApp | New-SPEnterpriseSearchCrawlTopology
        } else {
            Write-Host -ForegroundColor White " - A crawl topology with crawl components already exists, skipping crawl topology creation."
        }
 
        If ($installCrawlSvc) {
            $crawlComponent = $crawlTopology.CrawlComponents | where {$_.ServerName -eq $env:ComputerName}
            If ($crawlTopology.CrawlComponents.Count -eq 0 -and $crawlComponent -eq $null) {
                $crawlStore = $searchApp.CrawlStores | where {$_.Name -eq "$($DBPrefix+$appConfig.DatabaseName)_CrawlStore"}
                Write-Host -ForegroundColor White " - Creating new crawl component..."
                $crawlComponent = New-SPEnterpriseSearchCrawlComponent -SearchServiceInstance $searchSvc -SearchApplication $searchApp -CrawlTopology $crawlTopology -CrawlDatabase $crawlStore.Id.ToString() -IndexLocation $appConfig.IndexLocation
            } else {
                Write-Host -ForegroundColor White " - Crawl component already exist, skipping crawl component creation."
            }
        }

        $queryTopology = Get-SPEnterpriseSearchQueryTopology -SearchApplication $searchApp | where {$_.QueryComponents.Count -gt 0 -or $_.State -eq "Inactive"}

        If ($queryTopology -eq $null) {
            Write-Host -ForegroundColor White " - Creating new query topology..."
            $queryTopology = $searchApp | New-SPEnterpriseSearchQueryTopology -Partitions $appConfig.Partitions
        } else {
            Write-Host -ForegroundColor White " - A query topology with query components already exists, skipping query topology creation."
        }

        If ($installQuerySvc) {
            $queryComponent = $queryTopology.QueryComponents | where {$_.ServerName -eq $env:ComputerName}
            #If ($true){ #$queryTopology.QueryComponents.Count -eq 0 -and $queryComponent -eq $null) {
            If ($queryTopology.QueryComponents.Count -eq 0 -and $queryComponent -eq $null) {
                $partition = ($queryTopology | Get-SPEnterpriseSearchIndexPartition)
                Write-Host -ForegroundColor White " - Creating new query component..."
                $queryComponent = New-SPEnterpriseSearchQueryComponent -IndexPartition $partition -QueryTopology $queryTopology -SearchServiceInstance $searchSvc -ShareName $svcConfig.ShareName
                Write-Host -ForegroundColor White " - Setting index partition and property store database..."
                $propertyStore = $searchApp.PropertyStores | where {$_.Name -eq "$($DBPrefix+$appConfig.DatabaseName)_PropertyStore"}
                $partition | Set-SPEnterpriseSearchIndexPartition -PropertyDatabase $propertyStore.Id.ToString()
            } else {
                Write-Host -ForegroundColor White " - Query component already exist, skipping query component creation."
            }
        }

        If ($installSyncSvc) {            
            ## SLN: Updated to new syntax
			$SearchQueryAndSiteSettingsService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance"}
    		If (-not $?) { throw "- Failed to find Search Query and Site Settings service instance" }
			## Start Service instance
    		If ($SearchQueryAndSiteSettingsService.Status -eq "Disabled")
			{
   	    		Write-Host -ForegroundColor White "- Starting Search Query and Site Settings Service Instance..."
				Start-SPServiceInstance (Get-SPServiceInstance | where { $_.TypeName -eq "Search Query and Site Settings Service"}).Id
			}
        }

        ## Don't activate until we've added all components
        $allCrawlServersDone = $true
        $appConfig.CrawlServers.Server | ForEach-Object {
            $server = $_.Name
            $top = $crawlTopology.CrawlComponents | where {$_.ServerName -eq $server}
            If ($top -eq $null) { $allCrawlServersDone = $false }
        }

        If ($allCrawlServersDone -and $crawlTopology.State -ne "Active") {
            Write-Host -ForegroundColor White " - Setting new crawl topology to active..."
            $crawlTopology | Set-SPEnterpriseSearchCrawlTopology -Active -Confirm:$false
			Write-Host -ForegroundColor Blue " - Waiting on Crawl Components to provision..." -NoNewLine
			while ($true) 
			{
				$ct = Get-SPEnterpriseSearchCrawlTopology -Identity $crawlTopology -SearchApplication $searchApp
				$state = $ct.CrawlComponents | where {$_.State -ne "Ready"}
				If ($ct.State -eq "Active" -and $state -eq $null) 
				{
					break
				}
				Write-Host -ForegroundColor Blue "." -NoNewLine
				Start-Sleep 1
			}
            Write-Host -BackgroundColor Blue -ForegroundColor Black "Done!"

			## Need to delete the original crawl topology that was created by default
            $searchApp | Get-SPEnterpriseSearchCrawlTopology | where {$_.State -eq "Inactive"} | Remove-SPEnterpriseSearchCrawlTopology -Confirm:$false
        }

        $allQueryServersDone = $true
        $appConfig.QueryServers.Server | ForEach-Object {
            $server = $_.Name
            $top = $queryTopology.QueryComponents | where {$_.ServerName -eq $server}
            If ($top -eq $null) { $allQueryServersDone = $false }
        }

        ## Make sure we have a crawl component added and started before trying to enable the query component
        If ($allCrawlServersDone -and $allQueryServersDone -and $queryTopology.State -ne "Active") {
            Write-Host -ForegroundColor White " - Setting query topology as active..."
            $queryTopology | Set-SPEnterpriseSearchQueryTopology -Active -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
			Write-Host -ForegroundColor Blue " - Waiting on Query Components to provision..." -NoNewLine
			while ($true) 
			{
				$qt = Get-SPEnterpriseSearchQueryTopology -Identity $queryTopology -SearchApplication $searchApp
				$state = $qt.QueryComponents | where {$_.State -ne "Ready"}
				If ($qt.State -eq "Active" -and $state -eq $null) 
				{
				break
				}
				Write-Host -ForegroundColor Blue "." -NoNewLine
				Start-Sleep 1
			}
            Write-Host -BackgroundColor Blue -ForegroundColor Black "Done!"
			
            ## Need to delete the original query topology that was created by default
            $searchApp | Get-SPEnterpriseSearchQueryTopology | where {$_.State -eq "Inactive"} | Remove-SPEnterpriseSearchQueryTopology -Confirm:$false
        }

        $proxy = Get-SPEnterpriseSearchServiceApplicationProxy -Identity $appConfig.Proxy.Name -ErrorAction SilentlyContinue
        If ($proxy -eq $null) {
            Write-Host -ForegroundColor White " - Creating enterprise search service application proxy..."
            $proxy = New-SPEnterpriseSearchServiceApplicationProxy -Name $appConfig.Proxy.Name -SearchApplication $searchApp -Partitioned:([bool]::Parse($appConfig.Proxy.Partitioned))
        } else {
            Write-Host -ForegroundColor White " - Enterprise search service application proxy already exists, skipping creation."
        }

        If ($proxy.Status -ne "Online") {
            $proxy.Status = "Online"
            $proxy.Update()
        }

        $proxy | Set-ProxyGroupsMembership $appConfig.Proxy.ProxyGroup
    }

    ## SLN: Create the network share (will report an error if exist)
    ## default to primitives 
    $PathToShare = """" + $svcConfig.ShareName + "=" + $svcConfig.IndexLocation + """"
	## The path to be shared should exist if the Enterprise Search App creation succeeded earlier
    Write-Host -ForegroundColor White " - Creating network share $PathToShare"
    net share $PathToShare "/GRANT:WSS_WPG,CHANGE"

	## Finally, set the crawl start addresses (including the elusive sps3:// URL required for People Search:
	$CrawlStartAddresses = $PortalURL+":"+$PortalPort+","+$MySiteURL+":"+$MySitePort+",sps3://"+$MySiteHostHeader+":"+$MySitePort
	Get-SPEnterpriseSearchServiceApplication | Get-SPEnterpriseSearchCrawlContentSource | Set-SPEnterpriseSearchCrawlContentSource -StartAddresses $CrawlStartAddresses
}

function Set-ProxyGroupsMembership([System.Xml.XmlElement[]]$groups, [Microsoft.SharePoint.Administration.SPServiceApplicationProxy[]]$InputObject)
{
    begin {}
    process {
        $proxy = $_
        
        ## Clear any existing proxy group assignments
        Get-SPServiceApplicationProxyGroup | where {$_.Proxies -contains $proxy} | ForEach-Object {
            $proxyGroupName = $_.Name
            If ([string]::IsNullOrEmpty($proxyGroupName)) { $proxyGroupName = "Default" }
            $group = $null
            [bool]$matchFound = $false
            foreach ($g in $groups) {
                $group = $g.Name
                If ($group -eq $proxyGroupName) { 
                    $matchFound = $true
                    break 
                }
            }
            If (!$matchFound) {
                Write-Host -ForegroundColor White " - Removing ""$($proxy.DisplayName)"" from ""$proxyGroupName"""
                $_ | Remove-SPServiceApplicationProxyGroupMember -Member $proxy -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
        
        foreach ($g in $groups) {
            $group = $g.Name

            $pg = $null
            If ($group -eq "Default" -or [string]::IsNullOrEmpty($group)) {
                $pg = [Microsoft.SharePoint.Administration.SPServiceApplicationProxyGroup]::Default
            } else {
                $pg = Get-SPServiceApplicationProxyGroup $group -ErrorAction SilentlyContinue -ErrorVariable err
                If ($pg -eq $null) {
                    $pg = New-SPServiceApplicationProxyGroup -Name $name
                }
            }
            
            $pg = $pg | where {$_.Proxies -notcontains $proxy}
            If ($pg -ne $null) { 
                Write-Host -ForegroundColor White " - Adding ""$($proxy.DisplayName)"" to ""$($pg.DisplayName)"""
                $pg | Add-SPServiceApplicationProxyGroupMember -Member $proxy 
            }
        }
    }
    end {}
}

function Get-ApplicationPool([System.Xml.XmlElement]$appPoolConfig) {
    ## Try and get the application pool if it already exists
    ## SLN: Updated names
    $pool = Get-SPServiceApplicationPool -Identity $appPoolConfig.Name -ErrorVariable err -ErrorAction SilentlyContinue
    If ($err) {
        ## The application pool does not exist so create.
        Write-Host -ForegroundColor White " - Getting $($appPoolConfig.Account) account for application pool..."
        $ManagedAccountSearch = (Get-SPManagedAccount -Identity $appPoolConfig.Account -ErrorVariable err -ErrorAction SilentlyContinue)
        If ($err) {
            If (($appPoolConfig.Password -ne "") -and ($appPoolConfig.Password -ne $null)) 
			{
				$appPoolConfigPWD = (ConvertTo-SecureString $appPoolConfig.Password -AsPlainText -force)
				$accountCred = New-Object System.Management.Automation.PsCredential $appPoolConfig.Account,$appPoolConfigPWD
			}
			Else
			{
				$accountCred = Get-Credential $appPoolConfig.Account
			}
            $ManagedAccountSearch = New-SPManagedAccount -Credential $accountCred
        }
        Write-Host -ForegroundColor White " - Creating application pool $($appPoolConfig.Name)..."
        $pool = New-SPServiceApplicationPool -Name $appPoolConfig.Name -Account $ManagedAccountSearch
    }
    return $pool
}

#EndRegion

#Region Assign Certificate
Function AssignCert
{
	## Load IIS WebAdministration Snapin/Module
	## Inspired by http://stackoverflow.com/questions/1924217/powershell-load-webadministration-in-ps1-script-on-both-iis-7-and-iis-7-5
	Try
	{
		If ($OS -eq "Win2008")
		{
			If (!(Get-PSSnapin WebAdministration -ErrorAction SilentlyContinue))
			{	 
  				If (!(Test-Path $env:ProgramFiles\IIS\PowerShellSnapin\IIsConsole.psc1)) 
				{
					Start-Process -Wait -NoNewWindow -FilePath msiexec.exe -ArgumentList "/i `"$bits\PrerequisiteInstallerFiles\iis7psprov_x64.msi`" /passive /promptrestart"
				}
				Add-PSSnapin WebAdministration
			}
		}
		Else ## Win2008R2
		{ 
  			Import-Module WebAdministration
		}
	}
	Catch
	{
		Write-Host -ForegroundColor White " - Could not load IIS Administration module."
	}
	Write-Host -ForegroundColor White " - Assigning certificate to site `"https://$SSLHostHeader`:$SSLPort`""
	Write-Host -ForegroundColor White " - Looking for existing `"$SSLHostHeader`" certificate to use..."
	$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -eq "CN=$SSLHostHeader"}
	If (!$Cert)
	{
		Write-Host -ForegroundColor White " - None found."
		$MakeCert = "$env:ProgramFiles\Microsoft Office Servers\14.0\Tools\makecert.exe"
		If (Test-Path "$MakeCert")
		{
			Write-Host -ForegroundColor White " - Creating new self-signed certificate..."
			Start-Process -NoNewWindow -Wait -FilePath "$MakeCert" -ArgumentList "-r -pe -n `"CN=$SSLHostHeader`" -eku 1.3.6.1.5.5.7.3.1 -ss My -sr localMachine -sky exchange -sp `"Microsoft RSA SChannel Cryptographic Provider`" -sy 12"
			$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -eq "CN=$SSLHostHeader"}
			$CertSubject = $Cert.Subject
		}
		Else 
		{
			Write-Host -ForegroundColor White " - `"$MakeCert`" not found."
			Write-Host -ForegroundColor White " - Looking for any machine-named certificates we can use..."
			## Select the first certificate with the most recent valid date
			$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -like "*$env:COMPUTERNAME"} | Sort-Object NotBefore -Desc | Select-Object -First 1
			If (!$Cert)
			{
				Write-Host -ForegroundColor White " - None found, skipping certificate creation."
			}
			Else {$CertSubject = $Cert.Subject}
		}
	}
	Else
	{
		$CertSubject = $Cert.Subject
		Write-Host -ForegroundColor White " - Certificate `"$CertSubject`" found."
	}
	If ($Cert)
	{
		## Export our certificate to a file, then import it to the Trusted Root Certification Authorites store so we don't get nasty browser warnings
		## This will actually only work if the Subject and the host part of the URL are the same
		## Borrowed from https://www.orcsweb.com/blog/james/powershell-ing-on-windows-server-how-to-import-certificates-using-powershell/
		Write-Host -ForegroundColor White " - Exporting `"$CertSubject`" to `"$SSLHostHeader.cer`"..."
		$Cert.Export("Cert") | Set-Content "$env:TEMP\$SSLHostHeader.cer" -Encoding byte
		$Pfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
		Write-Host -ForegroundColor White " - Importing `"$SSLHostHeader.cer`" to Local Machine\Root..."
		$Pfx.Import("$env:TEMP\$SSLHostHeader.cer")
		$Store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
		$Store.Open("MaxAllowed")
		$Store.Add($Pfx)
		$Store.Close()
		Write-Host -ForegroundColor White " - Assigning certificate `"$CertSubject`" to SSL-enabled site..."
		#Set-Location IIS:\SslBindings -ErrorAction Inquire
		$Cert | New-Item IIS:\SslBindings\0.0.0.0!$SSLPort -ErrorAction Inquire | Out-Null
		Write-Host -ForegroundColor White "- Certificate has been assigned to site `"https://$SSLHostHeader`:$SSLPort`""
	}
	Else {Write-Host -ForegroundColor White " - No certificates were found, and none could be created."}
	$Cert = $null
}
#EndRegion

#Region Miscellaneous/Utility Functions
# ===================================================================================
# Func: Load SharePoint Powershell Snapin
# Desc: Load SharePoint Powershell Snapin
# ===================================================================================
Function Load-SharePoint-Powershell
{
	If ((Get-PsSnapin |?{$_.Name -eq "Microsoft.SharePoint.PowerShell"})-eq $null)
	{
    	Write-Host -ForegroundColor White " - Loading SharePoint Powershell Snapin"
   		$PSSnapin = Add-PsSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue | Out-Null
	}
}

# ===================================================================================
# Func: ConvertTo-PlainText
# Desc: Convert string to secure phrase
#       Used (for example) to get the Farm Account password into plain text as input to provision the User Profile Sync Service
#       From http://www.vistax64.com/powershell/159190-read-host-assecurestring-problem.html
# ===================================================================================
Function ConvertTo-PlainText( [security.securestring]$secure )
{
	$marshal = [Runtime.InteropServices.Marshal]
	$marshal::PtrToStringAuto( $marshal::SecureStringToBSTR($secure) )
}

# ===================================================================================
# Func: Pause
# Desc: Wait for user to press a key - normally used after an error has occured
# ===================================================================================
Function Pause
{
	#From http://www.microsoft.com/technet/scriptcenter/resources/pstips/jan08/pstip0118.mspx
	Write-Host "Press any key to exit..."
	$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ===================================================================================
# Func: CheckSQLAccess
# Desc: Check the install account has the correct SQL database access
# Note: TODO see if better way to confirm specific roles
# ===================================================================================
Function CheckSQLAccess
{
    $script:DBServer = Get-DBServer $xmlinput
	Write-Host -ForegroundColor White " --------------------------------------------------------------"
	Write-Host -ForegroundColor White " - Checking access to SQL server (or instance) `"$DBServer`"..."
	$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
	$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
	$SqlConnection.ConnectionString = "Server=$DBServer;Database=master;Integrated Security=True"
	$SqlCmd.CommandText = "SELECT HAS_DBACCESS('master')"
	$SqlCmd.Connection = $SqlConnection
	$SqlCmd.CommandTimeout = 10
	Try
	{
		$SqlCmd.Connection.Open()
		$SqlCmd.ExecuteReader() | Out-Null
	}
	Catch
	{
		Write-Error $_
		Write-Warning " - Connection failed to SQL server or instance `"$DBServer`"!"
		Write-Warning " - Check the server (or instance) name, or verify rights for $env:USERDOMAIN\$env:USERNAME"
		$SqlCmd.Connection.Close()
		Pause
		break
	}	
	Write-Host -ForegroundColor White " - $env:USERDOMAIN\$env:USERNAME has access."
	Write-Host -ForegroundColor White " --------------------------------------------------------------"
	$SqlCmd.Connection.Close()
}
