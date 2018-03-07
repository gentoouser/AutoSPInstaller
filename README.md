# AutoSPInstaller
Automated SharePoint 2010/2013/2016 PowerShell-based installation script.

Customized version of https://autospinstaller.com/ to mount and upgrade older Content Databases 

- Main version of [AutoSPInstaller](https://github.com/brianlala/AutoSPInstaller)
- Download and Extract files
- Use https://autospinstaller.com/FarmConfiguration to create xml file
- Edit the xml to add your existing Content Databases
- The xml need to be added within the `<WebApplication>` tag
  ```
  <ExistingContentDatabases>
	 	<UpgradetoCliaims>true</UpgradetoCliaims>
		<UpgradeSiteCollections>true</UpgradeSiteCollections>
		<ContentDatabase>
			<DBName>WSS_Content_Root</DBName>
			<DBState>Disabled</DBState>
		</ContentDatabase>
   </ExistingContentDatabases> 
  ```
