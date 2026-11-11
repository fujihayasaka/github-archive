# Environments

| Environment | URL |
| ------------| --- |
| Lab | `dependency-graph-api-lab.service.ash1-iad.github.net` |
| Production API | `dependency-graph-api.service.ash1-iad.github.net` |
| Slow Queries API | `dependency-graph-api-slow-queries.service.ash1-iad.github.net` |

## `kubectl` cheat sheet

These require you to log in to a production bastion host, as well as load your vault credentials with `. vault-login`.

### List namespaces

```bash
mrysav@ops-shell-4189a64.ac4-iad(prd) ~ $ kubens | grep dependency-graph-api
dependency-graph-api-lab
dependency-graph-api-production
dependency-graph-api-scripts
```

### List services for a namespace

```bash
mrysav@ops-shell-4189a64.ac4-iad(prd) ~ $ kubectl --namespace dependency-graph-api-production get services
NAME             TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
api              LoadBalancer   10.125.172.54    <pending>     80:30383/TCP   216d
slow-query-api   LoadBalancer   10.125.186.102   <pending>     80:32520/TCP   216d
```

### Get URL for service in a namespace

Note the `-A1` on the `grep` - the URL for the service might be on the next line after the `load-balancer-dns-name` tag.

```bash
mrysav@ops-shell-4189a64.ac4-iad(prd) ~ $ kubectl --namespace dependency-graph-api-production describe service api | grep -A1 dns-name
                          kube-service-exporter.github.com/load-balancer-dns-name:
                            dependency-graph-api.service.ash1-iad.github.net,dependency-graph-api.service.iad.github.net
```
