<#
.SYNOPSIS
    Deploy resources for Emyrs (Merlin migration) testing scenarios

.DESCRIPTION
    This script deploys Azure resources for various migration testing scenarios.
    Uses your existing Azure CLI login credentials.

.PARAMETER Scenario
    The migration scenario to deploy. Valid values:
    - single-vm
    - single-tenant-vmss
    - standard-lb-vm-backend
    - pseudo-vip

.PARAMETER ResourceGroupName
    Name of the resource group to create/use

.PARAMETER Location
    Azure region for deployment. For testing use:
    - useast2euap (East Canary)
    - uscentraleuap (Central Canary)

.PARAMETER VmCount
    Number of VMs to create (for multi-VM scenarios)

.EXAMPLE
    .\Deploy-TestResources.ps1 -Scenario "pseudo-vip" -ResourceGroupName "emyrs-test-rg" -Location "useast2euap" -VmCount 2
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("single-vm", "single-tenant-vmss", "standard-lb-vm-backend", "pseudo-vip")]
    [string]$Scenario,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [ValidateSet("useast2euap", "uscentraleuap", "eastus2", "centralus")]
    [string]$Location = "useast2euap",

    [Parameter(Mandatory = $false)]
    [int]$VmCount = 2,

    [Parameter(Mandatory = $false)]
    [string]$AdminUsername = "azureuser",

    [Parameter(Mandatory = $false)]
    [string]$DeploymentPrefix = "emyrs-test"
)

$ErrorActionPreference = "Stop"

# Script root directory
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$TemplatesRoot = Join-Path (Split-Path $ScriptRoot -Parent) "deployment-templates"

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Test-AzureLogin {
    Write-Step "Checking Azure CLI login status"
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        if ($account) {
            Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green
            Write-Host "Subscription: $($account.name) ($($account.id))" -ForegroundColor Green
            return $account
        }
    }
    catch {
        Write-Host "Not logged in to Azure CLI" -ForegroundColor Yellow
        return $null
    }
    return $null
}

