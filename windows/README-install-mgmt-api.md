# s1-agent-install-mgmt-api.ps1
A basic "helper script" to automate the download, installation, association to a site and activation of SentinelOne Agents on Windows.

## Detailed Description
This script can be downloaded and executed manually or via script.  

Note: The concept of this script could easily be modified for usage within configuration management tools (Ansible, Chef, Puppet, etc.)

For more information, please refer to [Installing the Windows Agent](https://community.sentinelone.com/s/article/000005521)

# Prerequisites

n/a

# Manual Usage
1. Download the 's1-agent-install-mgmt-api.ps1' script
2. Execute the script with Administrator privileges (passing arguments for S1_CONSOLE_PREFIX, API_KEY, SITE_TOKEN and VERSION_STATUS).  For example:
```
s1-agent-install-mgmt-api.ps1 usea1-console eyJraWQiOiJ0abcdefghij0123456789bGciOiJFUzI1NiJ9.eyJzdWIiOiJzZXJ2aWNldXNlci01MzUyMabcdefghij0123456789TdlMC05ZjcxZGMyNDY4NzdAbWdtdC0xMTYzMy5zZW50aW5lbG9uZS5uZXQiLCJpc3MiOiJhdXRobi11cy1lYXN0LTEtcHJvZCIsImRlcGxveW1lbnRfaWQiOiIxMTYzMyIsInR5cGUiOiJ1c2VyIiwiZXhwIjoxNzA4NTU2MzY5Labcdefghij0123456789S0wYjZjLTRlYTItYWM1ZC04YTlmNjdmYjA2ZTQifQ.755-K8b4Hjf2pJvKfPLsVPDDjRZpJVqKX1gBsZ65O4rjI3nbbnwcVn9rv6_8eDd_u_rjRqpob3unYEevMnYHGA eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS1jb25zb2xlLnNlbnRpbmVsb25lLm5ldCIsICJ1dWlkX2dlbiI6ICJhYTBkMmU1NWQ0NWE1YzBjIiwgInNhbXBsZV9kYXRhIjogImRvIG5vdCB1c2UifQo= GA
```

# Usage within AWS EC2 User Data
When manually launching a new EC2 Instance... 

During 'Step 3: Configure Instance Details', Copy/Paste the following into the 'User data' text area.


Be sure to replace the S1_CONSOLE_PREFIX (ie: usea1-console), API_KEY, SITE_TOKEN and VERSION_STATUS (ie: GA or EA) values with appropriate values:

## Windows-based instances
```
<powershell>
Set-ExecutionPolicy Unrestricted
(new-object Net.WebClient).DownloadFile("https://raw.githubusercontent.com/s1community/install-tools/main/windows/s1-agent-install-mgmt-api.ps1", "$env:TEMP\s1-agent-install-mgmt-api.ps1") 
& "$env:TEMP\s1-agent-install-mgmt-api.ps1" S1_CONSOLE_PREFIX API_KEY SITE_TOKEN VERSION_STATUS
</powershell>
<runAsLocalSystem>true</runAsLocalSystem>
```

# Usage within GCP Compute Engine

## Windows-based instances
When manually creating a new Compute Engine Windows Server instance, expand "Advanced Options (Networking, disks, security, management, sole-tenancy)" and then expand the Management subsection.  

Create new Metadata with "Key 1" set to `sysprep-specialize-script-ps1` and Copy/Paste the following into the "Value 1" textarea.

Be sure to replace the S1_CONSOLE_PREFIX (ie: usea1-console), API_KEY, SITE_TOKEN and VERSION_STATUS (ie: GA or EA) values with appropriate values:
```
Set-ExecutionPolicy Unrestricted -Force
(new-object Net.WebClient).DownloadFile("https://raw.githubusercontent.com/s1community/install-tools/main/windows/s1-agent-install-mgmt-api.ps1", "$env:TEMP\s1-agent-install-mgmt-api.ps1")
& "$env:TEMP\s1-agent-install-mgmt-api.ps1" S1_CONSOLE_PREFIX API_KEY SITE_TOKEN VERSION_STATUS
```
