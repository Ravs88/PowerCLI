function Move-VMHostToDVS {
<#  
.SYNOPSIS  
    Takes a VMHost's standard vSwitch and creates a distributed vSwitch then migrates all VMs and Uplinks

.DESCRIPTION 
    Migrates a host from an existing standard vSwitch to a distributed vSwitch, including VMs and uplinks

.NOTES  
    Author:  Kyle Ruddy, @kmruddy, thatcouldbeaproblem.com

.PARAMETER vmhost
	The FQDN or IP of your VMHost

.PARAMETER vsswitch
	The name of the standard virtual switch 

.EXAMPLE
	PS> Move-VMHostToDVS -vmhost vmhost01 -vss vSwitch1
#>
[CmdletBinding()] 
	param(
		[Parameter(Mandatory=$true,Position=0,ValueFromPipelineByPropertyName=$true)]
        [Alias('Name')]
		[String]$vmhost,
		[Parameter(Mandatory=$true,Position=1)]
		[String]$vsswitch
  	)

	Process {

        $modules = Get-Module
        if (!($modules | ?{$_.Name -like "VMware*"})) {
            Write-Warning "PowerCLI not found, please initialize PowerCLI."}
        elseif ((Get-Module -Name VMware.VimAutomation.Vds).Version.Major -lt 6) {Write-Warning "PowerCLI Version 6.0 not found, please upgrade."}
        elseif (!($global:DefaultVIServer) -or $global:DefaultVIServer.IsConnected -eq $false) {Write-Warning "No active vCenter connection found, please connect to a vCenter."}
        else {
	        $vmh = Get-VMHost -Name $vmhost
            $vss = $vmh | Get-VirtualSwitch -Name $vsswitch -Standard -ErrorAction SilentlyContinue
            $vmks = $vss | Get-VirtualPortGroup | ?{$_.Port -like "host"}
            if (!$vmh) {
                Write-Warning "$vmhost - VMHost can't be found."}
            elseif (!$vmh) {Write-Warning "$vmhost - VMHost can't be found."}
            elseif ($vss.nic.count -lt 2) {Write-Warning "$vss - $vmhost has less than 2 uplinks."}
            elseif ($vmks) {Write-Warning "$vss - Contains vmkernel ports for $vmhost"}
            else {
            
                $activenics = $vss.ExtensionData.Spec.Policy.NicTeaming.NicOrder.ActiveNic
                $stbynics = $vss.ExtensionData.Spec.Policy.NicTeaming.NicOrder.StandbyNic

                if (!(Get-VDSwitch -Name $vsswitch -ErrorAction SilentlyContinue)) {New-VDSwitch -Name $vss.Name -Mtu $vss.Mtu -NumUplinkPorts ($vss.nic.count) -Location ($vmh | Get-Datacenter) -Confirm:$false}
            
                $dvs = $vmh | Get-VDSwitch -Name $vsswitch -ErrorAction SilentlyContinue
                if (!$dvs) {Add-VDSwitchVMHost -VMHost $vmh -VDSwitch (Get-VDSwitch -Name $vsswitch -ErrorAction SilentlyContinue) -Confirm:$false; $dvs = $vmh | Get-VDSwitch -Name $vsswitch -ErrorAction SilentlyContinue}
                        
                if ($activenics.count -gt 1) {
                    Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $dvs -VMHostPhysicalNic (Get-VMHostNetworkAdapter -VMHost $vmh -Physical -Name ($activenics | select -last 1)) -Confirm:$false}
                elseif ($stbynics.count -gt 1) {Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $dvs -VMHostPhysicalNic (Get-VMHostNetworkAdapter -VMHost $vmh -Physical -Name ($stbynics | select -last 1)) -Confirm:$false}
                else {Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $dvs -VMHostPhysicalNic (Get-VMHostNetworkAdapter -VMHost $vmh -Physical -Name ($stbynics)) -Confirm:$false}
            
                $vspgs = $vss | Get-VirtualPortGroup -Standard
                foreach ($pg in $vspgs) {
                    $vdpg = $null

                    if (!($dvs | Get-VDPortgroup -Name $pg.Name)) {
                        if ($pg.VlanId -eq 4095) {
                            New-VDPortgroup -VDSwitch $dvs -Name $pg.Name -VlanTrunkRange "1-4094" -Confirm:$false | Out-Null}
                        else {New-VDPortgroup -VDSwitch $dvs -Name $pg.Name -VlanId $pg.vlanid -Confirm:$false | Out-Null}
                    }
                    $vdpg = $dvs | Get-VDPortgroup -Name $pg.Name
                    $pg | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $vdpg -Confirm:$false | Out-Null

                }
            
                $oldvss = Get-VirtualSwitch -Name $vss.Name -VMHost $vmh -Standard
                $oldactivenics = $oldvss.ExtensionData.Spec.Policy.NicTeaming.NicOrder.ActiveNic
                $oldstbynics = $oldvss.ExtensionData.Spec.Policy.NicTeaming.NicOrder.StandbyNic

                foreach ($avnic in $oldactivenics) {Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $dvs -VMHostPhysicalNic (Get-VMHostNetworkAdapter -VMHost $vmh -Physical -Name $avnic) -Confirm:$false}
                foreach ($svnic in $oldstbynics) {Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $dvs -VMHostPhysicalNic (Get-VMHostNetworkAdapter -VMHost $vmh -Physical -Name $svnic) -Confirm:$false}
                
            }
        }
	} # End of process
} # End of function

