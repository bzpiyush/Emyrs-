---
name: merlin-migration
description: Guide for Merlin migration testing - creating test infrastructure, querying Kusto for tenant info, and generating AzMove scripts. Use this when asked about Merlin migrations, tenant queries, or AzMove API calls.
license: MIT
---

# Merlin Migration Testing Skill

This skill guides you through the complete Merlin migration testing workflow.

<overview>
## Migration Testing Workflow

1. **Create Infrastructure** → VMs, LBs, VMSS with proper tags
2. **Query Kusto** → Get tenant info (Cluster, TenantName, FabricId)
3. **Generate AzMove Script** → For execution on SAW machine
4. **Validate & Migrate** → Run validation before migration
5. **Check Results** → Query AzMoveDiagnostic table
</overview>

---

<step_1_infrastructure>
## Step 1: Create Test Infrastructure

### Required Components (ALWAYS create these):
- Resource Group
- VNet with appropriate subnets
- NSG with RDP rule (TCP 3389)
- Public IPs (Standard SKU)
- **TipNode.SessionId tag** (MANDATORY - always ask user)

### Test Scenarios:

| Scenario | Infrastructure |
|----------|----------------|
| Simple VM | 1 VM with PIP |
| Basic LB | Basic LB + 2 VMs in backend pool |
| Standard LB | Standard LB + VMs + health probe |
| Single-tenant VMSS | 1 VMSS (all instances same tenant) |
| Multi-tenant VMSS | Multiple VMSS or VMs across tenants |
| Pseudo VIP | VMs without public IPs, internal LB |

### Regions for Canary Testing:
- `centraluseuap`
- `eastus2euap`

### PowerShell Tag Example:
```powershell
$tags = @{
    "TipNode.SessionId" = "<USER_PROVIDED_GUID>"
    "CreatedBy" = "Emyrs"
    "Scenario" = "<scenario_type>"
}
```
</step_1_infrastructure>

---

<step_2_kusto>
## Step 2: Query Kusto for Tenant Info

### Cluster Details:
- **Cluster URI**: `https://azcore.centralus.kusto.windows.net`
- **Database**: `AzureCP`
- **Table**: `MycroftContainerSnapshot_Latest`

### Get VM's Tenant Info:
```kql
MycroftContainerSnapshot_Latest
| where VirtualMachineUniqueId == "<VM_UNIQUE_ID>"
| project Cluster, TenantName, ClusterName, NodeId, VirtualMachineUniqueId
| take 1
```

### Verified Columns in MycroftContainerSnapshot_Latest:
| Column | Description |
|--------|-------------|
| `Cluster` | Azure cluster name |
| `TenantName` | Tenant identifier for migration |
| `ClusterName` | FabricId for AzMove |
| `NodeId` | Physical node identifier |
| `VirtualMachineUniqueId` | VM's unique ID (from Azure) |

### ⚠️ Columns that DO NOT EXIST:
- `AllocationId` - Don't use this!

### Getting VM Unique ID:
```powershell
$vm = Get-AzVM -ResourceGroupName "<RG>" -Name "<VM_NAME>"
$vm.VmId  # This is the VirtualMachineUniqueId for Kusto
```
</step_2_kusto>

---

<step_3_azmove>
## Step 3: Generate AzMove Script

### Fixed Values (Always Use):
| Parameter | Value |
|-----------|-------|
| RegionalNetworkResourceChannelType | `ViaPubSub` |
| VipGoalStateChannelType | `ViaPubSub` |
| RollbackMode | `Optimized` |

### AzMove Script Template:
```powershell
# Run this on SAW machine with FcShell

$AzMove = Get-AzMove -Name <CLUSTER>
$crpSubscriptionId = "<SUBSCRIPTION_ID>"
$tenantName = "<TENANT_NAME_FROM_KUSTO>"
$fabricId = "<CLUSTER_NAME_FROM_KUSTO>"

# Create migration input object
$migrationInput = New-AzMoveObject AzMove.Controller.MigrateRunningTenantToMerlinInput
$migrationInput | Update-AzMoveObject -PropertyName FabricId -PropertyValue $fabricId
$migrationInput | Update-AzMoveObject -PropertyName NrpSubscriptionId -PropertyValue $crpSubscriptionId
$migrationInput | Update-AzMoveObject -PropertyName RegionalNetworkResourceChannelType -PropertyValue "ViaPubSub"
$migrationInput | Update-AzMoveObject -PropertyName VipGoalStateChannelType -PropertyValue "ViaPubSub"
$migrationInput | Update-AzMoveObject -PropertyName RollbackMode -PropertyValue "Optimized"

# Step 1: VALIDATE (always run this first!)
$validateResult = ($AzMove | Invoke-AzMoveApi `
    -MethodName AzMoveService_ValidateMigrateRunningTenantToMerlinAsyncByCrpsubscriptionidTenantnameMigrationinputAsync `
    -Parameters @($crpSubscriptionId, $tenantName, $migrationInput)).Result

# Check validation result before proceeding
if ($validateResult.IsSuccess) {
    Write-Host "✅ Validation passed, proceeding with migration..."
    
    # Step 2: MIGRATE
    $migrateResult = ($AzMove | Invoke-AzMoveApi `
        -MethodName AzMoveService_MigrateRunningTenantToMerlinAsyncByCrpsubscriptionidTenantnameMigrationinputAsync `
        -Parameters @($crpSubscriptionId, $tenantName, $migrationInput)).Result
} else {
    Write-Host "❌ Validation failed: $($validateResult.ErrorMessage)"
}
```
</step_3_azmove>

