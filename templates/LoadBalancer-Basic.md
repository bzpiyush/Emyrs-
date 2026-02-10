# Basic Load Balancer Reference

## Overview
Basic LB for Merlin migration testing scenarios. Use this when you need to test migrating Basic LB workloads.

**Note:** Basic LB was officially retired on September 30, 2025, but existing Basic LBs still work and are valid migration test targets.

## Use Cases for Merlin Testing
- Test migration of Basic LB to Merlin
- Test migration of VMs behind Basic LB
- Validate Basic-to-Standard LB upgrade paths

## Key Differences from Standard
| Aspect | Basic | Standard |
|--------|-------|----------|
| SKU | Basic | Standard |
| Public IP SKU | **Must be Basic** | Must be Standard |
| Health probes | TCP, HTTP only | TCP, HTTP, HTTPS |
| Secure by default | ❌ No (open) | ✅ Yes (NSG required) |
| Availability zones | ❌ No | ✅ Yes |
| Backend pool | Availability set or VMSS only | Any VMs in VNet |
| Outbound rules | ❌ No | ✅ Yes |
| TCP Reset on idle | ❌ No | ✅ Yes |

## Required Components
1. Resource Group
2. VNet + Subnet
3. Public IP (**Basic SKU** - MUST include FirstPartyUsage IP Tag)
4. Load Balancer (Basic SKU)
5. Backend Pool
6. Health Probe (TCP or HTTP only)
7. Load Balancing Rule
8. Backend VMs (must have Basic Public IP or no Public IP)

## Subnet DefaultOutboundAccess Strategy
**Default:** Use `-DefaultOutboundAccess $true` (allows outbound internet)
**Fallback:** If subscription policy blocks it, use `-DefaultOutboundAccess $false`

```powershell
# Try with DefaultOutboundAccess = $true first
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.0.0.0/24" `
    -DefaultOutboundAccess $true

# If policy blocks it, use:
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.0.0.0/24" `
    -DefaultOutboundAccess $false
```

## Key PowerShell Commands

### 1. Create Public IP (Basic SKU)
```powershell
# Basic Public IP - Dynamic allocation
# NOTE: Some subscriptions require FirstPartyUsage IP Tag even for Basic
$ipTag = New-AzPublicIpTag -IpTagType "FirstPartyUsage" -Tag "/NonProd"
$pip = New-AzPublicIpAddress -Name "lb-pip" -ResourceGroupName $rg -Location $loc `
    -AllocationMethod Dynamic -Sku Basic -IpTag $ipTag -Tag @{"CreatedBy"="Emyrs"} -Force
```

### 2. Create Frontend IP Configuration
```powershell
# Public Basic LB
$feip = New-AzLoadBalancerFrontendIpConfig -Name "frontend" -PublicIpAddress $pip

# Internal Basic LB
$feip = New-AzLoadBalancerFrontendIpConfig -Name "frontend" `
    -PrivateIpAddress "10.0.0.100" -SubnetId $subnet.Id
```

### 3. Create Backend Pool
```powershell
$bepool = New-AzLoadBalancerBackendAddressPoolConfig -Name "backendpool"
```

### 4. Create Health Probe (TCP or HTTP only - NO HTTPS)
```powershell
# TCP probe
$probe = New-AzLoadBalancerProbeConfig -Name "healthprobe" -Protocol Tcp -Port 3389 `
    -IntervalInSeconds 15 -ProbeCount 2

# HTTP probe
$probe = New-AzLoadBalancerProbeConfig -Name "healthprobe" -Protocol Http -Port 80 `
    -RequestPath "/" -IntervalInSeconds 15 -ProbeCount 2
```

### 5. Create Load Balancing Rule
```powershell
# Note: NO -EnableTcpReset, NO -DisableOutboundSNAT for Basic
$rule = New-AzLoadBalancerRuleConfig -Name "lbrule" -Protocol Tcp `
    -FrontendPort 3389 -BackendPort 3389 `
    -FrontendIpConfiguration $feip -BackendAddressPool $bepool `
    -Probe $probe -IdleTimeoutInMinutes 4
```

### 6. Create Basic Load Balancer
```powershell
$lb = New-AzLoadBalancer -Name "myblb" -ResourceGroupName $rg -Location $loc `
    -Sku Basic `
    -FrontendIpConfiguration $feip -BackendAddressPool $bepool `
    -Probe $probe -LoadBalancingRule $rule `
    -Tag @{"CreatedBy"="Emyrs"} -Force
```

### 7. Add VM to Backend Pool
```powershell
# Backend VMs must have Basic Public IP or NO Public IP (can't mix SKUs)
$lb = Get-AzLoadBalancer -Name "myblb" -ResourceGroupName $rg
$bepool = $lb | Get-AzLoadBalancerBackendAddressPoolConfig -Name "backendpool"

$nic = Get-AzNetworkInterface -Name "vm1-nic" -ResourceGroupName $rg
$nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $bepool
$nic | Set-AzNetworkInterface
```

