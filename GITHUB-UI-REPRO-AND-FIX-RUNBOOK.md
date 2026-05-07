# GitHub UI Runbook: Reproduce and Fix ALZ State Drift

1. **Open** your test repository in GitHub, go to **Actions**, open **02 Azure Landing Zones Continuous Delivery**, and **verify** one successful baseline run exists.

2. **Upload** the workaround file to the repo with wrong landing zone name:
   - **Code** -> target folder (for example `alz-mgmt/`) -> **Add file** -> **Upload files** -> drag file -> enter commit message.
   - Because `main` is protected, **select** `Create a new branch for this commit and start a pull request`.
  - **Click** `Propose changes` -> **Create pull request** -> **Merge pull request** -> **Confirm merge**.

3. **Run** the workflow from **Actions**: open **02 Azure Landing Zones Continuous Delivery** -> **Run workflow**.

4. When apply is actively creating resources, **click** `Cancel workflow`.

5. **Upload** the corrected workaround file (correct landing zone name) using the same protected-branch flow:
  - **Add file** -> **Upload files** -> **Propose changes** -> **Create pull request** -> **Merge pull request** -> **Confirm merge**.

6. **Run** the workflow again and **confirm** reproduction by checking apply logs for:
   - `Failed to persist state to backend` or `LeaseIdMissing` (412), and/or
   - `RoleAssignmentExists` (409).

7. **Cancel** all in-progress runs for this environment in GitHub Actions.

8. **Access** the ACI runner container and **break** the state lease:

```bash
az login
az account set --subscription "<subscription-id>"
az container exec \
  --resource-group "<aci-rg>" \
  --name "<aci-container-group>" \
  --container-name "<aci-container-name>" \
  --exec-command "/bin/sh"

az login --identity
az account set --subscription "<subscription-id>"
az storage blob lease break \
  --auth-mode login \
  --account-name "<storage-account>" \
  --container-name "<container>" \
  --blob-name "terraform.tfstate"
```

9. **Re-init** backend and **recover** state:

```bash
terraform init \
  -backend-config="resource_group_name=<backend-rg>" \
  -backend-config="storage_account_name=<storage-account>" \
  -backend-config="container_name=<container>" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="use_azuread_auth=true"

terraform state push errored.tfstate
```

10. **Run** validation and final apply:

```bash
terraform plan -input=false
terraform apply -input=false -auto-approve
```

If `errored.tfstate` is missing and you get `RoleAssignmentExists`, **import** the existing role assignments from error IDs, then rerun step 10.
