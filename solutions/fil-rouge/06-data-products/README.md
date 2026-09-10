# Data Products as Code

This root extends the capstone platform with domain-owned SALES and FINANCE products.

Terraform owns databases, Medallion schemas, stages, roles and grants. Snow CLI deploys versioned SQL content under `sql/` after Terraform has published the structural contract.

## Validate

```powershell
terraform -chdir=environments/dev init -backend=false
terraform -chdir=environments/dev validate
```

## Deploy SQL

```powershell
snow sql -f sql/sales/orders.sql --database DB_SALES_DEV --warehouse WH_ETL_DEV
snow sql -f sql/finance/ledger.sql --database DB_FINANCE_DEV --warehouse WH_ETL_DEV
```
