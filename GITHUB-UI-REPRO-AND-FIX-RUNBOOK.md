# GitHub UI Runbook: Reproduce and Fix ALZ State Drift Incident

Purpose:
- Reproduce the same failure pattern as the customer.
- Confirm the reproduction is valid.
- Apply the correct recovery flow.

Scope:
- GitHub Actions
- Self-hosted runner in Azure Container Instance (ACI)
- Terraform remote state in Blob Storage with private endpoint

## A. Before you start

1. Use a test repo and test subscription only.
2. Confirm bootstrap is already successful.
3. Confirm one successful run of 02 Azure Landing Zones Continuous Delivery exists.
4. Make sure your runner and backend match customer topology.

Expected behavior to reproduce:
- First run is canceled during apply.
- Second run starts after config correction.
- Second run fails with state inconsistency symptoms such as:
  - 412 lease/state persistence issues, or
  - 409 RoleAssignmentExists errors.

## B. Reproduce in GitHub UI (button-by-button)

### Step 1: Open the repository

1. Go to your org: https://github.com/MyOrg-abengtss/
2. Click the test repository you are using for reproduction.

### Step 2: Verify baseline success

1. Click Actions.
2. In the left workflow list, click 02 Azure Landing Zones Continuous Delivery.
3. In the run history, verify at least one recent run has green check status.

If no green baseline run exists, do not continue. First get one successful run.

### Step 3: Add intentionally wrong management group name

1. Click Code.
2. Navigate to the file changed by the workaround from the issue-287 fix process.
3. Click the pencil icon (Edit this file).
4. Set the management group name to a wrong value (intentional mismatch).
5. Scroll down to Commit changes.
6. Select Commit directly to main (or your normal path if you use PR).
7. Click Commit changes.

### Step 4: Start workflow run with wrong value

1. Click Actions.
2. Click 02 Azure Landing Zones Continuous Delivery.
3. Click Run workflow.
4. Select branch main.
5. Click Run workflow.

### Step 5: Cancel during active apply

1. Open the running workflow.
2. Click the apply job.
3. Wait until Terraform shows active create/destroy operations (not just init/plan).
4. Top-right, click Cancel workflow.
5. Confirm cancellation when prompted.

Important: cancel while resources are actively changing. This is required to reproduce.

### Step 6: Correct management group name

1. Go back to Code.
2. Open the same file.
3. Click Edit (pencil).
4. Replace wrong management group value with the correct value from documentation.
5. Click Commit changes.

### Step 7: Start second run

1. Click Actions.
2. Click 02 Azure Landing Zones Continuous Delivery.
3. Click Run workflow.
4. Choose main.
5. Click Run workflow.

### Step 8: Observe failure signals

Open the failed run and check logs in apply step.

Reproduction is confirmed if one or more appear:
1. Failed to persist state to backend
2. Error saving state
3. 412 LeaseIdMissing on blob
4. RoleAssignmentExists 409 conflicts

## C. Validate this is the same issue

You have a valid match when all are true:
1. First run was canceled during apply.
2. Second run attempted to create resources that already exist.
3. State/backend write or lock symptoms are present, or existing-role-assignment conflicts are present.

If these are true, this reproduces the customer incident pattern.

## D. Recovery procedure after reproduction

1. In GitHub Actions, cancel all in-progress runs for this environment.
2. From ACI runner network path, break lease on state blob.
3. Re-run terraform init with same backend config.
4. If errored.tfstate exists from first failed run, run terraform state push errored.tfstate.
5. Run terraform plan.
6. If plan looks correct, run terraform apply once.

If errored.tfstate is missing:
1. Import already-created resources (especially RoleAssignmentExists objects).
2. Run plan, then apply.

## D1. Command pack for complete recovery (run from ACI network path)

Set variables:

```bash
export SUBSCRIPTION_ID="<subscription-id>"
export TFSTATE_RG="<backend-resource-group>"
export TFSTATE_SA="<backend-storage-account>"
export TFSTATE_CONTAINER="<backend-container>"
export TFSTATE_KEY="terraform.tfstate"
```

Login and verify subscription:

```bash
az login --identity
az account set --subscription "$SUBSCRIPTION_ID"
```

Check DNS resolves storage endpoint to private IP:

```bash
nslookup ${TFSTATE_SA}.blob.core.windows.net
```

Check current lease state:

```bash
az storage blob show \
  --auth-mode login \
  --account-name "$TFSTATE_SA" \
  --container-name "$TFSTATE_CONTAINER" \
  --name "$TFSTATE_KEY" \
  --query properties.lease
```

Break lease:

```bash
az storage blob lease break \
  --auth-mode login \
  --account-name "$TFSTATE_SA" \
  --container-name "$TFSTATE_CONTAINER" \
  --blob-name "$TFSTATE_KEY"
```

Re-init backend:

```bash
terraform init \
  -backend-config="resource_group_name=${TFSTATE_RG}" \
  -backend-config="storage_account_name=${TFSTATE_SA}" \
  -backend-config="container_name=${TFSTATE_CONTAINER}" \
  -backend-config="key=${TFSTATE_KEY}" \
  -backend-config="use_azuread_auth=true"
```

If available, push recovered state from first failed apply:

```bash
ls -l errored.tfstate
terraform state push errored.tfstate
```

Plan and apply:

```bash
terraform plan -input=false
terraform apply -input=false -auto-approve
```

If you get RoleAssignmentExists and errored.tfstate is missing, import each object from the error list:

```bash
terraform import 'azurerm_role_assignment.landing_zones_policy_mi["<key>"]' '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Authorization/roleAssignments/<guid>'
```

Then run plan/apply again.

## E. Prevent recurrence

1. Ensure apply does not use lock=false.
2. Enforce one concurrency group per state key.
3. Do not rerun apply after failed state persistence until state recovery is complete.
4. Keep one unique backend key per environment.

## F. What to capture for support and RCA

1. URL to canceled run.
2. URL to failed second run.
3. Screenshot or copied log lines showing 412/409 messages.
4. Backend identifiers used by the run:
   - backend resource group
   - storage account
   - container
   - key
5. Confirmation of runner type (ACI) and that backend is private endpoint.
