# secrets/

This directory holds local secret files that are **never committed to Git**.

The `.gitignore` excludes all files in `secrets/` except this README, so the directory exists in the clone without exposing any secret.

## Secret distribution architecture

```
┌─────────────────────────────────────────────────────────┐
│  Azure Key Vault (kvdata2aitfsecrets)                   │
│                                                         │
│  Secrets:                                               │
│  • SnowflakePAT-APP01  ← per-learner PAT               │
│  • SnowflakePAT-APP02  ← per-learner PAT               │
│  • SnowflakeOrganization, SnowflakeAccount, ...         │
│  • ArmClientId, ArmClientSecret, ArmTenantId, ...       │
│                                                         │
│  Access:                                                │
│  • Shared SP → Key Vault Secrets User                   │
│  • WIF CI SP → Key Vault Secrets User                   │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Learner-Login.ps1                                      │
│                                                         │
│  1. Load config/shared.env (committed, no secrets)      │
│  2. Load .env (gitignored, LEARNER_PREFIX only)         │
│  3. Login Azure with secrets/shared-sp.txt (bootstrap)  │
│  4. Retrieve PAT from Key Vault:                        │
│     az keyvault secret show \                           │
│       --vault-name $KEY_VAULT_NAME \                    │
│       --name SnowflakePAT-$LEARNER_PREFIX               │
│  5. Set TF_VAR_snowflake_token = <PAT>                  │
│  6. Fallback: secrets/snowflake_pat.txt if KV fails     │
└─────────────────────────────────────────────────────────┘
```

## Relationship with .env and config/shared.env

| File | Committed | Contains | Purpose |
|---|---|---|---|
| `config/shared.env` | Yes | Account IDs, Azure config, Key Vault name | Shared config (no secrets) |
| `.env` | No | `LEARNER_PREFIX`, `ENVIRONMENT` | Per-learner personal values |
| `secrets/shared-sp.txt` | No | `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, ... | Azure SP credentials (bootstrap) |
| `secrets/snowflake_pat.txt` | No | PAT token | Fallback if Key Vault is unavailable |
| `secrets/snowflake_key.p8` | No | RSA private key | JWT key-pair auth (M10) |
| `secrets/snowflake_key.pub` | No | RSA public key | JWT key-pair auth (M10) |

## Expected files

| File | Created when | Purpose | Source |
|---|---|---|---|
| `shared-sp.txt` | Day 0 (instructor distributes) | Azure SP credentials for `az login` | Instructor |
| `snowflake_pat.txt` | Day 0 (optional fallback) | Snowflake PAT | Key Vault (preferred) or `New-SnowflakeConnection.ps1` |
| `snowflake_key.p8` | Day 4 (M10) | RSA private key for JWT auth | `openssl genrsa` |
| `snowflake_key.pub` | Day 4 (M10) | RSA public key | `openssl rsa -pubout` |
| `backend.hcl` | Day 2 (M2) | Azure Blob backend config | Learner creates |

## Rules

1. **Never** commit a file in this directory other than `README.md`.
2. **Never** display the content of a secret file in a screenshot, log or report.
3. **Never** pass a secret as a command-line argument — use environment variables or masked prompts.
4. **Rotate** the PAT when the training module is complete.
5. **Delete** the contents of this directory at the end of the training.

## Verify Git ignores secrets

```bash
git check-ignore secrets/snowflake_pat.txt
git check-ignore secrets/shared-sp.txt
```

**Expected:** the command returns the path, confirming Git ignores it.

If the command returns nothing, stop and fix your `.gitignore` before proceeding.

## Instructor: set per-learner PATs in Key Vault

```powershell
# After running 00-bootstrap, set a PAT for each learner:
foreach ($prefix in @("APP01","APP02","APP03")) {
    $pat = Read-Host "Enter PAT for $prefix" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pat))
    az keyvault secret set `
        --vault-name kvdata2aitfsecrets `
        --name "SnowflakePAT-$prefix" `
        --value $plain
    $plain = $null
}
```
