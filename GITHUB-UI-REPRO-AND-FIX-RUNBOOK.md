# GitHub UI Runbook: Reproduce and Fix ALZ State Drift

This guide is short and action-focused for this setup:
- GitHub Actions
- Self-hosted runner in Azure Container Instance (ACI)
- Terraform state in Blob Storage with private endpoint

## 1. Reproduce the customer issue

1. **Open** your test repository in GitHub.
2. **Go to** Actions and **verify** one successful run of 02 Azure Landing Zones Continuous Delivery.
3. **Go to** Code and **open** the workaround file used for issue 287.
4. **Edit** the file and **set a wrong management group name**.
5. **Commit** the change to main (or merge PR to main).
6. **Go to** Actions, **open** 02 Azure Landing Zones Continuous Delivery, then **click** Run workflow.
7. When apply is actively creating resources, **click** Cancel workflow.
8. **Go back** to Code, **edit** the same file, and **set the correct management group name**.
9. **Commit** to main (or merge PR).
10. **Run** 02 Azure Landing Zones Continuous Delivery again.

Expected reproduction result:
- Second run fails with one or both:
  - 412 LeaseIdMissing / failed to persist state
  - 409 RoleAssignmentExists

## 2. Important clarification about files

You must include the workaround in the repository itself.

1. **Add** the workaround Terraform file to the repo (if it is not already there).
2. **Commit** and **push** the file.
3. **Then run** the pipeline.

If the file exists only locally and is not committed, the pipeline cannot use it.

### 2A. Exact GitHub Web UI upload steps (your screenshot)

Use this when you downloaded the fix file locally and changed the landing zone name.

1. **Open** the target folder in GitHub repo (example: `alz-mgmt/`).
2. **Click** `Add file` -> `Upload files`.
3. **Drag** your edited file into the upload area.
4. In `Propose changes` message, **enter** a short commit message, for example:
  - `Add fix.landing-zones-policy-mi-rbac.tf with wrong landing zone name for repro`
5. In the branch options (because main is protected):
  - **Select** `Create a new branch for this commit and start a pull request`.
  - **Keep** generated branch name or **rename** it (example: `repro/wrong-lz-name`).
6. **Click** `Propose changes`.
7. On the next PR page, **click** `Create pull request`.
8. After checks/policies pass, **click** `Merge pull request`.
9. **Click** `Confirm merge`.

Now the file is in the repo and can be used by the pipeline.

Repeat the same flow when you upload the corrected file later (new branch + new PR + merge).

## 3. Recover after reproduction (end-to-end fix)

1. **Cancel** all in-progress runs for this environment in GitHub Actions.
2. **Run recovery from ACI network path** (not from local machine).
3. **Access** the ACI container and **execute** commands there.

## 3A. Container Instance operations (exact steps)

Run these from your own terminal first (outside container):

1. **Login** and **set subscription**:

```bash
az login
az account set --subscription "<subscription-id>"
```

2. **Find** your container groups (if needed):

```bash
az container list --resource-group "<aci-rg>" --query "[].name" -o table
```

3. **List** containers in the selected group (get exact container name):

```bash
az container show \
  --resource-group "<aci-rg>" \
  --name "<aci-container-group>" \
  --query "containers[].name" -o table
```

4. **Open shell** in the runner container:

```bash
az container exec \
  --resource-group "<aci-rg>" \
  --name "<aci-container-group>" \
  --container-name "<aci-container-name>" \
  --exec-command "/bin/sh"
```

If `/bin/sh` fails, try:

```bash
az container exec \
  --resource-group "<aci-rg>" \
  --name "<aci-container-group>" \
  --container-name "<aci-container-name>" \
  --exec-command "bash"
```

Now run the recovery commands from inside this shell.

5. **Login** inside container (prefer managed identity):

```bash
az login --identity
az account set --subscription "<subscription-id>"
```

6. **Verify** private endpoint DNS resolution from inside container:

```bash
nslookup <storage-account>.blob.core.windows.net
```

Expected: private IP range (10.x/172.16-31.x/192.168.x).

7. **Break state lease**:

```bash
az storage blob lease break \
  --auth-mode login \
  --account-name "<storage-account>" \
  --container-name "<container>" \
  --blob-name "terraform.tfstate"
```

8. **Re-init backend** with same values as workflow:

```bash
terraform init \
  -backend-config="resource_group_name=<backend-rg>" \
  -backend-config="storage_account_name=<storage-account>" \
  -backend-config="container_name=<container>" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="use_azuread_auth=true"
```

9. If first failed run produced file, **push recovered state**:

```bash
terraform state push errored.tfstate
```

10. **Run** plan, then apply once:

```bash
terraform plan -input=false
terraform apply -input=false -auto-approve
```

11. If errored.tfstate is missing and you get RoleAssignmentExists, **import** existing resources from error IDs, then run plan/apply again:

```bash
terraform import 'azurerm_role_assignment.landing_zones_policy_mi["<key>"]' '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Authorization/roleAssignments/<guid>'
```

## 4. Prevent this from happening again

1. **Remove** lock=false from apply.
2. **Enforce** one concurrency group per state key.
3. **Do not rerun** apply after failed state persistence until recovery is done.
4. **Keep** unique state key per environment.
