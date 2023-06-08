property _validInstance; _isCurrentProject; _isDefaultDestinationFolder; _noError : Boolean
property _projectFile : 4D.File
property _currentProjectPackage; _projectPackage; _structureFolder : 4D.Folder
property logs : Collection
property settings : Object

Class constructor($target : Text; $customSettings : Object)
	ON ERR CALL("onError"; ek global)
	
	var $settings : Object
	
	This.logs:=New collection
	This.settings:=New object()
	This.settings.includePaths:=New collection
	This.settings.deletePaths:=New collection
	
	If (File("/RESOURCES/"+$target+".json").exists)
		This._overrideSettings(JSON Parse(File("/RESOURCES/"+$target+".json").getText()))  // Loads target default settings
	End if 
	This._isDefaultDestinationFolder:=False
	
	$settings:=($customSettings#Null) ? $customSettings : New object()
	
	This._validInstance:=True
	This._isCurrentProject:=True
	This._projectFile:=File(Structure file(*); fk platform path)
	This._currentProjectPackage:=This._projectFile.parent.parent
	If (($settings#Null) && ($settings.projectFile#Null) && \
		((Value type($settings.projectFile)=Is object) && OB Instance of($settings.projectFile; 4D.File)) || \
		((Value type($settings.projectFile)=Is text) && ($settings.projectFile#"")))
		This._isCurrentProject:=False
		This._projectFile:=This._resolvePath($settings.projectFile; Folder(Folder("/PACKAGE/"; *).platformPath; fk platform path))
		If (Not(This._projectFile.exists))
			This._validInstance:=False
			This._log(New object(\
				"function"; "Class constuctor"; \
				"message"; "Project file doesn't exist, instanciated object is unusable."; \
				"severity"; Error message))
		End if 
	End if 
	
	This._projectPackage:=This._projectFile.parent.parent
	
	If (This._validInstance)
		This._overrideSettings($settings)
		If ((This.settings.buildName=Null) || (This.settings.buildName=""))
			This.settings.buildName:=This._projectFile.name
			This._log(New object(\
				"function"; "Settings checking"; \
				"message"; "Build name automatically defined."; \
				"severity"; Information message))
		End if 
		If (This.settings.destinationFolder=Null)
			This.settings.destinationFolder:=This._projectPackage.parent.folder(This._projectFile.name+"_Build/")
			This._isDefaultDestinationFolder:=True
			This._log(New object(\
				"function"; "Settings checking"; \
				"message"; "Destination folder automatically defined."; \
				"severity"; Information message))
		End if 
		This._log(New object(\
			"function"; "Class constuctor"; \
			"message"; "Class init successful."; \
			"severity"; Information message))
	End if 
	
	//MARK:-
Function _overrideSettings($settings : Object)
	
	var $entries : Collection
	var $entry; $currentAppInfo; $sourceAppInfo : Object
	
	$entries:=OB Entries($settings)
	For each ($entry; $entries)
		Case of 
			: ($entry.key="destinationFolder")
				This.settings.destinationFolder:=This._resolvePath($settings.destinationFolder; This._projectPackage)
				If (Not(OB Instance of(This.settings.destinationFolder; 4D.Folder)))
					This._validInstance:=False
				Else 
					This._validInstance:=This._checkDestinationFolder()
				End if 
				
			: ($entry.key="includePaths")
				This.settings.includePaths:=This.settings.includePaths.concat($settings.includePaths)
				
			: ($entry.key="iconPath")
				This.settings.iconPath:=This._resolvePath($settings.iconPath; This._currentProjectPackage)
				
			: ($entry.key="license")
				This.settings.license:=This._resolvePath($settings.license; Null)
				
			: ($entry.key="sourceAppFolder")
				If (Value type($settings.sourceAppFolder)=Is text)
					$settings.sourceAppFolder:=($settings.sourceAppFolder="@/") ? $settings.sourceAppFolder : $settings.sourceAppFolder+"/"
				End if 
				This.settings.sourceAppFolder:=This._resolvePath($settings.sourceAppFolder; Null)
				If ((This.settings.sourceAppFolder=Null) || (Not(OB Instance of(This.settings.sourceAppFolder; 4D.Folder)) || (Not(This.settings.sourceAppFolder.exists))))
					This._validInstance:=False
					This._log(New object(\
						"function"; "Source application folder checking"; \
						"message"; "Source application folder doesn't exist"; \
						"severity"; Error message); \
						"sourceAppFolder"; $settings.sourceAppFolder)
					
				Else   // Versions checking
					$sourceAppInfo:=(Is macOS) ? This.settings.sourceAppFolder.file("Contents/Info.plist").getAppInfo() : This.settings.sourceAppFolder.file("Resources/Info.plist").getAppInfo()
					$currentAppInfo:=(Is macOS) ? Folder(Application file; fk platform path).file("Contents/Info.plist").getAppInfo() : File(Application file; fk platform path).parent.file("Resources/Info.plist").getAppInfo()
					If (($sourceAppInfo.CFBundleVersion=Null) || ($currentAppInfo.CFBundleVersion=Null) || ($sourceAppInfo.CFBundleVersion#$currentAppInfo.CFBundleVersion))
						This._validInstance:=False
						This._log(New object(\
							"function"; "Source application version checking"; \
							"message"; "Source application version doesn't match to current application version"; \
							"severity"; Error message); \
							"sourceAppFolder"; $settings.sourceAppFolder)
					End if 
				End if 
				
			Else 
				This.settings[$entry.key]:=$entry.value
		End case 
	End for each 
	
	//MARK:-
Function _log($log : Object)
	
	This.logs.push($log)
	If (This.settings.logger#Null)
		This.settings.logger($log)
	End if 
	
	//MARK:-
Function _resolvePath($path : Variant; $baseFolder : 4D.Folder) : Object
	
	Case of 
		: ((Value type($path)=Is object) && (OB Instance of($path; 4D.File) || OB Instance of($path; 4D.Folder)))  // $path is a File or a Folder
			return $path
			
		: (Value type($path)=Is text)  // $path is a text
			var $absolutePath : Text
			var $absoluteFolder; $app : 4D.Folder
			
			$absoluteFolder:=$baseFolder
			Case of 
				: ($path="./@")  // Relative path inside $baseFolder
					$path:=Substring($path; 3)
					$absolutePath:=$absoluteFolder.path+$path
				: ($path="../@")  // Relative path outside $baseFolder
					While ($path="../@")
						$absoluteFolder:=$absoluteFolder.parent
						$path:=Substring($path; 4)
					End while 
					$absolutePath:=$absoluteFolder.path+$path
				Else   // Absolute path or custom fileSystem
					Case of 
						: ($path="/4DCOMPONENTS/@")
							$app:=(Is macOS) ? Folder(Application file; fk platform path).folder("Contents/Components") : File(Application file; fk platform path).parent.folder("Components")
							$absolutePath:=$app.path+Substring($path; 15)
							
						: (($path="") | ($path="/"))  // Base folder
							$absolutePath:=$baseFolder.path
							
						Else   // Absolute path or baseFolder subpath
							
							var $pathExists : Boolean
							$pathExists:=($path="@/") ? Folder(Folder($path; *).platformPath; fk platform path).exists : File(File($path; *).platformPath; fk platform path).exists
							$absolutePath:=($pathExists) ? $path : Choose($baseFolder#Null; $absoluteFolder.path; "")+$path
					End case 
					
			End case 
			
			return ($absolutePath="@/") ? Folder(Folder($absolutePath; *).platformPath; fk platform path) : File(File($absolutePath; *).platformPath; fk platform path)
			
		Else 
			return Null
	End case 
	
	//MARK:-
Function _checkDestinationFolder() : Boolean
	
	This._noError:=True
	
	If (This.settings.destinationFolder.exists)  // Delete destination folder content if exists
		This.settings.destinationFolder.delete(fk recursive)
	End if 
	
	If (Not(This.settings.destinationFolder.create()))
		This._log(New object(\
			"function"; "Destination folder checking"; \
			"message"; "Destination folder doesn't exist and can't be created"; \
			"severity"; Error message); \
			"destinationFolder"; This.settings.destinationFolder.path)
		return False
	End if 
	
	return This._noError
	
	//MARK:-
Function _compileProject() : Boolean
	
	If (This._validInstance)
		var $compilation : Object
		
		If (Undefined(This.settings.compilerOptions))
			$compilation:=(This._isCurrentProject) ? Compile project : Compile project(This._projectFile)
		Else 
			$compilation:=(This._isCurrentProject) ? Compile project(This.settings.compilerOptions) : Compile project(This._projectFile; This.settings.compilerOptions)
		End if 
		
		If ($compilation.success)
			This._log(New object(\
				"function"; "Compilation"; \
				"message"; "Compilation successful."; \
				"severity"; Information message; \
				"result"; $compilation))
			return True
		Else 
			This._log(New object(\
				"function"; "Compilation"; \
				"message"; "Compilation failed."; \
				"severity"; Error message; \
				"result"; $compilation))
		End if 
	End if 
	
	//MARK:-
Function _createStructure() : Boolean
	
	var $structureFolder; $librariesFolder : 4D.Folder
	var $deletePaths : Collection
	var $result : Boolean
	
	If (This._validInstance)
		
		$structureFolder:=This._structureFolder
		
		// Copy Project Folder
		If ($structureFolder.exists)  // Empty the structure folder
			$structureFolder.delete(fk recursive)
		End if 
		$structureFolder.create()
		
		This._projectFile.parent.copyTo($structureFolder; fk overwrite)
		
		// Remove source methods
		$deletePaths:=New collection
		$deletePaths.push($structureFolder.folder("Project/Sources/Classes/"))
		$deletePaths.push($structureFolder.folder("Project/Sources/DatabaseMethods/"))
		$deletePaths.push($structureFolder.folder("Project/Sources/Methods/"))
		$deletePaths.push($structureFolder.folder("Project/Sources/Triggers/"))
		$deletePaths.push($structureFolder.folder("Project/Trash/"))
		
		If (This._deletePaths($deletePaths))
			$deletePaths:=$structureFolder.files(fk recursive).query("extension =:1"; ".4DM")  // Table Form, Form and Form object methods
			If (($deletePaths.length>0) || (This._deletePaths($deletePaths)))
				// Copy Libraries folder
				$librariesFolder:=This._projectPackage.folder("Libraries")
				If (($librariesFolder.exists) && ($librariesFolder.files.length))
					$librariesFolder.copyTo($structureFolder; fk overwrite)
				End if 
				return True
			End if 
		End if 
	End if 
	
	//MARK:-
Function _includePaths($pathsObj : Collection) : Boolean
	
	var $pathObj; $sourcePath; $destinationPath : Object
	
	If (($pathsObj#Null) && ($pathsObj.length>0))
		For each ($pathObj; $pathsObj)
			
			If (Undefined($pathObj.source))
				This._log(New object(\
					"function"; "Paths include"; \
					"message"; "Collection.source must contain Posix text paths, 4D.File objects or 4D.Folder objects"; \
					"severity"; Error message))
				return False
			Else 
				If ((Value type($pathObj.source)=Is text) || (OB Instance of($pathObj.source; 4D.Folder)) || (OB Instance of($pathObj.source; 4D.File)))
					$sourcePath:=This._resolvePath($pathObj.source; This._currentProjectPackage)
				Else 
					This._log(New object(\
						"function"; "Paths include"; \
						"message"; "Collection.source must contain Posix text paths, 4D.File objects or 4D.Folder objects"; \
						"severity"; Error message))
					return False
				End if 
			End if 
			
			If (Undefined($pathObj.destination))
				$destinationPath:=This._structureFolder
			Else 
				If ((Value type($pathObj.destination)=Is text) || (OB Instance of($pathObj.destination; 4D.Folder)))
					$destinationPath:=This._resolvePath($pathObj.destination; This._structureFolder)
				Else 
					This._log(New object(\
						"function"; "Paths include"; \
						"message"; "Collection.destination must contain Posix text paths or 4D.Folder objects"; \
						"severity"; Error message))
					return False
				End if 
			End if 
			
			If (Not($destinationPath.exists) && Not($destinationPath.create()))
				This._log(New object(\
					"function"; "Paths include"; \
					"message"; "Destination folder doesn't exist and can't be created"; \
					"severity"; Error message; \
					"destinationPath"; $destinationPath.path))
				return False
			End if 
			If ($sourcePath.exists)
				$destinationPath:=$sourcePath.copyTo($destinationPath; fk overwrite)
				If ($destinationPath.exists)
					This._log(New object(\
						"function"; "Paths include"; \
						"message"; "Path copied"; \
						"severity"; Information message; \
						"sourcePath"; $sourcePath.path; \
						"destinationPath"; $destinationPath.path))
				Else 
					This._log(New object(\
						"function"; "Paths include"; \
						"message"; "Path doesn't exist"; \
						"severity"; Warning message; \
						"sourcePath"; $sourcePath.path; \
						"destinationPath"; $destinationPath.path))
				End if 
			Else 
				This._log(New object(\
					"function"; "Paths include"; \
					"message"; "Path doesn't exist"; \
					"severity"; Warning message; \
					"sourcePath"; $sourcePath.path))
			End if 
		End for each 
	Else 
		This._log(New object(\
			"function"; "Paths include"; \
			"message"; "Empty paths collection"; \
			"severity"; Information message))
	End if 
	
	return True
	
	//MARK:-
Function _deletePaths($paths : Collection) : Boolean
	
	var $path : Variant
	var $deletePath : Object
	
	If (($paths#Null) && ($paths.length>0))
		For each ($path; $paths)
			
			If ((Value type($path)=Is text) || ((OB Instance of($path; 4D.Folder)) || (OB Instance of($path; 4D.File))))
				$deletePath:=This._resolvePath($path; This._structureFolder)
			Else 
				This._log(New object(\
					"function"; "Paths delete"; \
					"message"; "Collection must contain Posix text paths, 4D.File objects or 4D.Folder objects"; \
					"severity"; Error message))
				return False
			End if 
			
			If ($deletePath.exists)
				$deletePath.delete(fk recursive)
				This._log(New object(\
					"function"; "Paths delete"; \
					"message"; "Path deleted"; \
					"severity"; Information message; \
					"path"; $deletePath.path))
			Else 
				This._log(New object(\
					"function"; "Paths delete"; \
					"message"; "Path doesn't exist"; \
					"severity"; Warning message; \
					"path"; $deletePath.path))
			End if 
		End for each 
	Else 
		This._log(New object(\
			"function"; "Paths delete"; \
			"message"; "Empty paths collection"; \
			"severity"; Information message))
	End if 
	return True
	
	//MARK:-
Function _create4DZ() : Boolean
	
	var $structureFolder : 4D.Folder
	var $zipStructure : Object
	var $return : Object
	
	If ((This._validInstance) && (This.settings.packedProject))
		$structureFolder:=This._structureFolder
		$zipStructure:=New object
		$zipStructure.files:=New collection($structureFolder.folder("Project"))
		$zipStructure.encryption:=(This.settings.obfuscated) ? -1 : ZIP Encryption none
		$return:=ZIP Create archive($zipStructure; $structureFolder.file(This.settings.buildName+".4DZ"))
		If ($return.success)
			$structureFolder.folder("Project").delete(Delete with contents)
		Else 
			This._log(New object(\
				"function"; "Package compression"; \
				"message"; "Compression failed."; \
				"severity"; Error message; \
				"result"; $return))
			return False
		End if 
	End if 
	return True
	
Function _copySourceApp() : Boolean
	This._noError:=True
	This.settings.sourceAppFolder.copyTo(This.settings.destinationFolder.parent; This.settings.destinationFolder.fullName)
	return This._noError
	
	//MARK:-
Function _excludeModules() : Boolean
	var $excludedModule; $path; $basePath : Text
	var $optionalModulesFile : 4D.File
	var $optionalModules : Object
	var $paths; $modules : Collection
	
	This._noError:=True
	
	If ((This.settings.excludeModules#Null) && (This.settings.excludeModules.length>0))
		$optionalModulesFile:=(Is macOS) ? Folder(Application file; fk platform path).file("Contents/Resources/BuildappOptionalModules.json") : File(Application file; fk platform path).parent.file("Resources/BuildappOptionalModules.json")
		If ($optionalModulesFile.exists)
			$paths:=New collection
			$basePath:=(Is macOS) ? This.settings.destinationFolder.path+"Contents/" : This.settings.destinationFolder.path
			$optionalModules:=JSON Parse($optionalModulesFile.getText())
			For each ($excludedModule; This.settings.excludeModules)
				$modules:=$optionalModules.modules.query("name = :1"; $excludedModule)
				If ($modules.length>0)
					If (($modules[0].foldersArray#Null) && ($modules[0].foldersArray.length>0))
						For each ($path; $modules[0].foldersArray)
							$paths.push($basePath+$path+"/")
						End for each 
					End if 
					If (($modules[0].filesArray#Null) && ($modules[0].filesArray.length>0))
						For each ($path; $modules[0].filesArray)
							$paths.push($basePath+$path)
						End for each 
					End if 
				End if 
			End for each 
			This._deletePaths($paths)
		Else 
			This._log(New object(\
				"function"; "Modules exclusion"; \
				"message"; "Unable to find the modules file: "+$optionalModulesFile.path; \
				"severity"; Error message))
			return False
		End if 
	End if 
	
	return This._noError
	
	//MARK:-
Function _setAppOptions() : Boolean
	var $appInfo; $exeInfo : Object
	var $infoFile; $exeFile; $manifestFile : 4D.File
	var $identifier : Text
	
	This._noError:=True
	
	$infoFile:=(Is macOS) ? This.settings.destinationFolder.file("Contents/Info.plist") : This.settings.destinationFolder.file("Resources/Info.plist")
	
	If ($infoFile.exists)
		$appInfo:=New object(\
			"com.4D.BuildApp.ReadOnlyApp"; "true"; \
			"com.4D.BuildApp.LastDataPathLookup"; Choose((This.settings.lastDataPathLookup="ByAppName") | (This.settings.lastDataPathLookup="ByAppPath"); This.settings.lastDataPathLookup; "ByAppName"); \
			"DataFileConversionMode"; "0"\
			)
		$appInfo.SDIRuntime:=((This.settings.useSDI#Null) && This.settings.useSDI) ? "1" : "0"
		
		If (Is macOS)
			$appInfo.CFBundleName:=This.settings.buildName
			$appInfo.CFBundleDisplayName:=This.settings.buildName
			$appInfo.CFBundleExecutable:=This.settings.buildName
			$identifier:=((This.settings.versioning.companyName#Null) && (This.settings.versioning.companyName#"")) ? This.settings.versioning.companyName : "com.4d"
			$identifier+="."+This.settings.buildName
			$appInfo.CFBundleIdentifier:=$identifier
		Else 
			$exeInfo:=New object("ProductName"; This.settings.buildName)
		End if 
		
		If (This.settings.iconPath#Null)  // Set icon
			If (This.settings.iconPath.exists)
				If (Is macOS)
					$appInfo.CFBundleIconFile:=This.settings.iconPath.fullName
					This.settings.iconPath.copyTo(This.settings.destinationFolder.folder("Contents/Resources/"))
					This.settings.iconPath.copyTo(This.settings.destinationFolder.folder("Contents/Resources/Images/WindowIcons/"); "windowIcon_205.icns"; fk overwrite)
				Else   // Windows
					$exeInfo.WinIcon:=This.settings.iconPath
				End if 
			Else 
				This._log(New object(\
					"function"; "Icon integration"; \
					"message"; "Icon file doesn't exist: "+This.settings.iconPath.path; \
					"severity"; Error message))
			End if 
		End if 
		
		If (This.settings.versioning#Null)  // Set version info
			If (Is macOS)
				If (This.settings.versioning.version#Null)
					$appInfo.CFBundleVersion:=This.settings.versioning.version
					$appInfo.CFBundleShortVersionString:=This.settings.versioning.version
				End if 
				If (This.settings.versioning.copyright#Null)
					$appInfo.NSHumanReadableCopyright:=This.settings.versioning.copyright
					// Force macOS to get copyright from info.plist file instead of localized strings file
					var $subFolder : 4D.Folder
					var $infoPlistFile : 4D.File
					var $resourcesSubFolders : Collection
					var $fileContent : Text
					$resourcesSubFolders:=This.settings.destinationFolder.folder("Contents/Resources/").folders()
					For each ($subFolder; $resourcesSubFolders)
						If ($subFolder.extension=".lproj")
							$infoPlistFile:=$subFolder.file("InfoPlist.strings")
							If ($infoPlistFile.exists)
								$fileContent:=$infoPlistFile.getText()
								$fileContent:=Replace string($fileContent; "CFBundleGetInfoString ="; "CF4DBundleGetInfoString ="; 1)
								$fileContent:=Replace string($fileContent; "NSHumanReadableCopyright ="; "NS4DHumanReadableCopyright ="; 1)
								$infoPlistFile.setText($fileContent)
							End if 
						End if 
					End for each 
				End if 
				//If (This.settings.versioning.creator#Null)
				//$appInfo._unknown:=This.settings.versioning.creator
				//End if 
				//If (This.settings.versioning.comment#Null)
				//$appInfo.Comment:=This.settings.versioning.comment
				//End if 
				//If (This.settings.versioning.companyName#Null)
				//$appInfo.CompanyName:=This.settings.versioning.companyName
				//End if 
				//If (This.settings.versioning.fileDescription#Null)
				//$appInfo.FileDescription:=This.settings.versioning.fileDescription
				//End if 
				//If (This.settings.versioning.internalName#Null)
				//$appInfo.InternalName:=This.settings.versioning.internalName
				//End if 
				//If (This.settings.versioning.legalTrademark#Null)
				//$appInfo.LegalTrademarks:=This.settings.versioning.legalTrademark
				//End if 
				//If (This.settings.versioning.privateBuild#Null)
				//$appInfo.PrivateBuild:=This.settings.versioning.privateBuild
				//End if 
				//If (This.settings.versioning.specialBuild#Null)
				//$appInfo.SpecialBuild:=This.settings.versioning.specialBuild
				//End if 
				
			Else   // Windows
				If (This.settings.versioning.version#Null)
					$exeInfo.ProductVersion:=This.settings.versioning.version  //
				End if 
				If (This.settings.versioning.copyright#Null)
					$exeInfo.LegalCopyright:=This.settings.versioning.copyright  //
				End if 
				//If (This.settings.versioning.creator#Null)
				//$exeInfo.Creator:=This.settings.versioning.creator
				//End if 
				//If (This.settings.versioning.comment#Null)
				//$exeInfo.Comment:=This.settings.versioning.comment
				//End if 
				If (This.settings.versioning.companyName#Null)
					$exeInfo.CompanyName:=This.settings.versioning.companyName
				End if 
				If (This.settings.versioning.fileDescription#Null)
					$exeInfo.FileDescription:=This.settings.versioning.fileDescription  //
				End if 
				If (This.settings.versioning.internalName#Null)
					$exeInfo.InternalName:=This.settings.versioning.internalName
				End if 
				If (This.settings.versioning.legalTrademark#Null)
					$exeInfo.LegalTrademarks:=This.settings.versioning.legalTrademark  // No defined in setAppInfo
				End if 
				//If (This.settings.versioning.privateBuild#Null)
				//$exeInfo.PrivateBuild:=This.settings.versioning.privateBuild
				//End if 
				//If (This.settings.versioning.specialBuild#Null)
				//$exeInfo.SpecialBuild:=This.settings.versioning.specialBuild
				//End if 
			End if 
		End if 
		
		$infoFile.setAppInfo($appInfo)
		
		If ($exeInfo#Null)
			$exeFile:=This.settings.destinationFolder.file(This.settings.buildName+".exe")
			If ($exeFile.exists)
				$exeFile.setAppInfo($exeInfo)
			Else 
				This._log(New object(\
					"function"; "Setting app options"; \
					"message"; "Exe file doesn't exist: "+$exeFile.path; \
					"severity"; Warning message))
				return False
			End if 
		End if 
		
	Else 
		This._log(New object(\
			"function"; "Setting app options"; \
			"message"; "Info.plist file doesn't exist: "+$infoFile.path; \
			"severity"; Warning message))
		return False
	End if 
	
	If (Is Windows)
		$manifestFile:=((This.settings.startElevated#Null) && (This.settings.startElevated))\
			 ? This.settings.destinationFolder.file("Resources/Updater/elevated.manifest")\
			 : This.settings.destinationFolder.file("Resources/Updater/normal.manifest")
		$manifestFile.copyTo(This.settings.destinationFolder.folder("Resources/Updater/"); "Updater.exe.manifest"; fk overwrite)
		This.settings.destinationFolder.file("Resources/Updater/elevated.manifest").delete()
		This.settings.destinationFolder.file("Resources/Updater/normal.manifest").delete()
	End if 
	
	return This._noError
	
	//MARK:-
Function _generateLicense() : Boolean
	var $status : Object
	
	If ((This.settings.license#Null) && (This.settings.license.exists))
		$status:=Create deployment license(This.settings.destinationFolder; This.settings.license)
		If ($status.success)
			return True
		Else 
			This._log(New object(\
				"function"; "Deployment license creation"; \
				"message"; "Deployment license creation failed"; \
				"severity"; Error message; \
				"result"; $status))
		End if 
	Else 
		This._log(New object(\
			"function"; "Deployment license creation"; \
			"message"; "License file doesn't exist: "+Choose(This.settings.license#Null; This.settings.license.path; "Undefined"); \
			"severity"; Error message))
	End if 
	
	//MARK:-
Function _sign() : Boolean
	
	If (Is macOS && (This.settings.signApplication#Null))
		//Default values initialization
		This.settings.signApplication.macSignature:=(This.settings.signApplication.macSignature#Null) ? This.settings.signApplication.macSignature : False
		This.settings.signApplication.macCertificate:=(This.settings.signApplication.macCertificate#Null) ? This.settings.signApplication.macCertificate : ""
		This.settings.signApplication.adHocSignature:=(This.settings.signApplication.adHocSignature#Null) ? This.settings.signApplication.adHocSignature : True
		
		If (This.settings.signApplication.macSignature || This.settings.signApplication.adHocSignature)
			var $script; $entitlements : 4D.File
			$script:=Folder(Application file; fk platform path).file("Contents/Resources/SignApp.sh")
			$entitlements:=Folder(Application file; fk platform path).file("Contents/Resources/4D.entitlements")
			If ($script.exists && $entitlements.exists)
				var $commandLine; $certificateName : Text
				var $signatureWorker : 4D.SystemWorker
				
				$certificateName:=(Not(This.settings.signApplication.macSignature) && This.settings.signApplication.adHocSignature) ? "-" : This.settings.signApplication.macCertificate  // If nAdHocSignature, the certificate name shall be '-'
				
				If ($certificateName#"")
					
					$commandLine:="'"
					$commandLine+=$script.path+"' '"
					$commandLine+=$certificateName+"' '"
					$commandLine+=This.settings.destinationFolder.path+"' '"
					$commandLine+=$entitlements.path+"'"
					
					$signatureWorker:=4D.SystemWorker.new($commandLine)
					$signatureWorker.wait(120)
					
					If ($signatureWorker.terminated)
						If ($signatureWorker.exitCode=0)
							This._log(New object(\
								"function"; "Signature"; \
								"message"; "Signature successful."; \
								"severity"; Information message; \
								"signatureReturn"; $signatureWorker.response))
						Else 
							This._log(New object(\
								"function"; "Signature"; \
								"message"; "Signature error."; \
								"severity"; Error message; \
								"signatureReturn"; $signatureWorker.response))
							return False
						End if 
					Else 
						This._log(New object(\
							"function"; "Signature"; \
							"message"; "Signature timeout."; \
							"severity"; Error message))
						return False
					End if 
				Else 
					This._log(New object(\
						"function"; "Signature"; \
						"message"; "No certificate defined."; \
						"severity"; Error message))
					return False
				End if 
			Else 
				This._log(New object(\
					"function"; "Signature"; \
					"message"; "Signature files are missing."; \
					"severity"; Error message; \
					"script"; $script.path; \
					"entitlements"; $entitlements.path))
				return False
			End if 
		End if 
	End if 
	return True
	