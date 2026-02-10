# Copilot Instructions for Emyrs Project

<project_context>
## Project Overview

This is **Emyrs**, a Merlin migration testing automation project. It helps create Azure test infrastructure and automate the migration testing workflow.

**Purpose**: Automate the end-to-end Merlin migration testing process:
1. Create test VMs/VMSS/LBs in Azure
2. Query Kusto for tenant information
3. Generate AzMove API scripts for SAW execution
4. Verify migration results
</project_context>

<tech_stack>
## Technology Stack

- **Languages**: PowerShell, KQL (Kusto Query Language)
- **Cloud**: Azure (VMs, VMSS, Load Balancers, VNets, NSGs)
- **Data**: Azure Data Explorer (Kusto) - AzureCP and AzureCM clusters
- **Tools**: Azure PowerShell Az module, MCP (Model Context Protocol)
</tech_stack>

<critical_rules>
## Critical Rules - NEVER Violate

1. **TipNode.SessionId is MANDATORY** - Every VM must have this tag untill user says otherwise. Always ask user for a GUID to use.
2. **Always use Kusto MCP tools** - Never tell users to run queries manually
3. **Execute commands yourself** - Use `run_in_terminal`, don't show commands
4. **Confirm before deploying** - Always show deployment plan first
5. **Verify Kusto schema** - Sample tables before querying to avoid errors
</critical_rules>

<kusto_config>
## Kusto Configuration

### AzureCP Cluster (Primary):
- URI: `https://azcore.centralus.kusto.windows.net`
- Database: `AzureCP`
- Key Table: `MycroftContainerSnapshot_Latest`

### AzureCM Cluster (Secondary):
- URI: `https://azurecm.kusto.windows.net`
- Database: `AzureCM`

### Known Good Columns (MycroftContainerSnapshot_Latest):
- `Cluster`, `TenantName`, `ClusterName`, `NodeId`, `VirtualMachineUniqueId`

### ⚠️ Avoid These (Don't Exist):
- `AllocationId`
</kusto_config>

<azure_regions>
## Azure Canary Regions

For Merlin testing, use these regions:
- `centraluseuap` (preferred)
- `eastus2euap`
</azure_regions>

<azmove_fixed_values>
## AzMove Fixed Values

Always use these values in migration scripts:
```
RegionalNetworkResourceChannelType = "ViaPubSub"
VipGoalStateChannelType = "ViaPubSub"  
RollbackMode = "Optimized"
```
</azmove_fixed_values>

<file_structure>
## Project Structure

```
Emyrs/
├── .github/
│   ├── chatmodes/
│   │   └── emyrs.chatmode.md    # Main chatmode definition
│   ├── skills/
│   │   └── merlin-migration/    # Migration skill
│   │       └── SKILL.md
│   └── copilot-instructions.md  # This file
├── .vscode/
│   ├── settings.json            # VS Code settings
│   └── mcp.json                 # Kusto MCP configuration
└── Docs/                        # Documentation
```
</file_structure>

<coding_standards>
## Coding Standards

### PowerShell:
- Use approved verbs (Get-, New-, Set-, Remove-)
- Always use `-Force` for non-interactive execution
- Include `-ErrorAction Stop` for critical commands
- Use splatting for commands with many parameters

### KQL:
- Always `| project` to limit columns returned
- Use `| take N` or `| limit N` to avoid large result sets
- Verify column names before querying
</coding_standards>
