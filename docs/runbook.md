# Runbook

## Opérations courantes

### Initialiser un environnement

```bash
cd environments/dev
terraform init -backend-config=backend.hcl
```

### Valider la configuration

```bash
terraform fmt -recursive -check
terraform validate
tflint
```

### Planifier un déploiement

```bash
terraform plan -out=tfplan
```

### Appliquer un déploiement

```bash
terraform apply tfplan
```

### Vérifier la dérive

```bash
terraform plan -detailed-exitcode
# Exit code 0: pas de dérive
# Exit code 2: dérive détectée
```

### Détruire un environnement

```bash
terraform destroy
```

> Ne jamais exécuter `terraform destroy` sans plan préalable ni confirmation humaine.

## Procédures d'incident

### State verrouillé

Si le state est verrouillé par une session interrompue :

1. Confirmer qu'aucun autre utilisateur n'utilise le state.
2. Identifier le verrou avec `terraform force-unlock -list`.
3. Forcer le déverrouillage avec l'identifiant du verrou.

> Cette opération est dangereuse. Ne l'exécuter qu'après confirmation.

### Détection de dérive inattendue

1. Exécuter `terraform plan -detailed-exitcode`.
2. Si la sortie indique une dérive, analyser le plan.
3. Si la dérive est due à une modification manuelle, importer ou corriger.
4. Si la dérive est due à un bug Terraform, ouvrir une branche de correction.
5. Ne jamais appliquer un plan de destruction sans revue.

### Secret exposé

1. Ne pas afficher la valeur.
2. Rotationner le secret immédiatement.
3. Retirer le secret du fichier concerné.
4. Vérifier l'historique Git.
5. Si le secret a été publié, purger l'historique et notifier les collaborateurs.

## Nettoyage de fin de session

1. Détruire les ressources Terraform de chaque environnement.
2. Vérifier qu'aucun warehouse n'est actif.
3. Vérifier qu'aucun resource monitor n'est déclenché.
4. Supprimer les branches temporaires.
5. Archiver ou supprimer le projet apprenant.