---

<step_4_verify>
## Step 4: Verify Migration Results

### Query AzMoveDiagnostics for detailed logs:

**Cluster:** `https://azurecm.kusto.windows.net`
**Database:** `AzureCM`
**Table:** `AzMoveDiagnostics`

```kql
AzMoveDiagnostics
| where PreciseTimeStamp > ago(10d)
| where ActorId != "<NULL>"
| where Message has "<TENANT_NAME_OR_VM_ID>"
| where not(
    Message startswith "<"
    or Message startswith "["
    or Message startswith "{"
    or Message startswith "Registering"
)
| where Message has_any ("NRP", "CRP", "AzSM", "NSM")
| project PreciseTimeStamp, Message
| order by PreciseTimeStamp asc
```

### Migration Phases (Expected Order for Success):

| # | Service | Operation | Phase |
|---|---------|-----------|-------|
| 1 | CRP | Discover | Validation |
| 2 | NRP | ValidateMigrateRunningTenantToMerlin | Validation |
| 3 | CRP | Validate | Validation |
| 4 | AzSM | ValidateTenantMerlinMigration | Validation |
| 5 | CRP | LockAvSet | Lock |
| 6 | AzSM | BlockTenantOperationsForMerlinMigration | Lock |
| 7 | NRP | BlockSubscriptionForMerlinMigration | Lock |
| 8 | NRP | MigrateRunningTenantToMerlin | **Migration** |
| 9 | AzSM | MigrateTenantFromNonMerlinToMerlinInNsm | Migration |
| 10 | AzSM | UpdateTenantMerlinStatus | Migration |
| 11 | CRP | MigrateAvSet | Migration |
| 12 | NRP | ServiceCleanupInRnm | Cleanup |
| 13 | NRP | UnblockSubscriptionForMerlinMigration | Cleanup |
| 14 | AzSM | UnblockTenantOperationsForMerlinMigration | Cleanup |
| 15 | CRP | UnlockAvSet | Cleanup |

### Log Analysis Patterns:

| Pattern | Status | Meaning |
|---------|--------|---------|
| All "succeeded" ending with UnlockAvSet | ✅ SUCCESS | Migration completed |
| "failed" then "Rollback...succeeded" | ⚠️ ROLLBACK OK | Migration failed, rollback worked |
| "failed" then "Rollback...failed" | ❌ CRITICAL | Both failed, escalate! |
| Validation "failed" | 🚫 BLOCKED | Migration never started |
</step_4_verify>

---

<step_5_analysis>
## Step 5: Generate Migration Analysis Report

After querying logs, generate a summary report:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              MIGRATION ANALYSIS REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Tenant: <TENANT_NAME>
  Status: ✅ MIGRATION SUCCESSFUL (or ⚠️/❌)

  PHASE BREAKDOWN:
  ├── Validation: ✅ All 4 checks passed
  ├── Lock: ✅ All 3 locks acquired
  ├── Migration: ✅ All 4 operations succeeded
  └── Cleanup: ✅ All 4 unlocks completed

  SUMMARY:
  ├── Total Operations: 15
  ├── Succeeded: 15
  ├── Failed: 0
  └── Result: Tenant migrated to Merlin
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
</step_5_analysis>

---

<troubleshooting>
## Troubleshooting

### Common Issues:

| Issue | Solution |
|-------|----------|
| VM not found in Kusto | Wait 5-15 min after VM creation |
| AllocationId column error | Use `ClusterName` instead (it's the FabricId) |
| Validation fails | Check tenant is on correct cluster |
| Migration stuck | Query AzMoveDiagnostics for status |
| Rollback failed | 🚨 Escalate to AzMove team immediately |

### Verify VM is registered:
```kql
MycroftContainerSnapshot_Latest
| where VirtualMachineUniqueId == "<VM_ID>"
| count
```
If count is 0, wait longer for VM to appear in Kusto.

### Common Failure Points:

| Failure At | Likely Cause | Action |
|------------|--------------|--------|
| NRP Validate | Network config issue | Check VNet/subnet config |
| CRP LockAvSet | AvSet already locked | Wait and retry |
| NRP MigrateRunning... | Timeout or conflict | Check detailed NRP logs |
| AzSM Rollback | Inconsistent state | Escalate to AzMove team |
</troubleshooting>
