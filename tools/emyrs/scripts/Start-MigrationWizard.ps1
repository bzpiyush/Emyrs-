<#
.SYNOPSIS
    Interactive Emyrs Migration Wizard

.DESCRIPTION
    Step-by-step wizard for Merlin migration testing.
    Guides you through deployment, Kusto queries, and API generation.

.EXAMPLE
    .\Start-MigrationWizard.ps1
#>

$ErrorActionPreference = "Stop"

function Show-Banner {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║              🧙 EMYRS - Migration Wizard 🧙                    ║" -ForegroundColor Magenta
    Write-Host "║                  Merlin Migration Testing                      ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
}

function Show-Menu {
    param([string]$Title, [string[]]$Options)
    
    Write-Host "`n$Title" -ForegroundColor Cyan
    Write-Host ("─" * 50) -ForegroundColor Gray
    
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  [$($i + 1)] $($Options[$i])" -ForegroundColor White
    }
    Write-Host ""
    
    do {
        $choice = Read-Host "Select option (1-$($Options.Count))"
    } while ($choice -lt 1 -or $choice -gt $Options.Count)
    
    return $choice - 1
}

function Get-Input {
    param(
        [string]$Prompt,
        [string]$Default = "",
        [switch]$Required
    )
    
    $displayPrompt = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    $value = Read-Host $displayPrompt
    
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = $Default
    }
    
    if ($Required -and [string]::IsNullOrWhiteSpace($value)) {
        Write-Host "This field is required!" -ForegroundColor Red
        return Get-Input -Prompt $Prompt -Default $Default -Required
    }
    
    return $value
}

function Show-Step {
    param([int]$Number, [string]$Title)
    Write-Host "`n" -NoNewline
    Write-Host "═══ STEP ${Number}: ${Title} ═══" -ForegroundColor Yellow
}

# ==================== MAIN WIZARD ====================

Show-Banner

# Store all inputs
$config = @{}

# Step 1: Choose Action
Show-Step -Number 1 -Title "Choose Action"
$actions = @(
    "Deploy new test resources",
    "Generate AzMove script (already have tenant info)",
    "Show Kusto query for tenant info",
    "Show Kusto query for migration status",
    "Cleanup resources"
)
$actionChoice = Show-Menu -Title "What would you like to do?" -Options $actions

