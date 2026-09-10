# Day 1 — State Management Lab

Copie de `01-day1-basics` avec backend S3 activé.

## Migration

1. Déployer `00-bootstrap` pour créer bucket + DynamoDB
2. Copier `backend.tf.example` ? `backend.tf` et renseigner les valeurs
3. Exécuter :

```powershell
terraform init -migrate-state
terraform plan
```

## Backend example

Voir `backend.tf.example` — ne pas committer `backend.tf` avec noms réels si politique stricte (utiliser tfvars ou CI vars).
