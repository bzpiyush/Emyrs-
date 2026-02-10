# Emyrs Agent Instructions

<identity>
You are working on **Emyrs**, a Merlin migration testing automation project for Azure infrastructure.
</identity>

<critical_requirements>
## CRITICAL - Read Before Any Action

1. **TipNode.SessionId Tag** - MANDATORY for all VMs. Always ask for this GUID before deployment.
2. **Kusto MCP Tools** - Use them directly, never ask users to run queries manually.
3. **Execute Commands** - Run commands yourself, don't just show them.
4. **Confirm Before Deploy** - Show deployment plan and wait for approval.
</critical_requirements>

<build_instructions>
## Build & Run Instructions

This project is primarily PowerShell-based and doesn't require traditional builds.

### Prerequisites:
```powershell
# Install Azure PowerShell module
Install-Module -Name Az -AllowClobber -Scope CurrentUser

# Login to Azure
Connect-AzAccount
```

### Validation:
```powershell
# Verify Azure connection
Get-AzContext

# Verify subscription access
Get-AzSubscription
```
</build_instructions>

<project_layout>
## Project Layout

```
Emyrs/
├── .github/
│   ├── chatmodes/emyrs.chatmode.md  # Main chatmode (Copilot instructions)
│   ├── skills/merlin-migration/      # Agent skill for migrations
│   └── copilot-instructions.md       # Repository-wide instructions
├── .vscode/
│   ├── settings.json                 # Auto-approve, MCP settings
│   └── mcp.json                      # Kusto MCP server config
├── Docs/                             # Documentation folder
└── AGENTS.md                         # This file
```
</project_layout>

<kusto_configuration>
## Kusto Cluster Access

### AzureCP (Primary):
- URI: `https://azcore.centralus.kusto.windows.net`
- Database: `AzureCP` 
- Table: `MycroftContainerSnapshot_Latest`

### AzureCM (Secondary):
- URI: `https://azurecm.kusto.windows.net`
- Database: `AzureCM`

### MCP Tools Available:
- `mcp_kusto-azurecp_kusto_query` - Query AzureCP
- `mcp_kusto-azurecm_kusto_query` - Query AzureCM
- `mcp_kusto-azurecp_kusto_sample_entity` - Sample data
</kusto_configuration>

<azmove_constants>
## AzMove Fixed Values

Always use these in migration scripts:
- `RegionalNetworkResourceChannelType` = "ViaPubSub"
- `VipGoalStateChannelType` = "ViaPubSub"
- `RollbackMode` = "Optimized"
</azmove_constants>

<regions>
## Canary Regions

For Merlin testing:
- `centraluseuap`
- `eastus2euap`
</regions>

<workflow>
## Standard Workflow

1. **Create Infrastructure** → VMs/LBs/VMSS with TipNode.SessionId tag
2. **Wait** → 5-15 minutes for VM to appear in Kusto
3. **Query Kusto** → Get TenantName, ClusterName (FabricId)
4. **Generate AzMove Script** → For SAW execution
5. **Run Validation** → Always validate before migrating
6. **Execute Migration** → Run migration API
7. **Verify** → Check AzMoveDiagnostic table
</workflow>

<testing>
## Testing

### Network Connectivity Testing:
Use `Invoke-AzVMRunCommand` to test connectivity between VMs (private IPs aren't routable from outside):

```powershell
Invoke-AzVMRunCommand `
    -ResourceGroupName "<RG>" `
    -VMName "<SOURCE_VM>" `
    -CommandId "RunPowerShellScript" `
    -ScriptString "ping <TARGET_PRIVATE_IP> -n 4"
```
</testing>

<cleanup>
## Cleanup

```powershell
Remove-AzResourceGroup -Name "<RG_NAME>" -Force -AsJob
```
</cleanup>
