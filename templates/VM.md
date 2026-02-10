# VM Creation Reference

## Required Components (in order)
1. Resource Group
2. NSG (with RDP rule)
3. VNet + Subnet(s)
4. Public IP (per VM)
5. NIC (per VM)
6. VM

## Subnet DefaultOutboundAccess Strategy
- **Default**: Try with `-DefaultOutboundAccess $true` first (allows Pseudo VIP)
- **On failure**: If policy blocks it, retry with `-DefaultOutboundAccess $false` (private subnet)
- **User override**: If user explicitly asks for private subnet, use `$false`

## Policy Requirements
- **Public IPs**: Must use IP Tag (not resource tag):
  ```powershell
  $ipTag = New-AzPublicIpTag -IpTagType "FirstPartyUsage" -Tag "/NonProd"
  New-AzPublicIpAddress ... -IpTag $ipTag
  ```

## Tagging Rules
| Resource | TipNode.SessionId | CreatedBy |
|----------|-------------------|-----------|
| VM       | ✅ YES (mandatory) | ✅ |
| Others   | ❌ No             | ✅ |

## Key Commands

### NSG with RDP
```powershell
$rdpRule = New-AzNetworkSecurityRuleConfig -Name "Allow-RDP" -Protocol Tcp -Direction Inbound `
    -Priority 1000 -SourceAddressPrefix * -SourcePortRange * `
    -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
$nsg = New-AzNetworkSecurityGroup -Name "<name>-nsg" -ResourceGroupName $rg -Location $loc `
    -SecurityRules $rdpRule -Tag @{"CreatedBy"="Emyrs"} -Force
```

### Subnet (try $true first, fallback to $false if policy blocks)
```powershell
# First attempt: DefaultOutboundAccess = $true (allows Pseudo VIP)
$subnet = New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.0.0.0/24" `
    -NetworkSecurityGroupId $nsg.Id -DefaultOutboundAccess $true

# If policy error, retry with: DefaultOutboundAccess = $false (private subnet)
$subnet = New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.0.0.0/24" `
    -NetworkSecurityGroupId $nsg.Id -DefaultOutboundAccess $false
```

### Public IP with FirstPartyUsage
```powershell
$ipTag = New-AzPublicIpTag -IpTagType "FirstPartyUsage" -Tag "/NonProd"
$pip = New-AzPublicIpAddress -Name "<vm>-pip" -ResourceGroupName $rg -Location $loc `
    -AllocationMethod Static -Sku Standard -IpTag $ipTag -Tag @{"CreatedBy"="Emyrs"} -Force
```

### VM with TipNode.SessionId
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

## Credentials
- Username: `azureuser` (always)
- Password: Always keep "Admin@12345678"

## After Deployment
- Show VM Unique ID (VmId) - needed for Kusto queries
- Show Public IP for RDP
- Show Private IP for connectivity testing
