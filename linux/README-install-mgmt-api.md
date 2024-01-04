# s1-agent-install-mgmt-api.sh
A basic "helper script" to automate the download, installation, association to a site and activation of SentinelOne Agents on Linux.

## Detailed Description
This script can be downloaded and executed manually or via script.  

Note: The concept of this script could easily be modified for usage within configuration management tools (Ansible, Chef, Puppet, etc.)

For more information, please refer to [Installing the Linux Agent](https://community.sentinelone.com/s/article/000004908)

# Prerequisites
You must have `curl` installed on your target Linux host

# Manual Usage
1. Download the 's1-agent-install-mgmt-api.sh' script
2. Make it executeable
```
sudo chmod +x s1-agent-install-mgmt-api.sh
```
3. Execute the script with root privileges (passing arguments for S1_CONSOLE_PREFIX, API_KEY, SITE_TOKEN and VERSION_STATUS).  For example:
```
sudo ./s1-agent-install-mgmt-api.sh usea1-console eEBKU8tXIEaDy4vezc9MHeru6ElrA3pJaNIY2eg7adzMfQYGYX3YRJ3x7h0fFF7eFxY9HKtQzHZR3FDi eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS1jb25zb2xlLnNlbnRpbmVsb25lLm5ldCIsICJ1dWlkX2dlbiI6ICJhYTBkMmU1NWQ0NWE1YzBjIiwgInNhbXBsZV9kYXRhIjogImRvIG5vdCB1c2UifQo= GA
```

# Usage within AWS EC2 User Data
When manually launching a new EC2 Instance... 

During 'Step 3: Configure Instance Details', Copy/Paste the following into the 'User data' text area.


Be sure to replace the S1_CONSOLE_PREFIX (ie: usea1-console), API_KEY, SITE_TOKEN and VERSION_STATUS (ie: GA or EA) values with appropriate values:
## Linux-based instances
```
#!/bin/bash
sudo curl -L "https://raw.githubusercontent.com/s1community/install-tools/main/linux/s1-agent-install-mgmt-api.sh" -o s1-agent-install-mgmt-api.sh
sudo chmod +x s1-agent-install-mgmt-api.sh
sudo ./s1-agent-install-mgmt-api.sh S1_CONSOLE_PREFIX API_KEY SITE_TOKEN VERSION_STATUS
```
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
## Linux-based instances
When manually creating a new Compute Engine instance, expand "Advanced Options (Networking, disks, security, management, sole-tenancy)" and then expand the Management subsection.  Copy/Paste the following into the Automation 'Startup script' textarea.

Be sure to replace the S1_CONSOLE_PREFIX (ie: usea1-console), API_KEY, SITE_TOKEN and VERSION_STATUS (ie: GA or EA) values with appropriate values:
```
#!/bin/bash
sudo curl -L "https://raw.githubusercontent.com/s1community/install-tools/main/linux/s1-agent-install-mgmt-api.sh" -o s1-agent-install-mgmt-api.sh
sudo chmod +x s1-agent-install-mgmt-api.sh
sudo ./s1-agent-install-mgmt-api.sh S1_CONSOLE_PREFIX API_KEY SITE_TOKEN VERSION_STATUS
```
## Windows-based instances
When manually creating a new Compute Engine Windows Server instance, expand "Advanced Options (Networking, disks, security, management, sole-tenancy)" and then expand the Management subsection.  

Create new Metadata with "Key 1" set to `sysprep-specialize-script-ps1` and Copy/Paste the following into the "Value 1" textarea.

Be sure to replace the S1_CONSOLE_PREFIX (ie: usea1-console), API_KEY, SITE_TOKEN and VERSION_STATUS (ie: GA or EA) values with appropriate values:
```
Set-ExecutionPolicy Unrestricted -Force
(new-object Net.WebClient).DownloadFile("https://raw.githubusercontent.com/s1community/install-tools/main/windows/s1-agent-install-mgmt-api.ps1", "$env:TEMP\s1-agent-install-mgmt-api.ps1")
& "$env:TEMP\s1-agent-install-mgmt-api.ps1" S1_CONSOLE_PREFIX API_KEY SITE_TOKEN VERSION_STATUS
```

# Usage within Azure Virtual Machines
When manually creating a new Virtual Machine, in the 'Advanced' section of the 'Create a virtual machine' wizard, Copy/Paste the following cloud-init script.
Be sure to replace the S1_CONSOLE_PREFIX (ie: usea1-console), API_KEY, SITE_TOKEN and VERSION_STATUS (ie: GA or EA) values with appropriate values:
```
#cloud-config
write_files:
  - path: /tmp/s1-agent-helper-install.sh
    permissions: 0755
    content: |
      #!/bin/bash
      curl https://raw.githubusercontent.com/s1community/install-tools/main/linux/s1-agent-install-mgmt-api.sh -o /tmp/s1-agent-install-mgmt-api.sh
      chmod 755 /tmp/s1-agent-install-mgmt-api.sh
      /tmp/s1-agent-install-mgmt-api.sh S1_CONSOLE_PREFIX API_KEY SITE_TOKEN VERSION_STATUS
runcmd:
  - /tmp/s1-agent-helper-install.sh
```

