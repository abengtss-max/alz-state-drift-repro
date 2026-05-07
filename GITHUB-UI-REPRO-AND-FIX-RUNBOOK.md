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

## 3. Recover after reproduction (end-to-end fix)

1. **Cancel** all in-progress runs for this environment in GitHub Actions.
2. **Run recovery from ACI network path** (not from local machine).
3. **Login** in container with identity:

```bash
az login --identity
az account set --subscription "<subscription-id>"
```

4. **Break state lease**:

```bash
az storage blob lease break \
  --auth-mode login \
  --account-name "<storage-account>" \
  --container-name "<container>" \
  --blob-name "terraform.tfstate"
```

5. **Re-init backend** with same values as workflow:

```bash
terraform init \
  -backend-config="resource_group_name=<backend-rg>" \
  -backend-config="storage_account_name=<storage-account>" \
  -backend-config="container_name=<container>" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="use_azuread_auth=true"
```

6. If first failed run produced file, **push recovered state**:

```bash
terraform state push errored.tfstate
```

7. **Run** plan, then apply once:

```bash
terraform plan -input=false
terraform apply -input=false -auto-approve
```

8. If errored.tfstate is missing and you get RoleAssignmentExists, **import** existing resources from error IDs, then run plan/apply again:

```bash
terraform import 'azurerm_role_assignment.landing_zones_policy_mi["<key>"]' '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Authorization/roleAssignments/<guid>'
```

## 4. Prevent this from happening again

1. **Remove** lock=false from apply.
2. **Enforce** one concurrency group per state key.
3. **Do not rerun** apply after failed state persistence until recovery is done.
4. **Keep** unique state key per environment.
