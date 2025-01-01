# Kusto Debugging

When getting failures in dev from Kusto it can be helpful to view your executed queries with:

```
.show queries 
| order by StartedOn desc
```