# Synergy Replace Server
Monitor the Synergy Composer for critical server alerts.  If a critical alert is detected, look for an available server of the same hardware type and replace the failing server with an available server of the same type.

## Synergy_Replace_Server.ps1
The Synergy_Replace_Server script does the following:

* Connects to an HPE Synergy Composer (or HPE OneView instance)
* Every 10 seconds the tool will check for any new Critical alerts
* Identifies the compute module generating the alert
* Powers off the compute module
* Un-assigns the existing Server Profile from the Compute Module
* Assigns the Server Profile to an available Compute Module of the same Hardware Type
* Powers on the compute module

The required parameters on the command-line are:
```
Appliance              IPv4 Address of the Synergy Composer or OneView Instance
Username               Administrative User (Administrator)

The script will prompt for the Administrator's Password (not displayed in clear text)
```

# How to use the scripts
This PowerShell script requires the HPE OneView PowerShell library found here: https://github.com/HewlettPackard/POSH-HPOneView.

# Sample Command Syntax
Synergy_Replace_Server.ps1 -Appliance IP_ADDR -Username Administrator
