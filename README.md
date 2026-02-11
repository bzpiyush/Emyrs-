# Emyrs — Merlin Migration Testing Assistant

> An AI-powered automation assistant for Azure Merlin migration testing. Emyrs creates test infrastructure, queries Kusto for tenant info, generates AzMove scripts, and verifies migration results — all through natural language.

---

## What Does Emyrs Do?

Emyrs automates the end-to-end Merlin migration testing workflow:

```
1. Create Infrastructure  →  VMs / VMSS / Load Balancers in Azure canary regions
2. Query Kusto            →  Get TenantName, ClusterName (FabricId) from AzureCP
3. Generate AzMove Script →  Ready-to-run script for SAW execution
4. Verify Migration       →  Analyze AzMoveDiagnostics logs and generate reports
```

### Example Usage

Open VS Code, switch to the **Emyrs** chat mode, and just say:

```
"Create 2 VMs in centraluseuap for migration testing"
"Query kusto for my VM"
"Check migration status for tenant xyz"
"Clean up piyushrg"
```

Emyrs handles everything — no manual commands needed.

---

## Prerequisites

| Requirement | How to install |
|---|---|
| **VS Code** | Latest version with GitHub Copilot (Chat + Agent mode) |
| **Azure PowerShell** | `Install-Module -Name Az -AllowClobber -Scope CurrentUser` |
| **Azure Login** | `Connect-AzAccount` |
| **uv** (Python package runner) | `winget install astral-sh.uv` or `pip install uv` or [astral.sh/uv](https://docs.astral.sh/uv/) |
| **Subscription Access** | Access to an Azure subscription for Merlin testing |

> **You do NOT need to install:** Kusto Explorer, Azure Data Explorer extension, or any MCP extension. Everything is built-in.

---

## ⚡ Quick Start

### 1. Clone the repo
```bash
git clone https://github.com/bzpiyush/Emyrs-.git
cd Emyrs
```

### 2. Open in VS Code
```bash
code .
```

### 3. Login to Azure
```powershell
Connect-AzAccount
```

### 4. Allow MCP servers
When VS Code opens the repo, it will prompt:
> "Allow MCP servers to start?"

Click **Allow**. This starts two Kusto MCP servers (AzureCP + AzureCM). `uvx` will auto-download the `microsoft-fabric-rti-mcp` package on first run — no manual install needed.

### 5. Switch to Emyrs chat mode
- Open Copilot Chat → Click the chat mode dropdown → Select **"emyrs"**
- Start talking: `"Create a VM in eastus2euap for Merlin testing"`

---

## 📁 Project Structure

```
Emyrs/
├── .github/
│   ├── chatmodes/
│   │   └── emyrs.chatmode.md        # Main Emyrs persona & instructions
│   ├── skills/
│   │   └── merlin-migration/
│   │       └── SKILL.md             # Migration workflow skill
│   └── copilot-instructions.md      # Repo-wide Copilot instructions
├── .vscode/
│   ├── settings.json                # VS Code & Copilot settings
│   └── mcp.json                     # Kusto MCP server configuration
├── templates/
│   ├── VM.md                        # VM creation reference
│   ├── VMSS.md                      # VMSS creation reference
│   ├── LoadBalancer-Standard.md     # Standard LB reference
│   ├── LoadBalancer-Basic.md        # Basic LB reference
│   └── PseudoVIP.md                 # Pseudo VIP / Floating IP reference
├── tools/
│   └── Test-StreamConnectivity.ps1  # TCP stream ping for migration testing
├── AGENTS.md                        # Agent instructions (build, test, cleanup)
└── README.md                        # This file
```

---

## 🔧 Key Components

### Chat Mode (`.github/chatmodes/emyrs.chatmode.md`)
The main brain of Emyrs. Defines the persona, deployment logic, Kusto integration, AzMove script generation, and migration verification workflows.

### Kusto MCP Servers (`.vscode/mcp.json`)
Two MCP (Model Context Protocol) servers for direct Kusto access:

| Server | Cluster | Database | Purpose |
|---|---|---|---|
| `kusto-azurecp` | `azcore.centralus.kusto.windows.net` | AzureCP | Tenant info (`MycroftContainerSnapshot_Latest`) |
| `kusto-azurecm` | `azurecm.kusto.windows.net` | AzureCM | Migration logs (`AzMoveDiagnostics`) |

### Templates (`templates/`)
Resource creation references that Emyrs reads dynamically based on what you ask for. Each template contains the correct PowerShell commands, tagging rules, and edge case handling.

### Tools (`tools/`)
- **`Test-StreamConnectivity.ps1`** — TCP-based continuous ping script. Run inside a VM (via RDP) to prove zero packet loss during migration. Uses TCP instead of ICMP to work regardless of firewall/NSG settings.

---

## 🌍 Supported Canary Regions

| Region | Preferred |
|---|---|
| `centraluseuap` | ✅ Primary |
| `eastus2euap` | ✅ Fallback |

---

## 📖 Migration Workflow

### Step 1: Create Test Infrastructure
Tell Emyrs what you need. It creates the full stack (RG, VNet, Subnet, NSG, PIPs, NICs, VMs).

```
"Create 3 VMs across 2 subnets with a Standard Load Balancer"
```

### Step 2: Query Kusto
After VMs are running (wait 5-15 min), Emyrs queries `MycroftContainerSnapshot_Latest` for:
- **TenantName** — Tenant identifier
- **ClusterName** — FabricId for AzMove
- **Cluster** — Azure cluster name
- **NodeId** — Physical node

```
"Query kusto for my VM"
```

### Step 3: Generate AzMove Script
Emyrs generates the FcShell script with all the correct fixed values:

| Parameter | Value |
|---|---|
| `RegionalNetworkResourceChannelType` | `ViaPubSub` |
| `VipGoalStateChannelType` | `ViaPubSub` |
| `RollbackMode` | `Optimized` |

Copy the script and run it on **SAW** (FcShell).

### Step 4: Verify Migration
After running the AzMove script on SAW, Emyrs queries `AzMoveDiagnostics` and generates a detailed report:

```
"Check migration status"
```

Reports include phase-by-phase breakdown (Validation → Lock → Migration → Cleanup) with ✅/❌ status indicators.

---

## 🔌 Connectivity Testing

For proving zero packet loss during migration:

1. RDP into one of your VMs
2. Copy `tools/Test-StreamConnectivity.ps1` to the VM
3. Run it targeting the other VM's private IP:

```powershell
.\Test-StreamConnectivity.ps1 -TargetIP "10.0.0.5" -Count 500 -Port 3389
```

---

## 🧹 Cleanup

Just tell Emyrs:
```
"Clean up piyushrg"
```

Or manually:
```powershell
Remove-AzResourceGroup -Name "<RG_NAME>" -Force -AsJob
```

---

## ⚠️ Important Notes

- **TipNode.SessionId** — Mandatory tag for all VMs in Merlin testing. Emyrs will ask for it unless you say otherwise.
- **Kusto queries are automatic** — Emyrs uses MCP tools to query Kusto directly; you never need to run queries manually.
- **Canary regions can be unstable** — These are pre-production regions. Transient errors (like `DiskServiceInternalError`) can occur. Emyrs handles retries and region fallback automatically.
- **AzMove scripts run on SAW** — The generated migration scripts must be executed on a SAW machine with FcShell, not locally.

---

## �️ Troubleshooting

| Problem | Fix |
|---|---|
| MCP servers don't start | Make sure `uv` is installed: run `uvx --version` in terminal. If not found, install with `winget install astral-sh.uv` |
| "Not authenticated" Kusto errors | Run `Connect-AzAccount` or `az login` in the terminal |
| No "emyrs" chat mode in dropdown | Ensure the `.github/chatmodes/` folder is present and restart VS Code |
| VM creation fails with `DiskServiceInternalError` | Canary region issue — ask Emyrs to retry in the other region |
| `SubscriptionNotRegisteredForFeature` on Public IP | The subscription doesn't support `FirstPartyUsage` IP tags — Emyrs handles this automatically by falling back to resource tags |

---

## �👥 Team

Built for the **Merlin Migration Testing** team.

---