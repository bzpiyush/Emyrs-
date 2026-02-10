# VMSS Creation Reference

## Single-Tenant vs Multi-Tenant VMSS

| Setting | Single-Tenant | Multi-Tenant |
|---------|---------------|--------------|
| **Orchestration Mode** | `Uniform` | `Flexible` |
| **Availability Zones** | Single zone (e.g., `-Zone 2`) | Regional (no zone) |
| **Fault Domain Count** | `5` (fixed spreading) | `1` (max spreading) |
| **Single Placement Group** | `$true` | `$false` |
| **Upgrade Policy** | `Automatic` + AutoOSUpgrade | `Manual` |
| **Scaling Capacity** | `< 100` | Up to 1,000 |

---

## Single-Tenant VMSS (Uniform Mode) - WORKING

```powershell
$rg = "piyushvmsstest"
$loc = "centraluseuap"
$sessionId = "<TipNode.SessionId>"
$password = ConvertTo-SecureString "<password>" -AsPlainText -Force

# Get network resources
$vnet = Get-AzVirtualNetwork -ResourceGroupName $rg -Name "$rg-vnet"
$subnet = $vnet.Subnets[0]
$nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "$rg-nsg"

# 1. Base config (don't use -EnableAutomaticOSUpgrade flag - set it manually)
$vmssConfig = New-AzVmssConfig -Location $loc `
    -SkuCapacity 1 `
    -SkuName "Standard_D2hs_v3" `
    -UpgradePolicyMode "Automatic" `
    -Zone 2 `
    -PlatformFaultDomainCount 5 `
    -SinglePlacementGroup $true `
    -OrchestrationMode "Uniform" `
    -Tag @{"TipNode.SessionId"=$sessionId; "CreatedBy"="Emyrs"; "Type"="SingleTenant"}

# 2. Enable AutoOSUpgrade manually on config object
$vmssConfig.UpgradePolicy.AutomaticOSUpgradePolicy = New-Object Microsoft.Azure.Management.Compute.Models.AutomaticOSUpgradePolicy
$vmssConfig.UpgradePolicy.AutomaticOSUpgradePolicy.EnableAutomaticOSUpgrade = $true

# 3. OS Profile (disable Windows auto-updates for Platform Auto-Upgrade)
$vmssConfig = Set-AzVmssOsProfile -VirtualMachineScaleSet $vmssConfig `
    -ComputerNamePrefix "stvm" `
    -AdminUsername "azureuser" `
    -AdminPassword $password `
    -WindowsConfigurationProvisionVMAgent $true `
    -WindowsConfigurationEnableAutomaticUpdate $false

# 4. Storage Profile (Gen2 image required for Trusted Launch)
$vmssConfig = Set-AzVmssStorageProfile -VirtualMachineScaleSet $vmssConfig `
    -OsDiskCreateOption "FromImage" `
    -OsDiskCaching "ReadWrite" `
    -ImageReferencePublisher "MicrosoftWindowsServer" `
    -ImageReferenceOffer "WindowsServer" `
    -ImageReferenceSku "2022-datacenter-g2" `
    -ImageReferenceVersion "latest"

# 5. Health Extension (REQUIRED for AutoOSUpgrade)
$healthSettings = @{ "protocol" = "tcp"; "port" = 3389 }
$vmssConfig = Add-AzVmssExtension -VirtualMachineScaleSet $vmssConfig `
    -Name "HealthExtension" `
    -Publisher "Microsoft.ManagedServices" `
    -Type "ApplicationHealthWindows" `
    -TypeHandlerVersion "1.0" `
    -AutoUpgradeMinorVersion $true `
    -Setting $healthSettings

# 6. Network Config
$ipConfig = New-AzVmssIpConfig -Name "ipconfig1" -SubnetId $subnet.Id -Primary
$vmssConfig = Add-AzVmssNetworkInterfaceConfiguration -VirtualMachineScaleSet $vmssConfig `
    -Name "nic" -Primary $true -IpConfiguration $ipConfig -NetworkSecurityGroupId $nsg.Id

# 7. Create VMSS
New-AzVmss -ResourceGroupName $rg -VMScaleSetName "vmss-single-tenant" -VirtualMachineScaleSet $vmssConfig
```

---

## Multi-Tenant VMSS (Flexible Mode) - WORKING

```powershell
$rg = "piyushvmsstest"
$loc = "centraluseuap"
$sessionId = "<TipNode.SessionId>"
$password = ConvertTo-SecureString "<password>" -AsPlainText -Force

# Get network resources
$vnet = Get-AzVirtualNetwork -ResourceGroupName $rg -Name "$rg-vnet"
$subnet = $vnet.Subnets[0]
$nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "$rg-nsg"

# 1. Base config - Flexible mode, FD=1 for max spreading
$vmssConfig = New-AzVmssConfig -Location $loc `
    -SkuCapacity 1 `
    -SkuName "Standard_D2hs_v3" `
    -UpgradePolicyMode "Manual" `
    -OrchestrationMode "Flexible" `
    -PlatformFaultDomainCount 1 `
    -Tag @{"TipNode.SessionId"=$sessionId; "CreatedBy"="Emyrs"; "Type"="MultiTenant"}

# 2. Enable Trusted Launch (REQUIRED by SDN SFI policy)
$vmssConfig = Set-AzVmssSecurityProfile -VirtualMachineScaleSet $vmssConfig -SecurityType "TrustedLaunch"
$vmssConfig = Set-AzVmssUefi -VirtualMachineScaleSet $vmssConfig -EnableVtpm $true -EnableSecureBoot $true

# 3. OS Profile
$vmssConfig = Set-AzVmssOsProfile -VirtualMachineScaleSet $vmssConfig `
    -ComputerNamePrefix "mtvm" `
    -AdminUsername "azureuser" `
    -AdminPassword $password

