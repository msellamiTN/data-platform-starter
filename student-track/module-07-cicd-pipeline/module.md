# M07 - CI/CD Pipeline

## Objectif
Pipeline Azure DevOps : validate, plan, approval, apply, audit.

## DÃ©marrage rapide
1. Le starter de ce module a Ã©tÃ© copiÃ© dans votre workspace via New-StudentWorkspace.ps1.
2. Ouvrez module.md pour les consignes et consultez la solution de rÃ©fÃ©rence si nÃ©cessaire.
3. CrÃ©ez ou modifiez les fichiers .tf attendus.
4. Validez avec : powershell -ExecutionPolicy Bypass -File .\scripts\SelfPacedLab.ps1 -Module 7 -All

## Solution vÃ©rifiÃ©e
solutions/fil-rouge/03-devops-setup

## Astuce
Ne jamais commiter 	erraform.tfvars, .env, ackend.hcl, secrets/ ou les fichiers d'etat.