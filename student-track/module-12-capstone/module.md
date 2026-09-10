# M12 - Capstone

## Objectif
Assemblage complet : Key Vault, stage, tags, monitors, network policy.

## DÃ©marrage rapide
1. Le starter de ce module a Ã©tÃ© copiÃ© dans votre workspace via New-StudentWorkspace.ps1.
2. Ouvrez module.md pour les consignes et consultez la solution de rÃ©fÃ©rence si nÃ©cessaire.
3. CrÃ©ez ou modifiez les fichiers .tf attendus.
4. Validez avec : powershell -ExecutionPolicy Bypass -File .\scripts\SelfPacedLab.ps1 -Module 12 -All

## Solution vÃ©rifiÃ©e
solutions/fil-rouge/05-capstone/environments/dev

## Astuce
Ne jamais commiter 	erraform.tfvars, .env, ackend.hcl, secrets/ ou les fichiers d'etat.