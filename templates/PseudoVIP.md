# Pseudo VIP (Default Outbound Access) Reference

## Overview
When a VM is in a subnet WITHOUT `-DefaultOutboundAccess $false`, Azure automatically assigns a **default outbound public IP** (Pseudo VIP). This IP is Microsoft-owned, can change without notice, and is NOT recommended for production.

**For Merlin testing:** We create VMs with Pseudo VIP to test migration scenarios.

## Key Difference from Regular VMs

| Aspect | Regular VM (Private Subnet) | Pseudo VIP VM |
|--------|----------------------------|---------------|
| Subnet setting | `-DefaultOutboundAccess $false` | `-DefaultOutboundAccess $true` or NOT SET |
| Explicit Public IP | Yes (Standard SKU) | **NO** |
| Outbound IP | Your Public IP | Azure's Default Outbound IP (Pseudo VIP) |
| IP stability | Stable, you own it | Can change, Microsoft owns it |

## Required Components
1. Resource Group
2. NSG (with RDP rule)
3. VNet + Subnet (**WITHOUT** `-DefaultOutboundAccess $false`)
4. NIC (**WITHOUT** Public IP)
5. VM

## Subnet DefaultOutboundAccess Strategy
- **Default**: Use `-DefaultOutboundAccess $true` (enables Pseudo VIP)
- **On failure**: If policy blocks it, Pseudo VIP scenario may not work in that subscription
- After March 31, 2026, new VNets default to private subnets - explicitly set `$true`

## Key Commands

### Subnet WITHOUT Private Flag (enables Pseudo VIP)
```powershell
# DO NOT include -DefaultOutboundAccess $false
# Either omit it entirely or set to $true
$subnet = New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.0.0.0/24" `
    -NetworkSecurityGroupId $nsg.Id
# OR explicitly enable default outbound:
$subnet = New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.0.0.0/24" `
    -NetworkSecurityGroupId $nsg.Id -DefaultOutboundAccess $true
```

### NIC WITHOUT Public IP
```powershell
# NO -PublicIpAddressId parameter!
$nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $rg -Location $loc `
    -SubnetId $subnet.Id -Tag @{"CreatedBy"="Emyrs"} -Force
```

### VM (same as normal, just no public IP on NIC)
```powershell
$vmTags = @{ "TipNode.SessionId" = "<GUID>"; "CreatedBy" = "Emyrs" }
$vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_D2s_v3" -Tags $vmTags |
    Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential $cred |
    Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" `
        -Skus "2022-datacenter-g2" -Version "latest" |
    Add-AzVMNetworkInterface -Id $nic.Id |
    Set-AzVMBootDiagnostic -Disable
New-AzVM -ResourceGroupName $rg -Location $loc -VM $vmConfig
```

## How to Verify Pseudo VIP
The VM won't show a public IP in Azure portal, but it CAN reach the internet via the default outbound IP.

```powershell
# Run inside the VM to see its outbound IP
Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName $vmName `
    -CommandId "RunPowerShellScript" `
    -ScriptString "(Invoke-WebRequest -Uri 'https://ifconfig.me' -UseBasicParsing).Content"
```

## RDP Access for Pseudo VIP VMs
Since there's no public IP, you need one of these to RDP:
1. **Bastion** - Deploy Azure Bastion in the VNet
2. **Jump Box** - Another VM with public IP in same VNet
3. **VPN/ExpressRoute** - Connect to VNet privately

## Pseudo VIP Limitations (from Azure docs)
- IP can change without notice
- Not consistent across VMSS instances
- Doesn't support fragmented packets
- Doesn't support ICMP pings
- Multiple NICs can yield inconsistent outbound IPs

## When to Use Pseudo VIP for Testing
- Testing Merlin migration with default outbound scenarios
- Verifying behavior before/after migration
- Testing workloads that rely on default outbound access

## Comparison: Explicit Outbound Methods
| Method | Pseudo VIP | NAT Gateway | Standard LB | Public IP |
|--------|------------|-------------|-------------|-----------|
| Subnet private | No | Yes | Yes | Yes |
| Dedicated IP | No | Yes | Yes | Yes |
| Recommended | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |
| Production use | ❌ | ✅ | ✅ | ✅ |
