# admin-fix

**Utilisation :** formateur uniquement.  
**Objectif :** Créer ou réparer l'utilisateur service `TERRAFORM_SVC` et charger sa clé publique RSA.

Ce dossier est un *root module* Terraform autonome qui :
- se connecte à Snowflake avec l'utilisateur admin `DATA2AI` (authentification password) ;
- gère la ressource `snowflake_user.terraform_svc` ;
- lit la clé publique dans `../../secrets/snowflake_key.oneline`.

Il n'est pas destiné aux participants. Le [Jour 0 apprenant](../../courses/day-00/README.md) n’exécute aucune opération administrative; les réparations `CREATE USER` et `GRANT ROLE` restent sous la responsabilité du formateur ou de l’administrateur.

---

## Prérequis

1. Avoir généré `secrets/snowflake_key.p8` et `secrets/snowflake_key.pub`.
2. Construire `secrets/snowflake_key.oneline` (clé publique sans en-têtes ni retour chariot).
3. Avoir les identifiants `DATA2AI` depuis `access.txt`.
4. Créer `terraform.tfvars` depuis l'exemple :

```powershell
copy terraform.tfvars.example terraform.tfvars
```

---

## Workflow

```powershell
terraform init
terraform plan
terraform apply
```

Après exécution, `TERRAFORM_SVC` est créé/mis à jour avec la clé publique du fichier `snowflake_key.oneline`.

> N'oubliez pas d'accorder explicitement le rôle `ACCOUNTADMIN` à `TERRAFORM_SVC` si nécessaire :
> ```sql
> GRANT ROLE ACCOUNTADMIN TO USER TERRAFORM_SVC;
> ```

---

## Nettoyage

Le state reste local (`terraform.tfstate`). Pour le supprimer sans toucher à l'utilisateur Snowflake :

```powershell
Remove-Item terraform.tfstate, terraform.tfstate.backup, .terraform.lock.hcl
Remove-Item -Recurse -Force .terraform
```

---

## Structure

| Fichier | Rôle |
|---|---|
| `provider.tf` | Provider Snowflake, auth password DATA2AI |
| `variables.tf` | Variables d'entrée (organisations, account, user, role, password) |
| `main.tf` | Gestion de l'utilisateur `TERRAFORM_SVC` et sa clé publique |
| `terraform.tfvars.example` | Template des variables sensibles |
| `terraform.tfvars` | Fichier local gitignoré contenant le vrai mot de passe |
