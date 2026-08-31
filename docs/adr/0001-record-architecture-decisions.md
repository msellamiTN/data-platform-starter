# ADR-0001 — Enregistrer les décisions d'architecture

## Statut

Accepté

## Contexte

Le projet construit une plateforme Snowflake avec Terraform sur Azure. Les décisions d'architecture affectent la sécurité, les coûts, la reproductibilité et la maintenance. Sans trace écrite, ces décisions se perdent ou se contredisent.

## Décision

Chaque décision d'architecture significative est enregistrée dans ce dossier `docs/adr/` sous la forme d'un ADR (Architecture Decision Record).

Un ADR contient :

- **Statut** : proposé, accepté, déprécié ou remplacé;
- **Contexte** : la situation qui motive la décision;
- **Décision** : la décision prise;
- **Conséquences** : les impacts positifs et négatifs.

## Conséquences

- Les décisions sont traçables et datées.
- Un nouveau contributeur peut comprendre pourquoi un choix a été fait.
- Une décision peut être remise en question en créant un nouvel ADR qui remplace le précédent.
- Le dossier `docs/adr/` est versionné avec le code.
