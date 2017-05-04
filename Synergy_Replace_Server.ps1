##############################################################################
# Synergy_Replace_Server.ps1
#
#   Monitor the Synergy Composer for critical server alerts.  
#   If an alert is detected, look for an available server 
#   of the same hardware type and replace the failing server
#   with an available server of the same type.
#
#   VERSION 1.0
#
#   AUTHORS
#   Dave Olker - HPE Global Solutions Engineering (BEST)
#
# (C) Copyright 2017 Hewlett Packard Enterprise Development LP 
##############################################################################
<#
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
#>


[CmdletBinding()]
param
(
    [Parameter (Mandatory, HelpMessage = "Provide the IP Address of the Synergy Composer.")]
    [ValidateNotNullorEmpty()]
    [IPAddress]$Appliance,
    
    [Parameter (Mandatory, HelpMessage = "Provide the Administrator Username.")]
    [ValidateNotNullorEmpty()]
    [String]$Username,
    
    [Parameter (Mandatory, HelpMessage = "Provide the Administrator's Password.")]
    [ValidateNotNullorEmpty()]
    [SecureString]$Password
)


function PowerOff_Compute_Modules
{
    Write-Output "Checking Power State of Compute Module Located at '$SrvName'" | Timestamp
    if ($Server.powerState -eq "On") {
        Write-Output "Attempting to power OFF Compute Module Located at '$SrvName'" | Timestamp
        if (Get-HPOVServer -Name "$SrvName" | Stop-HPOVServer -Confirm:$false -Force | Wait-HPOVTaskComplete) {
            Write-Output "Unable to power OFF Compute Module Located at '$SrvName'. Exiting." | Timestamp
            Exit
        }
    }
    else {
        Write-Output "Compute Module Located at '$SrvName' is already powered OFF" | Timestamp
    }
    
    Write-Output "Checking Power State of Compute Module Located at '$AvailableServerName'" | Timestamp
    if ($AvailableServer.powerState -eq "On") {
        Write-Output "Attempting to power OFF Compute Module Located at '$AvailableServerName'" | Timestamp
        if (Get-HPOVServer -Name "$AvailableServerName" | Stop-HPOVServer -Confirm:$false -Force | Wait-HPOVTaskComplete) {
            Write-Output "Unable to power OFF Compute Module Located at '$AvailableServerName'. Exiting." | Timestamp
            Exit
        }
    }
    else {
        Write-Output "Compute Module Located at '$AvailableServerName' is already powered OFF" | Timestamp
    }
}


function Unassign_Server_Profile
{
    Write-Output "Unassigning Server Profile '$SrvProfileName'" | Timestamp
    Get-HPOVServerProfile -Name "$SrvProfileName" | New-HPOVServerProfileAssign -Unassigned | Wait-HPOVTaskComplete
    Write-Output "Server Profile '$SrvProfileName' Unassigned" | Timestamp
    #
    # Sleep for 10 seconds to allow compute module to quiesce
    #
    Start-Sleep 10
}


function Assign_Server_Profile
{
    Write-Output "Assigning Server Profile '$SrvProfileName'" | Timestamp
    if (-Not (Get-HPOVServerProfile -Name "$SrvProfileName" | New-HPOVServerProfileAssign -Server "$AvailableServerName" -ApplianceConnection $ApplianceConnection | Wait-HPOVTaskComplete)) {
        Write-Output "Server Profile '$SrvProfileName' Assigned" | Timestamp
    }
}


function Clear_Alert
{
    Write-Output "Clearing Alert" | Timestamp
    if (-Not (Set-HPOVAlert -InputObject $Alert -Cleared)) {
        Write-Output "Alert Cleared" | Timestamp
    }
}


function PowerOn_Compute_Module
{
    Write-Output "Powering ON Compute Module Located at '$AvailableServerName'" | Timestamp
    Get-HPOVServer -Name "$AvailableServerName" | Start-HPOVServer | Wait-HPOVTaskComplete
    Write-Output "Compute Module '$AvailableServerName' Powered ON" | Timestamp
}


function Check_Available_Server
{
    Write-Output "Checking for Available Compute Module matching type '$SrvHardwareTypeName'" | Timestamp
    $Global:AvailableServer = Get-HPOVServer -NoProfile -ServerHardwareType $SrvHardwareType | Select -first 1
    
    if ($AvailableServer) {
        #
        # We have identified a matching compute module with no server profile assigned.
        #
        $Global:AvailableServerName = $AvailableServer.name
        Write-Output "Available Compute Module Identified in '$AvailableServerName'" | Timestamp
    }
    else {
        Write-Output "No available Compute Modules of type '$SrvHardwareTypeName' found.  Exiting." | Timestamp
        Exit
    }
}


function Check_Critical_Alert
{
    $Loop = $True
    While ($Loop) {
        #
        # Loop checking for new Critical Alerts every 10 seconds
        #
        Write-Host -NoNewline "Checking for new Active Critical Alerts ." | Timestamp
        do {
            Start-Sleep 10
            $Global:Alert = Get-HPOVAlert -Severity Critical -AlertState Active -TimeSpan (New-TimeSpan -Seconds 10)
            Write-Host -NoNewline "."
        }
        until ($Alert)

        $Srv = Send-HPOVRequest -uri $Alert.resourceUri -method GET
        $Global:SrvName = $Srv.name
    
        Write-Host
        Write-Output "Critical Alert detected for compute module located in '$SrvName'" | Timestamp
    
        $Global:Server = Get-HPOVServer -Name $SrvName
        
        #
        # Verify the Critical Alert is associated to a compute module with an assigned Server Profile
        #
        if ($Server.serverProfileUri) {
            $SrvProfile = Send-HPOVRequest -uri $Server.serverProfileUri -method GET
            $Global:SrvProfileName = $SrvProfile.name
            $Global:SrvHardware = Send-HPOVRequest -uri $Srv.serverHardwareTypeUri -method GET
            $Global:SrvHardwareType = Get-HPOVServerHardwareType -Name $SrvHardware.name
            $Global:SrvHardwareTypeName = $SrvHardwareType.name
        
            Write-Host
            Write-Output "Critical Alert detected for compute module located in '$SrvName'" | Timestamp
            $Loop = $False
        }
        else {
            Write-Host
            Write-Output "No Server Profile associated with '$SrvName'.  Skipping." | Timestamp
        }
    }
}


##############################################################################
#
# Main Program
#
##############################################################################

if (-not (get-module HPOneview.300)) 
{
    Import-Module HPOneView.300
}

if (-not $ConnectedSessions) 
{
	$ApplianceConnection = Connect-HPOVMgmt -Hostname $Appliance -Username $Username -Password $Password

    if (-Not $ConnectedSessions)
    {
        Write-Output "Login to the Synergy Composer failed.  Exiting."
        Exit
    } 
    else {
        Import-HPOVSslCertificate
    }
}

filter Timestamp {"$(Get-Date -Format G): $_"}

Write-Output "HPE Synergy Server Replace Tool Beginning..." | Timestamp

Check_Critical_Alert
Check_Available_Server
PowerOff_Compute_Modules

#
# Clear the Alert and sleep for 1 minute to allow the
# Server Profile to Unassign cleanly
#
Clear_Alert
Write-Output "Pause for 60 seconds for server hardware to refresh" | Timestamp
Start-Sleep 60

#
# Unassign the server profile from the compute module
#
Unassign_Server_Profile

#
# Assign the server profile to the replacement compute module
#
Assign_Server_Profile
PowerOn_Compute_Module

Write-Output "HPE Synergy Server Relace Tool Exiting" | Timestamp