function Move-VMHostToVSS {
<#  
.SYNOPSIS  
    Takes a VMHost's distributed vSwitch and creates a standard vSwitch then migrates all VMs and Uplinks

.DESCRIPTION 
    Migrates a host from an existing distributed vSwitch to a standard vSwitch, including VMs and uplinks

.NOTES  
    Author:  Kyle Ruddy, @kmruddy, thatcouldbeaproblem.com

.PARAMETER vmhost
	The FQDN or IP of your VMHost

.PARAMETER dvswitch
	The name of the distributed virtual switch 

.EXAMPLE
	PS> Move-VMHostToVSS -vmhost vmhost01 -dvs vSwitch1
#>
[CmdletBinding()] 
	param(
		[Parameter(Mandatory=$true,Position=0,ValueFromPipelineByPropertyName=$true)]
        [Alias('Name')]
		[String]$vmhost,
		[Parameter(Mandatory=$true,Position=1)]
		[String]$dvswitch
  	)

	Process {

    $modules = Get-Module
    if (!($modules | ?{$_.Name -like "VMware*"})) {
        Write-Warning "PowerCLI not found, please initialize PowerCLI."}
    elseif ((Get-Module -Name VMware.VimAutomation.Vds).Version.Major -lt 6) {Write-Warning "PowerCLI Version 6.0 not found, please upgrade."}
    elseif (!($global:DefaultVIServer) -or $global:DefaultVIServer.IsConnected -eq $false) {Write-Warning "No active vCenter connection found, please connect to a vCenter."}
    else {
        $vmh = Get-VMHost -Name $vmhost
        $dvs = $vmh | Get-VDSwitch -Name $dvswitch -ErrorAction SilentlyContinue
        $vmks = $dvs | Get-VMHostNetworkAdapter -VMKernel -VMHost $vmh -ErrorAction SilentlyContinue
        if (!$vmh) {
            Write-Warning "$vmhost - VMHost can't be found."}
        elseif (!$vmh) {Write-Warning "$vmhost - VMHost can't be found."}
        elseif ($dvs.NumUplinkPorts -lt 2) {Write-Warning "$vss - $vmhost has less than 2 uplinks."}
        elseif ((Get-VirtualSwitch -Name $dvswitch -Standard -ErrorAction SilentlyContinue)) {Write-Warning "$dvswitch - a standard switch of this name already exists."}
        elseif ($vmks) {Write-Warning "$dvswitch - Contains vmkernel ports for $vmhost"}
        else {

            $uplinks = $dvs | Get-VMHostNetworkAdapter -VMHost $vmh
            $pgs = Get-VDPortgroup -VDSwitch $dvs.name | ?{$_.IsUplink -eq $false}

            $vss = New-VirtualSwitch -VMHost $vmh -Name $dvs.Name -Mtu $dvs.Mtu
       
            Remove-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter ($uplinks | select -Last 1) -Confirm:$false
            Add-VirtualSwitchPhysicalNetworkAdapter -VMHostPhysicalNic ($uplinks | select -Last 1) -VirtualSwitch $vss -Confirm:$false

            foreach ($pg in $pgs) {
                $vspg = $null

                if ($pg.VlanConfiguration.VlanType -eq "Vlan") {
                    $vss | New-VirtualPortGroup -Name $pg.Name -VLanId $pg.VlanConfiguration.VlanId -Confirm:$false | Out-Null}
                elseif ($pg.VlanConfiguration.VlanType -eq "Trunk") {$vss | New-VirtualPortGroup -Name $pg.Name -VLanId 4095 -Confirm:$false | Out-Null}
                else {$vss | New-VirtualPortGroup -Name $pg.Name -Confirm:$false | Out-Null}
                Start-Sleep -Seconds 5
                $vspg = $vss | Get-VirtualPortGroup -Name $pg.Name -Standard
                $pg | Get-NetworkAdapter | ?{$_.parent.VMHost -eq $vmh} | Set-NetworkAdapter -Portgroup $vspg -Confirm:$false | Out-Null
            
            }

            $olduplinks = $dvs | Get-VMHostNetworkAdapter -VMHost $vmh
            foreach ($uplink in $olduplinks) {
                Remove-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $uplink -Confirm:$false
                Add-VirtualSwitchPhysicalNetworkAdapter -VMHostPhysicalNic $uplink -VirtualSwitch $vss -Confirm:$false
            }

            }
        }
	} # End of process
} # End of function