### 8. Create VM with Basic Public IP (for backend)
```powershell
# Basic Public IP for VM - ALWAYS include FirstPartyUsage IP Tag
$ipTag = New-AzPublicIpTag -IpTagType "FirstPartyUsage" -Tag "/NonProd"
$vmPip = New-AzPublicIpAddress -Name "$vmName-pip" -ResourceGroupName $rg -Location $loc `
    -AllocationMethod Dynamic -Sku Basic -IpTag $ipTag -Tag @{"CreatedBy"="Emyrs"} -Force

$nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $rg -Location $loc `
    -SubnetId $subnet.Id -PublicIpAddressId $vmPip.Id -Tag @{"CreatedBy"="Emyrs"} -Force
```

## Complete Basic LB Setup Example
```powershell
$rg = "basiclb-test-rg"
$loc = "centraluseuap"

# 1. Public IP (Basic) - ALWAYS include FirstPartyUsage IP Tag
$ipTag = New-AzPublicIpTag -IpTagType "FirstPartyUsage" -Tag "/NonProd"
$pip = New-AzPublicIpAddress -Name "blb-pip" -ResourceGroupName $rg -Location $loc `
    -AllocationMethod Dynamic -Sku Basic -IpTag $ipTag -Force

# 2. Frontend
$feip = New-AzLoadBalancerFrontendIpConfig -Name "frontend" -PublicIpAddress $pip

# 3. Backend pool
$bepool = New-AzLoadBalancerBackendAddressPoolConfig -Name "backendpool"

# 4. Health probe (TCP)
$probe = New-AzLoadBalancerProbeConfig -Name "tcpprobe" -Protocol Tcp -Port 80 `
    -IntervalInSeconds 15 -ProbeCount 2

# 5. LB rule
$rule = New-AzLoadBalancerRuleConfig -Name "httprule" -Protocol Tcp `
    -FrontendPort 80 -BackendPort 80 `
    -FrontendIpConfiguration $feip -BackendAddressPool $bepool `
    -Probe $probe -IdleTimeoutInMinutes 4

# 6. Create Basic LB
$lb = New-AzLoadBalancer -Name "mybasicLB" -ResourceGroupName $rg -Location $loc `
    -Sku Basic -FrontendIpConfiguration $feip -BackendAddressPool $bepool `
    -Probe $probe -LoadBalancingRule $rule -Force

Write-Host "Basic LB created: $($lb.Name)"
```

## Basic LB Limitations
- ❌ No availability zones
- ❌ No HTTPS health probes
- ❌ No outbound rules (uses implicit SNAT)
- ❌ No TCP reset on idle
- ❌ No SLA
- ❌ Backend pool limited to availability set or VMSS
- ✅ Open by default (no NSG required for health probes)
- ✅ Can use Dynamic IP allocation

## SKU Mixing Rules
- Basic LB + Basic Public IP = ✅ OK
- Basic LB + Standard Public IP = ❌ FAILS
- Standard LB + Standard Public IP = ✅ OK
- Standard LB + Basic Public IP = ❌ FAILS
- VMs behind Basic LB cannot have Standard Public IPs

## How to Verify Basic LB was Created

### Check LB SKU
```powershell
# Get LB and check SKU
$lb = Get-AzLoadBalancer -Name "mybasicLB" -ResourceGroupName $rg
$lb.Sku.Name

# Expected output for Basic: "Basic"
# Expected output for Standard: "Standard"
```

### Check Public IP SKU (must match LB SKU)
```powershell
$pip = Get-AzPublicIpAddress -Name "blb-pip" -ResourceGroupName $rg
$pip.Sku.Name

# Expected output: "Basic"
```

### List All LBs with SKU
```powershell
Get-AzLoadBalancer -ResourceGroupName $rg | Select Name, @{N='SKU';E={$_.Sku.Name}}, Location
```

### Full Verification Script
```powershell
$rg = "your-rg-name"
$lbName = "mybasicLB"

$lb = Get-AzLoadBalancer -Name $lbName -ResourceGroupName $rg
Write-Host "Load Balancer: $($lb.Name)" -ForegroundColor Cyan
Write-Host "  SKU: $($lb.Sku.Name)" -ForegroundColor $(if ($lb.Sku.Name -eq 'Basic') { 'Green' } else { 'Yellow' })
Write-Host "  Frontend IPs: $($lb.FrontendIpConfigurations.Count)"
Write-Host "  Backend Pools: $($lb.BackendAddressPools.Count)"
Write-Host "  Health Probes: $($lb.Probes.Count)"
Write-Host "  LB Rules: $($lb.LoadBalancingRules.Count)"

if ($lb.Sku.Name -eq 'Basic') {
    Write-Host "`n✅ This is a BASIC Load Balancer" -ForegroundColor Green
} else {
    Write-Host "`n⚠️ This is a STANDARD Load Balancer" -ForegroundColor Yellow
}
```