switch ($actionChoice) {
    0 {
        # Deploy new resources
        Show-Step -Number 2 -Title "Deployment Configuration"
        
        # Scenario
        $scenarios = @("single-vm", "pseudo-vip", "single-tenant-vmss", "standard-lb-vm-backend")
        $scenarioChoice = Show-Menu -Title "Select migration scenario:" -Options $scenarios
        $config.Scenario = $scenarios[$scenarioChoice]
        
        # Region
        $regions = @("uscentraleuap (Central Canary)", "useast2euap (East Canary)")
        $regionChoice = Show-Menu -Title "Select region:" -Options $regions
        $config.Region = @("uscentraleuap", "useast2euap")[$regionChoice]
        
        # Resource Group
        $config.ResourceGroup = Get-Input -Prompt "Resource group name" -Default "emyrs-test-$($config.Scenario)-rg"
        
        # VM Count (if applicable)
        if ($config.Scenario -in @("pseudo-vip", "single-tenant-vmss", "standard-lb-vm-backend")) {
            $config.VmCount = Get-Input -Prompt "Number of VMs/instances" -Default "2"
        } else {
            $config.VmCount = "1"
        }
        
        # Confirm
        Show-Step -Number 3 -Title "Confirm Deployment"
        Write-Host "`nDeployment Summary:" -ForegroundColor White
        Write-Host "  Scenario:       $($config.Scenario)" -ForegroundColor Gray
        Write-Host "  Region:         $($config.Region)" -ForegroundColor Gray
        Write-Host "  Resource Group: $($config.ResourceGroup)" -ForegroundColor Gray
        Write-Host "  VM Count:       $($config.VmCount)" -ForegroundColor Gray
        
        $confirm = Get-Input -Prompt "`nProceed with deployment? (yes/no)" -Default "no"
        if ($confirm -eq "yes" -or $confirm -eq "y") {
            Write-Host "`nStarting deployment..." -ForegroundColor Green
            & "$PSScriptRoot\Deploy-TestResources.ps1" `
                -Scenario $config.Scenario `
                -ResourceGroupName $config.ResourceGroup `
                -Location $config.Region `
                -VmCount ([int]$config.VmCount)
        } else {
            Write-Host "Deployment cancelled." -ForegroundColor Yellow
        }
    }
    
    1 {
        # Generate AzMove script
        Show-Step -Number 2 -Title "Enter Values from Kusto"
        
        Write-Host "`nEnter values from your Kusto query (MycroftContainerSnapshot_Latest):" -ForegroundColor Cyan
        
        $config.SubscriptionId = Get-Input -Prompt "Subscription ID" -Required
        $config.AzMoveEndpoint = Get-Input -Prompt "Cluster (AzMove endpoint, e.g., uscentraleuap-prod-b)" -Required
        $config.TenantName = Get-Input -Prompt "TenantName" -Required
        $config.FabricId = Get-Input -Prompt "ClusterName (FabricId)" -Required
        
        Show-Step -Number 3 -Title "Generated AzMove Script"
        
        $script = @"

# ============================================================
# EMYRS - AzMove Migration Script
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ============================================================
# Run this on SAW machine after taking JIT access
# ============================================================

`$AzMove = Get-AzMove -Name $($config.AzMoveEndpoint)

`$crpSubscriptionId = "$($config.SubscriptionId)"
`$tenantName = "$($config.TenantName)"
`$fabricId = "$($config.FabricId)"

`$migrationInput = New-AzMoveObject AzMove.Controller.MigrateRunningTenantToMerlinInput
`$migrationInput | Update-AzMoveObject -PropertyName FabricId -PropertyValue `$fabricId
`$migrationInput | Update-AzMoveObject -PropertyName NrpSubscriptionId -PropertyValue `$crpSubscriptionId
`$migrationInput | Update-AzMoveObject -PropertyName RegionalNetworkResourceChannelType -PropertyValue "ViaPubSub"
`$migrationInput | Update-AzMoveObject -PropertyName VipGoalStateChannelType -PropertyValue "ViaPubSub"
`$migrationInput | Update-AzMoveObject -PropertyName RollbackMode -PropertyValue "Optimized"

# ==================== STEP 1: VALIDATE ====================
Write-Host "Running Validation API..." -ForegroundColor Yellow
`$validateResult = (`$AzMove | Invoke-AzMoveApi -MethodName AzMoveService_ValidateMigrateRunningTenantToMerlinAsyncByCrpsubscriptionidTenantnameMigrationinputAsync -Parameters @(`$crpSubscriptionId, `$tenantName, `$migrationInput)).Result
`$validateResult

# ==================== STEP 2: MIGRATE ====================
# Uncomment below after validation passes!
# Write-Host "Running Migration API..." -ForegroundColor Yellow
# `$migrateResult = (`$AzMove | Invoke-AzMoveApi -MethodName AzMoveService_MigrateRunningTenantToMerlinAsyncByCrpsubscriptionidTenantnameMigrationinputAsync -Parameters @(`$crpSubscriptionId, `$tenantName, `$migrationInput)).Result
# `$migrateResult
"@

        Write-Host $script -ForegroundColor White
        
        # Save to file
        $saveFile = Get-Input -Prompt "`nSave to file? (yes/no)" -Default "yes"
        if ($saveFile -eq "yes" -or $saveFile -eq "y") {
            $fileName = "azmove-script-$(Get-Date -Format 'yyyyMMdd-HHmmss').ps1"
            $filePath = Join-Path $PSScriptRoot $fileName
            $script | Out-File -FilePath $filePath -Encoding UTF8
            Write-Host "Saved to: $filePath" -ForegroundColor Green
        }
    }
    
    2 {
        # Show Kusto query for tenant
        Show-Step -Number 2 -Title "Kusto Query for Tenant Info"
        
        $vmId = Get-Input -Prompt "Enter VM Unique ID"
        
        Write-Host "`nRun this query in Kusto Explorer or Azure Data Explorer:" -ForegroundColor Cyan
        Write-Host @"

cluster('azcore.centralus.kusto.windows.net').database('AzureCP').
MycroftContainerSnapshot_Latest
| where VirtualMachineUniqueId == "$vmId"
| project 
    AzMoveEndpoint = Cluster,
    TenantName,
    FabricId = ClusterName
| take 1

"@ -ForegroundColor Yellow
    }
    
    3 {
        # Show migration status query
        Show-Step -Number 2 -Title "Kusto Query for Migration Status"
        
        $tenantName = Get-Input -Prompt "Enter TenantName"
        
        Write-Host "`nRun this query in Kusto:" -ForegroundColor Cyan
        Write-Host @"

AzMoveDiagnostics
| where PreciseTimeStamp > ago(1d)
| where * contains "$tenantName"
| order by PreciseTimeStamp desc
| project PreciseTimeStamp, OperationName, Status, Message
| limit 100

"@ -ForegroundColor Yellow
    }
    
    4 {
        # Cleanup
        Show-Step -Number 2 -Title "Cleanup Resources"
        
        $config.ResourceGroup = Get-Input -Prompt "Resource group to delete" -Required
        
        $confirm = Get-Input -Prompt "Are you sure you want to delete '$($config.ResourceGroup)'? (yes/no)" -Default "no"
        if ($confirm -eq "yes" -or $confirm -eq "y") {
            & "$PSScriptRoot\Cleanup-TestResources.ps1" -ResourceGroupName $config.ResourceGroup -Force
        } else {
            Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        }
    }
}

Write-Host "`n✨ Done! ✨`n" -ForegroundColor Green
