# 🧙 Emyrs - Merlin Migration Automation Tool

> *Emyrs* - the Welsh name for Merlin the wizard. Because migrating to Merlin should feel like magic! ✨

This tool automates the testing workflow for Merlin migration using AzMove APIs.

## 🎯 What Emyrs Does

| Step | Action | Automated? |
|------|--------|------------|
| 1 | Create test resources (VMs, LB, VMSS) | ✅ ARM Templates |
| 2 | Get VM Unique IDs | ✅ Script output |
| 3 | Query Kusto for Tenant Name | ✅ MCP Server |
| 4 | Generate AzMove FcShell commands | ✅ Copilot |
| 5 | Take JIT + Run APIs on SAW | ❌ Manual |
| 6 | Check migration results | ✅ MCP Server |

## 📋 Supported Scenarios

| Scenario | Description |
|----------|-------------|
| `single-vm` | Single VM migration |
| `single-tenant-vmss` | Single tenant VMSS migration |
| `standard-lb-vm-backend` | Standard LB with VM backend pool |
| `pseudo-vip` | Pseudo VIP with multiple VMs |

## 🔧 Prerequisites

### 1. Azure CLI
```powershell
# Install Azure CLI
winget install Microsoft.AzureCLI

# Login with your credentials
az login
```

### 2. UV Package Manager (Required for Kusto MCP Server)

The MCP server uses `uvx` to run the Kusto connector. Install it:

```powershell
# Option 1: Install via PowerShell (Recommended)
irm https://astral.sh/uv/install.ps1 | iex

# Option 2: If you have pip
pip install uv
```

After installation, **restart your terminal** or add to PATH manually:
```powershell
$env:Path = "C:\Users\$env:USERNAME\.local\bin;$env:Path"
```

Verify installation:
```powershell
uvx --version
# Should show: uvx 0.10.x or higher
```

### 3. VS Code with GitHub Copilot
- Install [GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot) extension
- Install [GitHub Copilot Chat](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat) extension

### 4. MCP Server Setup (One-time)

The `.mcp.json` file in this folder configures the Kusto MCP server. VS Code + Copilot will auto-detect it.

**How it works:**
- When you open this folder in VS Code, Copilot reads `.mcp.json`
- The MCP server (`microsoft-fabric-rti-mcp`) connects to AzureCM Kusto
- Authentication uses your Azure AD credentials from `az login`

**First-time setup:**
1. Open this `emyrs` folder in VS Code
2. Open Copilot Chat (Ctrl+Shift+I)
3. The MCP server will auto-download via `uvx` on first use
4. You may see a prompt to allow the MCP server - click **Allow**

**Troubleshooting MCP:**
| Issue | Solution |
|-------|----------|
| `uvx not found` | Restart VS Code after installing uv |
| Auth errors | Run `az login` and try again |
| MCP not loading | Check `.mcp.json` exists in workspace root |

## 📁 Folder Structure

```
emyrs/
├── .github/
│   └── copilot-instructions.md  # Copilot behavior instructions
├── .vscode/
│   └── tasks.json               # VS Code tasks with input forms
├── .mcp.json                    # Kusto MCP config (AzureCM)
├── README.md                    # This file
├── deployment-templates/        # ARM templates
│   ├── single-vm/
│   ├── single-tenant-vmss/
│   ├── standard-lb-vm-backend/
│   └── pseudo-vip/
├── scripts/
│   ├── Deploy-TestResources.ps1
│   ├── Cleanup-TestResources.ps1
│   └── Start-MigrationWizard.ps1  # Interactive wizard!
├── api-templates/
│   ├── azmove-migration.json
│   └── azmove-complete-script.ps1
└── kusto-queries/
    ├── get-tenant-from-vm.kql
    ├── get-tenants-for-multiple-vms.kql
    ├── check-migration-status.kql
    └── migration-summary.kql
```

## 🎮 Three Ways to Use Emyrs

### Option 1: Interactive Wizard (Recommended for beginners)
```powershell
.\scripts\Start-MigrationWizard.ps1
```
Step-by-step prompts guide you through the entire process.

### Option 2: VS Code Tasks (Input forms)
Press `Ctrl+Shift+P` → "Tasks: Run Task" → Select an Emyrs task:
- 🚀 Deploy Test Resources
- 🔍 Query Kusto for Tenant Info
- 📝 Generate AzMove Script
- 🔎 Check Migration Status
- 🧹 Cleanup Resources

### Option 3: Copilot Chat (Natural language)
Just tell Copilot what you want in plain English!

## 🚀 Usage Workflow

### Step 1: Tell Copilot What You Want

```
You: "I want to test pseudo VIP migration with 2 VMs in East Canary"

Copilot: "I'll create a Pseudo VIP setup with:
         - Scenario: pseudo-vip
         - VM Count: 2
         - Region: useast2euap (East Canary)
         Confirm? (yes/no)"

You: "yes"
```

### Step 2: Copilot Creates Resources

Copilot runs the deployment script and gives you:
- Resource Group name
- VM Unique IDs (needed for Kusto query)
- Subscription ID

### Step 3: Get Tenant Name from Kusto

Wait ~5-15 minutes for data to appear, then Copilot queries:

```kql
cluster('azcore.centralus.kusto.windows.net').database('AzureCP').
MycroftContainerSnapshot_Latest
| where PreciseTimeStamp > ago(100d)
| where VirtualMachineUniqueId == "<VM_UNIQUE_ID>"
| project 
    PreciseTimeStamp, 
    AzMoveEndpoint = Cluster,      // "uscentraleuap-prod-b"
    TenantName,                     // "20499ca6-ab49-46ff-968e-7aedddcbd95e"
    FabricId = ClusterName          // "CDM06PrdApp17"
```