function New-SecurePassword {
    $length = 16
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
    $password = -join ((1..$length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $password
}

function Deploy-Scenario {
    param(
        [string]$Scenario,
        [string]$ResourceGroupName,
        [string]$Location,
        [int]$VmCount,
        [string]$AdminUsername,
        [string]$DeploymentPrefix
    )

    $templatePath = Join-Path $TemplatesRoot $Scenario "azuredeploy.json"
    
    if (-not (Test-Path $templatePath)) {
        throw "Template not found: $templatePath"
    }

    Write-Step "Creating Resource Group: $ResourceGroupName in $Location"
    az group create --name $ResourceGroupName --location $Location --output none

    Write-Step "Deploying $Scenario scenario"
    
    $adminPassword = New-SecurePassword
    Write-Host "Generated admin password (save this!): $adminPassword" -ForegroundColor Yellow

    $deploymentName = "emyrs-$Scenario-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    switch ($Scenario) {
        "single-vm" {
            $result = az deployment group create `
                --resource-group $ResourceGroupName `
                --name $deploymentName `
                --template-file $templatePath `
                --parameters vmName="$DeploymentPrefix-vm" `
                --parameters adminUsername=$AdminUsername `
                --parameters adminPassword=$adminPassword `
                --parameters location=$Location `
                --output json | ConvertFrom-Json
        }
        "pseudo-vip" {
            $result = az deployment group create `
                --resource-group $ResourceGroupName `
                --name $deploymentName `
                --template-file $templatePath `
                --parameters deploymentPrefix=$DeploymentPrefix `
                --parameters vmCount=$VmCount `
                --parameters adminUsername=$AdminUsername `
                --parameters adminPassword=$adminPassword `
                --parameters location=$Location `
                --output json | ConvertFrom-Json
        }
        "single-tenant-vmss" {
            $result = az deployment group create `
                --resource-group $ResourceGroupName `
                --name $deploymentName `
                --template-file $templatePath `
                --parameters vmssName="$DeploymentPrefix-vmss" `
                --parameters instanceCount=$VmCount `
                --parameters adminUsername=$AdminUsername `
                --parameters adminPassword=$adminPassword `
                --parameters location=$Location `
                --output json | ConvertFrom-Json
        }
        "standard-lb-vm-backend" {
            $result = az deployment group create `
                --resource-group $ResourceGroupName `
                --name $deploymentName `
                --template-file $templatePath `
                --parameters deploymentPrefix=$DeploymentPrefix `
                --parameters vmCount=$VmCount `
                --parameters adminUsername=$AdminUsername `
                --parameters adminPassword=$adminPassword `
                --parameters location=$Location `
                --output json | ConvertFrom-Json
        }
    }

    if ($result.properties.provisioningState -eq "Succeeded") {
        Write-Host "`nDeployment Succeeded!" -ForegroundColor Green
        return $result
    }
    else {
        throw "Deployment failed: $($result.properties.provisioningState)"
    }
}

function Get-DeployedVMDetails {
    param([string]$ResourceGroupName)
    
    Write-Step "Getting VM details"
    
    $vms = az vm list --resource-group $ResourceGroupName --show-details --output json | ConvertFrom-Json
    
    $vmDetails = @()
    foreach ($vm in $vms) {
        $vmDetails += @{
            Name = $vm.name
            ResourceId = $vm.id
            VmId = $vm.vmId  # This is the virtualMachineUniqueId!
            Location = $vm.location
            PrivateIp = $vm.privateIps
            PublicIp = $vm.publicIps
        }
    }
    
    return $vmDetails
}

function Show-NextSteps {
    param($VmDetails, [string]$SubscriptionId, [string]$Location)
    
    # Determine AzMove endpoint based on location
    $azMoveEndpoint = switch ($Location) {
        "useast2euap" { "useast2euap-prod-b" }
        "uscentraleuap" { "uscentraleuap-prod-b" }
        default { "<REGION>-prod-b" }
    }
    
    Write-Host "`n" -NoNewline
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "                    EMYRS - NEXT STEPS                          " -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    Write-Host "`n📋 DEPLOYED VMs:" -ForegroundColor Yellow
    foreach ($vm in $VmDetails) {
        Write-Host "   VM Name: $($vm.Name)" -ForegroundColor White
        Write-Host "   VM Unique ID: $($vm.VmId)" -ForegroundColor Green
        Write-Host "   Resource ID: $($vm.ResourceId)" -ForegroundColor Gray
        Write-Host ""
    }

    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "STEP 1: Query Kusto to get Tenant Name" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Wait ~5-15 minutes for data to appear in Kusto, then run:" -ForegroundColor White
    Write-Host ""
    
    foreach ($vm in $VmDetails) {
        Write-Host "// For VM: $($vm.Name)" -ForegroundColor Gray
        Write-Host @"
LogContainerSnapshot
| where PreciseTimeStamp > ago(1d)
| where virtualMachineUniqueId contains "$($vm.VmId)"
| order by PreciseTimeStamp desc
| project PreciseTimeStamp, Tenant, tenantName
| limit 1
"@ -ForegroundColor Cyan
        Write-Host ""
    }

    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "STEP 2: Generate Migration Commands" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Come back to Copilot and say:" -ForegroundColor White
    Write-Host '  "I have the tenant name: <TENANT_NAME_FROM_KUSTO>"' -ForegroundColor Green
    Write-Host "Copilot will generate the complete AzMove FcShell commands" -ForegroundColor White
    
    Write-Host "`n════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "QUICK REFERENCE:" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Subscription ID: $SubscriptionId" -ForegroundColor White
    Write-Host "Region: $Location" -ForegroundColor White
    Write-Host "AzMove Endpoint: $azMoveEndpoint" -ForegroundColor White
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

# ==================== MAIN ====================
try {
    Write-Host "`n" -NoNewline
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║          EMYRS - Merlin Migration Test Deployer                ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host "Scenario: $Scenario" -ForegroundColor White
    Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "Location: $Location" -ForegroundColor White
    if ($Scenario -in @("pseudo-vip", "standard-lb-vm-backend", "single-tenant-vmss")) {
        Write-Host "VM/Instance Count: $VmCount" -ForegroundColor White
    }

    $account = Test-AzureLogin
    if (-not $account) {
        Write-Host "Please login to Azure CLI first: az login" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "`nProceed with deployment? (y/n): " -ForegroundColor Yellow -NoNewline
    $confirm = Read-Host
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        exit 0
    }

    # Deploy
    $deploymentResult = Deploy-Scenario `
        -Scenario $Scenario `
        -ResourceGroupName $ResourceGroupName `
        -Location $Location `
        -VmCount $VmCount `
        -AdminUsername $AdminUsername `
        -DeploymentPrefix $DeploymentPrefix

    # Get VM details including vmId (virtualMachineUniqueId)
    $vmDetails = Get-DeployedVMDetails -ResourceGroupName $ResourceGroupName
    
    # Show next steps
    Show-NextSteps -VmDetails $vmDetails -SubscriptionId $account.id -Location $Location
}
catch {
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
