 #Requires -RunAsAdministrator

 $s1_mgmt_url =  (Get-SSMParameter -Name "S1_MGMT_URL" -WithDecryption $True).Value
 $api_key =  (Get-SSMParameter -Name "S1_API_KEY" -WithDecryption $True).Value
 $site_token =  (Get-SSMParameter -Name "S1_SITE_TOKEN" -WithDecryption $True).Value
 $version_status = (Get-SSMParameter -Name "S1_VERSION_STATUS" -WithDecryption $True).Value
 
 # Show how the input parameters will be used
 write-output ""
 write-output "Console:             $s1_console_prefix"
 write-output "Version Status:      $version_status"
 Write-Output "mgmt url:            $s1_mgmt_url"
 $api_endpoint = "/web/api/v2.1/update/agent/packages"
 $agent_file_name = ""
 $agent_download_link = ""
 $agent_package_major_version = ""
 
 # Basic sanity checks for input parameters
 if (-Not ($api_key.Length -gt 79)) {
     Write-Output "API Keys are generally 80 to 430 characters long and are alphanumeric."
     exit 1
 }
 
 if (-Not ($site_token.Length -gt 90)) {
     Write-Output "Site Tokens are generally 90 characters or longer and are ASCII encoded."
     exit 1
 }
 
 if ($version_status -ne "GA" -and $version_status -ne "EA") {
     Write-Output "Invalid format for VERSION_STATUS: $version_status"
     Write-Output "The value of VERSION_STATUS must be either 'GA' or 'EA'"
     exit 1
 }
 
 # Concatenate the Management Console URL with API Endpoint for Agent Packages
 $uri = $s1_mgmt_url + $api_endpoint
 
 # Convert Agent version status to lowercase (for usage in the upcoming API query)
 $version_status = $version_status.ToLower()
 
 # Check if we need a 32 or 64bit package
 $osArch = "64 bit"
 if($env:PROCESSOR_ARCHITECTURE -eq "x86"){$osArch = "32 bit"}
 
 # Configure HTTP header for API Calls
 $apiHeaders = @{"Authorization"="APIToken $api_key"}
 
 # The body contains parameters to search for packages with .exe file extensions.. ordering by latest major version.
 $body = @{
     "limit"=10
     "platformTypes"="windows"
     "countOnly"="false"
     "sortBy"="majorVersion"
     "fileExtension"=".exe"
     "sortOrder"="desc"
     "osArches"=$osArch
     "status"=$version_status
     }
 
 # Query the S1 API
 $response = Invoke-RestMethod -Uri $uri -Headers $apiHeaders -Method Get -ContentType "application/json" -Body $body
 
 # Store the response data as a list of objects
 $packages = $response.data
 
 # Find the package that matches our criteria and record the file name and download link.
 #Note: "$version_status*"" will match either GA or GA-SP1, GA-SP2, etc
 foreach ($package in $packages) {
     if ($package.status -like "$version_status*") {
         $agent_download_link = $package.link
         $agent_file_name = $package.fileName
         $agent_package_major_version = $package.majorVersion
         break
     }
 }
 
 # Show which file name was selected and its download link.
 Write-Output "Agent File Name:     $agent_file_name"
 Write-Output "Agent Download Link: $agent_download_link"
 write-output ""
 
 # Now that we have the download link and file name.  Download the package to a TEMP directory.
 $wc = New-Object System.Net.WebClient
 $wc.Headers['Authorization'] = "APIToken $api_key"
 $wc.DownloadFile($agent_download_link, "$env:TEMP\$agent_file_name")
 
 # If the agent package is version 22.1+, use the new CLI installation syntax
 if ($agent_package_major_version -ge "22.1") {
     # Execute using newer cli flags
     if($auto_reboot -eq "True") {
         # Execute the package with the quiet option and force restart
         & "$env:TEMP\$agent_file_name" -t $site_token -q -b
     }
     else {
         # Execute the package with the quiet option and do NOT restart
         & "$env:TEMP\$agent_file_name" -t $site_token -q
     }
 }
 else {
     #Execute the older EXE package
     if($auto_reboot -eq "True") {
         # Execute the package with the quiet option and force restart
         & "$env:TEMP\$agent_file_name" /SITE_TOKEN=$site_token /quiet /reboot
     }
     else {
         # Execute the package with the quiet option and do NOT restart
         & "$env:TEMP\$agent_file_name" /SITE_TOKEN=$site_token /quiet /norestart
     }
 } 
 