**Kusto Output Mapping:**
| Kusto Column | AzMove Parameter | Example |
|--------------|------------------|---------|
| `Cluster` | `Get-AzMove -Name` | `uscentraleuap-prod-b` |
| `TenantName` | `$tenantName` | `20499ca6-ab49-46ff-968e-7aedddcbd95e` |
| `ClusterName` | `FabricId` | `CDM06PrdApp17` |

> **Important**: Tenant-based migration! One tenant can have one or multiple VMs. 
> If you have multiple VMs, Copilot will check if they share the same tenant.
> - Same tenant → Single migration command
> - Different tenants → Separate commands for each tenant

### Step 4: Get Migration Commands

Copilot generates the complete FcShell script:

```powershell
# AzMove endpoint comes directly from Kusto "Cluster" column!
$AzMove = Get-AzMove -Name uscentraleuap-prod-b

$crpSubscriptionId = "<YOUR_SUBSCRIPTION_ID>"
$tenantName = "<TENANT_NAME_FROM_KUSTO>"      # From Kusto: TenantName
$fabricId = "<CLUSTER_NAME_FROM_KUSTO>"       # From Kusto: ClusterName (e.g., CDM06PrdApp17)

$migrationInput = New-AzMoveObject AzMove.Controller.MigrateRunningTenantToMerlinInput
$migrationInput | Update-AzMoveObject -PropertyName FabricId -PropertyValue $fabricId
$migrationInput | Update-AzMoveObject -PropertyName NrpSubscriptionId -PropertyValue $crpSubscriptionId
$migrationInput | Update-AzMoveObject -PropertyName RegionalNetworkResourceChannelType -PropertyValue "ViaPubSub"
$migrationInput | Update-AzMoveObject -PropertyName VipGoalStateChannelType -PropertyValue "ViaPubSub"
$migrationInput | Update-AzMoveObject -PropertyName RollbackMode -PropertyValue "Optimized"

# VALIDATE FIRST!
$result = ($AzMove | Invoke-AzMoveApi -MethodName AzMoveService_ValidateMigrateRunningTenantToMerlinAsyncByCrpsubscriptionidTenantnameMigrationinputAsync -Parameters @($crpSubscriptionId, $tenantName, $migrationInput)).Result

# THEN MIGRATE (after validation passes)
$result = ($AzMove | Invoke-AzMoveApi -MethodName AzMoveService_MigrateRunningTenantToMerlinAsyncByCrpsubscriptionidTenantnameMigrationinputAsync -Parameters @($crpSubscriptionId, $tenantName, $migrationInput)).Result
```

### Step 5: Run on SAW Machine (Manual)

1. Take JIT access
2. Copy the generated script
3. Run Validate API first
4. If validation passes, run Migrate API

### Step 6: Check Results

Come back and tell Copilot:

```
You: "I ran the validation API"
# or
You: "I ran both APIs"
```

Copilot queries AzMoveDiagnostics:

```kql
AzMoveDiagnostics
| where PreciseTimeStamp > ago(1d)
| where * contains "<TENANT_NAME>"
| order by PreciseTimeStamp desc
```

## 🌍 Region Configuration

| Region | Endpoint | AZs | Notes |
|--------|----------|-----|-------|
| `useast2euap` | `useast2euap-prod-b` | a, b, c, d | East Canary (default to b) |
| `uscentraleuap` | `uscentraleuap-prod-b` | b only | Central Canary (always b) |

## 📝 Fixed vs Dynamic Values

### Always Fixed (Never Change)
| Parameter | Value |
|-----------|-------|
| `RegionalNetworkResourceChannelType` | `"ViaPubSub"` |
| `VipGoalStateChannelType` | `"ViaPubSub"` |
| `RollbackMode` | `"Optimized"` |

### Dynamic (From Kusto/Deployment)
| Parameter | Kusto Source | Example |
|-----------|--------------|---------|
| `crpSubscriptionId` | Your Azure subscription | `513cee7a-0615-47f3-acf0-a1b8d501867c` |
| `Get-AzMove -Name` | `Cluster` column | `uscentraleuap-prod-b` |
| `$tenantName` | `TenantName` column | `20499ca6-ab49-46ff-968e-7aedddcbd95e` |
| `FabricId` | `ClusterName` column | `CDM06PrdApp17` |
| `NrpSubscriptionId` | Same as crpSubscriptionId | `513cee7a-0615-47f3-acf0-a1b8d501867c` |

## ⚠️ Important Notes

1. **Never assume values** - Always get from Kusto query (`MycroftContainerSnapshot_Latest`)
2. **Wait for Kusto data** - Can take 5-15 minutes after deployment
3. **Tenant-based migration** - Multiple VMs may share a tenant
4. **Validate first** - Always run validation API before migration
5. **Check both APIs** - Tell Copilot which API(s) you ran

## 🧹 Cleanup

After testing:
```powershell
.\scripts\Cleanup-TestResources.ps1 -ResourceGroupName "emyrs-test-rg"
```

## 🔐 Authentication

| Component | Method |
|-----------|--------|
| Azure Resources | `az login` (your credentials) |
| Kusto Queries | MCP Server (auto uses your Azure AD token) |
| AzMove APIs | JIT access on SAW machine |

---

*Built with 🧙 by the Emyrs team*
