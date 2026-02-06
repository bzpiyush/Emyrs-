<#
.SYNOPSIS
    Cleanup resources after Emyrs migration testing

.DESCRIPTION
    Deletes the resource group and all resources created for migration testing

.PARAMETER ResourceGroupName
    Name of the resource group to delete

.EXAMPLE
    .\Cleanup-TestResources.ps1 -ResourceGroupName "emyrs-test-rg"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║          EMYRS - Resource Cleanup                              ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

    $rgExists = az group exists --name $ResourceGroupName
    if ($rgExists -eq "false") {
        Write-Host "Resource group '$ResourceGroupName' does not exist." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "`nResources that will be deleted:" -ForegroundColor Yellow
    az resource list --resource-group $ResourceGroupName --query "[].{Name:name, Type:type}" -o table

    if (-not $Force) {
        Write-Host "`nAre you sure you want to delete '$ResourceGroupName' and ALL its resources? (y/n): " -ForegroundColor Red -NoNewline
        $confirm = Read-Host
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "Cleanup cancelled." -ForegroundColor Yellow
            exit 0
        }
    }

    Write-Host "`nDeleting resource group '$ResourceGroupName'..." -ForegroundColor Yellow
    az group delete --name $ResourceGroupName --yes --no-wait

    Write-Host "Resource group deletion initiated (running in background)." -ForegroundColor Green
    Write-Host "Check status with: az group show -n $ResourceGroupName" -ForegroundColor Gray
}
catch {
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
