# Standard Load Balancer Reference

## Overview
Standard LB for production workloads. Zone-redundant, supports availability zones, secure by default.

**Important:** Basic LB was retired on September 30, 2025. Use Standard for all new deployments.

## Components (from Azure docs)
1. **Frontend IP** - Public or Private IP, point of contact for clients
2. **Backend Pool** - VMs or VMSS serving requests (IP-based or NIC-based)
3. **Health Probe** - TCP, HTTP, or HTTPS to check backend health
4. **Load Balancing Rule** - Maps frontend IP:port to backend pool
5. **Outbound Rule** - Configures outbound SNAT (optional but recommended)
6. **Inbound NAT Rule** - Port forwarding to specific VM (optional)

## SKU Comparison (Standard vs Basic)
| Feature | Standard | Basic (Retired) |
|---------|----------|-----------------|
| Backend pool size | Up to 1000 | Up to 300 |
| Health probes | TCP, HTTP, HTTPS | TCP, HTTP only |
| Availability zones | ✅ Yes | ❌ No |
| Secure by default | ✅ Yes (NSG required) | ❌ Open by default |
| Outbound rules | ✅ Yes | ❌ No |
| HA Ports | ✅ Yes | ❌ No |
| SLA | 99.99% | No SLA |
| TCP Reset on idle | ✅ Yes | ❌ No |

## Health Probe Configuration
| Property | Description |
|----------|-------------|
| Protocol | TCP, HTTP, or HTTPS |
| Port | Destination port to probe |
| Interval | Seconds between probes (default 5) |
| Threshold | Consecutive failures before marking unhealthy |

**Probe Source IP:** `168.63.129.16` (AzureLoadBalancer service tag) - Must be allowed in NSG!

### Probe Behavior
- **TCP**: 3-way handshake, fails if no response or TCP RST
- **HTTP/HTTPS**: Returns 200 = healthy, anything else = unhealthy
- **Timeout**: HTTP/HTTPS has 30 second timeout

## Key PowerShell Commands

### 1. Create Public IP (Standard SKU, Zone-Redundant)
```powershell
$ipTag = New-AzPublicIpTag -IpTagType "FirstPartyUsage" -Tag "/NonProd"
$pip = New-AzPublicIpAddress -Name "lb-pip" -ResourceGroupName $rg -Location $loc `
    -AllocationMethod Static -Sku Standard -Zone 1,2,3 -IpTag $ipTag -Force
```

### 2. Create Frontend IP Configuration
```powershell
# Public LB
$feip = New-AzLoadBalancerFrontendIpConfig -Name "frontend" -PublicIpAddress $pip

# Internal LB (private IP)
$feip = New-AzLoadBalancerFrontendIpConfig -Name "frontend" `
    -PrivateIpAddress "10.0.0.100" -SubnetId $subnet.Id
```

### 3. Create Backend Pool
```powershell
$bepool = New-AzLoadBalancerBackendAddressPoolConfig -Name "backendpool"
```

### 4. Create Health Probe
```powershell
# TCP probe (for RDP, custom apps)
$probe = New-AzLoadBalancerProbeConfig -Name "healthprobe" `
    -Protocol Tcp -Port 3389 -IntervalInSeconds 5 -ProbeCount 2

# HTTP probe (for web apps)
$probe = New-AzLoadBalancerProbeConfig -Name "healthprobe" `
    -Protocol Http -Port 80 -RequestPath "/" -IntervalInSeconds 15 -ProbeCount 2

# HTTPS probe
$probe = New-AzLoadBalancerProbeConfig -Name "healthprobe" `
    -Protocol Https -Port 443 -RequestPath "/health" -IntervalInSeconds 15 -ProbeCount 2
```

### 5. Create Load Balancing Rule
```powershell
$rule = New-AzLoadBalancerRuleConfig -Name "lbrule" `
    -Protocol Tcp -FrontendPort 80 -BackendPort 80 `
    -FrontendIpConfiguration $feip -BackendAddressPool $bepool `
    -Probe $probe -IdleTimeoutInMinutes 15 `
    -EnableTcpReset -DisableOutboundSNAT
```

### 6. Create the Load Balancer
```powershell
$lb = New-AzLoadBalancer -Name "myslb" -ResourceGroupName $rg -Location $loc `
    -Sku Standard `
    -FrontendIpConfiguration $feip `
    -BackendAddressPool $bepool `
    -Probe $probe `
    -LoadBalancingRule $rule `
    -Tag @{"CreatedBy"="Emyrs"} -Force
```

### 7. Create Outbound Rule (Recommended for SNAT)
```powershell
# Get the LB first
$lb = Get-AzLoadBalancer -Name "myslb" -ResourceGroupName $rg
$feip = $lb.FrontendIpConfigurations[0]
$bepool = $lb.BackendAddressPools[0]

# Add outbound rule
$outboundRule = New-AzLoadBalancerOutboundRuleConfig -Name "outbound" `
    -FrontendIpConfiguration $feip `
    -BackendAddressPool $bepool `
    -Protocol All `
    -IdleTimeoutInMinutes 15 `
    -AllocatedOutboundPort 10000

$lb.OutboundRules.Add($outboundRule)
Set-AzLoadBalancer -LoadBalancer $lb
```

### 8. Add VM NIC to Backend Pool
```powershell
$lb = Get-AzLoadBalancer -Name "myslb" -ResourceGroupName $rg
$bepool = $lb | Get-AzLoadBalancerBackendAddressPoolConfig -Name "backendpool"

$nic = Get-AzNetworkInterface -Name "vm1-nic" -ResourceGroupName $rg
$nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $bepool
$nic | Set-AzNetworkInterface
```

### 9. Add VMSS to Backend Pool (during creation)
```powershell
$ipConfig = New-AzVmssIpConfig -Name "ipconfig1" -SubnetId $subnet.Id -Primary `
    -LoadBalancerBackendAddressPoolsId $bepool.Id
```

## Outbound Connectivity Methods (Priority Order)
1. **NAT Gateway** - Best, recommended for most scenarios
2. **Public IP on VM** - Static 1:1 NAT
3. **LB Outbound Rules** - Explicit SNAT control
4. **LB without Outbound Rules** - Implicit, not recommended
5. **Default Outbound Access** - Worst, being deprecated

## SNAT Port Allocation
- Each public IP provides 64,000 ports
- Default allocation based on backend pool size
- Use outbound rules to manually control port allocation
- Formula: `Frontend IPs * 64K / Backend instances`

## Limitations
- Can't span two VNets
- Backend must be in same VNet as frontend (for internal LB)
- No ICMP support
- IP fragments not supported
- Health probe source IP (168.63.129.16) must be allowed

## HA Ports (All Ports Load Balancing)
```powershell
# Load balance ALL TCP/UDP ports (useful for NVA scenarios)
$rule = New-AzLoadBalancerRuleConfig -Name "ha-rule" `
    -Protocol All -FrontendPort 0 -BackendPort 0 `
    -FrontendIpConfiguration $feip -BackendAddressPool $bepool `
    -Probe $probe -EnableFloatingIP
```