# 4. Storage Profile (Gen2 required for Trusted Launch)
$vmssConfig = Set-AzVmssStorageProfile -VirtualMachineScaleSet $vmssConfig `
    -OsDiskCreateOption "FromImage" `
    -ImageReferencePublisher "MicrosoftWindowsServer" `
    -ImageReferenceOffer "WindowsServer" `
    -ImageReferenceSku "2022-datacenter-g2" `
    -ImageReferenceVersion "latest"

# 5. Network Config
$ipConfig = New-AzVmssIpConfig -Name "ipconfig1" -SubnetId $subnet.Id -Primary
$vmssConfig = Add-AzVmssNetworkInterfaceConfiguration -VirtualMachineScaleSet $vmssConfig `
    -Name "nic" -Primary $true -IpConfiguration $ipConfig -NetworkSecurityGroupId $nsg.Id

# 6. Create VMSS
New-AzVmss -ResourceGroupName $rg -VMScaleSetName "vmss-multi-tenant" -VirtualMachineScaleSet $vmssConfig
```

---

## Policy Requirements (RnmTestIDC Subscription)

### 1. Trusted Launch (SDN SFI Policy)
```powershell
# Use Set-AzVmssSecurityProfile + Set-AzVmssUefi
$vmssConfig = Set-AzVmssSecurityProfile -VirtualMachineScaleSet $vmssConfig -SecurityType "TrustedLaunch"
$vmssConfig = Set-AzVmssUefi -VirtualMachineScaleSet $vmssConfig -EnableVtpm $true -EnableSecureBoot $true

# Must use Gen2 image (e.g., "2022-datacenter-g2")
```

### 2. Automatic OS Upgrade (Uniform mode only)
```powershell
# Set manually on config object (flag sometimes fails)
$vmssConfig.UpgradePolicy.AutomaticOSUpgradePolicy = New-Object Microsoft.Azure.Management.Compute.Models.AutomaticOSUpgradePolicy
 $vmssConfig.UpgradePolicy.AutomaticOSUpgradePolicy.EnableAutomaticOSUpgrade = $true

# MUST add Health Extension
$healthSettings = @{ "protocol" = "tcp"; "port" = 3389 }
Add-AzVmssExtension -VirtualMachineScaleSet $vmssConfig -Name "HealthExtension" `
    -Publisher "Microsoft.ManagedServices" -Type "ApplicationHealthWindows" `
    -TypeHandlerVersion "1.0" -Setting $healthSettings
```

### 3. Private Subnet (No Default Outbound)
```powershell
# Subnet must use DefaultOutboundAccess = $false
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name "default" `
    -AddressPrefix "10.0.0.0/24" `
    -NetworkSecurityGroupId $nsg.Id `
    -DefaultOutboundAccess $false
```

### 4. Public IPs - FirstPartyUsage Tag
```powershell
$ipTag = New-AzVmssPublicIpAddressConfigIpTag -IpTagType "FirstPartyUsage" -Tag "/NonProd"
$publicIpConfig = New-AzVmssPublicIpAddressConfig -Name "pip" -IpTag $ipTag
```

---

## Tagging

| Resource | TipNode.SessionId | CreatedBy |
|----------|-------------------|-----------|
| VMSS     | ✅ YES (mandatory) | ✅ |
| VNet/NSG | ❌ No             | ✅ |

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| `ZonalAllocationFailed` | Use `Standard_D2hs_v3` instead of `Standard_D2s_v3` |
| `Trusted Launch policy error` | Use `Set-AzVmssSecurityProfile` + `Set-AzVmssUefi` |
| `AutoOSUpgrade policy error` | Set manually on config + add Health Extension |
| `Subnet outbound access error` | Use `-DefaultOutboundAccess $false` |
| `-EnableAutomaticOSUpgrade` fails | Set via config object instead of flag |

---

## Check Zone/SKU Availability
```powershell
Get-AzComputeResourceSku -Location "centraluseuap" | 
    Where-Object { $_.ResourceType -eq "virtualMachines" -and $_.Name -like "Standard_D2*" } | 
    Select Name, @{N='Zones';E={$_.LocationInfo.Zones -join ','}}
```

---

## Get VMSS Info After Deployment

```powershell
# List VMSS with key properties
Get-AzVmss -ResourceGroupName $rg | Select Name, OrchestrationMode, PlatformFaultDomainCount, SinglePlacementGroup, ProvisioningState

# Uniform VMSS instances
Get-AzVmssVM -ResourceGroupName $rg -VMScaleSetName "vmss-single-tenant"

# Flexible VMSS - use Azure Resource Graph
Search-AzGraph -Query "resources | where type =~ 'Microsoft.Compute/virtualMachines' | where properties.virtualMachineScaleSet.id contains 'vmss-multi-tenant'"
```
