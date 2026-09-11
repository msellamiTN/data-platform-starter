# UAT — copie de DEV

Copiez ici depuis `envs/dev/` :

- `versions.tf`
- `provider.tf`
- `main.tf`
- `variables.tf`
- `outputs.tf`

Puis modifiez `backend.tf` et `terraform.tfvars` pour `UAT` (deja fournis).

Lancer :

```bash
cd terraform/envs/uat
terraform init -migrate-state
terraform plan -out=tfplan -input=false
```
