# Module RBAC — GlobalBank

Ce module gère la création des rôles Snowflake (`snowflake_account_role`) utilisés par la plateforme.

## Ressources principales

- `snowflake_account_role.access_roles` : rôles métier créés à partir de la map `var.roles`.

## Gestion des dépendances et du cycle de vie

```hcl
resource "snowflake_account_role" "access_roles" {
  for_each = var.roles

  name    = "${var.prefix}_${each.value.suffix}${local.suffix}"
  comment = "${each.value.comment} | ${local.owner_tag}"

  depends_on = []

  lifecycle {
    ignore_changes = all
  }
}
```

- `depends_on` : méta-argument laissé vide car la ressource ne dépend d'aucune autre ressource dans ce module. Il peut être complété si des dépendances explicites apparaissent.
- `lifecycle { ignore_changes = all }` : les rôles peuvent recevoir des privilèges ou évoluer en dehors de Terraform. Ce lifecycle empêche Terraform de reprovisionner le rôle lors de ces évolutions.
