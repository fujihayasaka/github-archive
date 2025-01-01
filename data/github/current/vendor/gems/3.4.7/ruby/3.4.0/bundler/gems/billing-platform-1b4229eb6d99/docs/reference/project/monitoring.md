# Monitoring

This document provides an overview of the different monitoring and observability setups for billing platform.

## Table of Contents

- [Details](#details)
  - [DataDog](#datadog)
  - [Splunk](#splunk)
  - [Sentry](#sentry)
- [References](#references)

## Details

### DataDog

- [General billing platform dashboard](https://app.datadoghq.com/dashboard/646-msn-qic?refresh_mode=sliding&from_ts=1694092611279&to_ts=1694697411279&live=true)
- [Azure emission dashboard](https://app.datadoghq.com/dashboard/aa7-aid-znj?refresh_mode=sliding&from_ts=1694683019958&to_ts=1694697419958&live=true)
- [React dashboard](https://app.datadoghq.com/dashboard/2rj-39u-76u/billing-react?refresh_mode=sliding&from_ts=1694093088427&to_ts=1694697888427&live=true)

#### Usage Report

- [Usage Report dashboard](https://app.datadoghq.com/dashboard/htb-kx2-zb7/billing-platform-usage-report-api?refresh_mode=sliding&from_ts=1695746074922&to_ts=1698338074922&live=true)
- [Usage Report API timeout monitor](https://app.datadoghq.com/monitors/133654562)
- [Usage Report API 5x error monitor](https://app.datadoghq.com/monitors/133352355)
- [Usage Report Export Job Error Monitor](https://app.datadoghq.com/monitors/138634955)

### Splunk

All log messages produced by one API/job/event handler run will have the same `TraceId` field. You can use this to filter for all logs related to a single run.

#### All Billing platform logs

[`index=billing kube_namespace=billing-platform*`](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dbilling%20kube_namespace%3Dbilling-platform*&earliest=-15m&latest=now&sid=1694697331.78487_6F675BFE-E002-4BA9-BC57-B70B5EBC6803&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard)

#### Billing platform error logs

[`index=billing kube_namespace=billing-platform* | spath SeverityText | search SeverityText=ERROR`](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dbilling%20kube_namespace%3Dbilling-platform*%20%7C%20spath%20SeverityText%20%7C%20search%20SeverityText%3DERROR&earliest=-15m&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&display.events.fields=%5B%22host%22%2C%22source%22%2C%22sourcetype%22%2C%22Body%22%5D&display.events.type=list&sid=1694697380.78505_6F675BFE-E002-4BA9-BC57-B70B5EBC6803)

#### Billing platform logs for Actions check run

To find logs related to given Actions run:

1. Capture the check run ID from the URL. Example: https://github.com/org-a-xxx/private-repo/actions/runs/5714679620/job/15482479703, the check run ID is `15482479703`.
2. Find the releated logs with a Splunk query [`index=billing kube_namespace=billing-platform-* source_uri="gid://git-hub/CheckRun/<check-run-id>"`](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dbilling%20kube_namespace%3Dbilling-platform-*%20source_uri%3D%22gid%3A%2F%2Fgit-hub%2FCheckRun%2F%3Ccheck-run-id%3E%22&earliest=-15m&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&sid=1694698032.78939_6F675BFE-E002-4BA9-BC57-B70B5EBC6803)
3. Use `TraceId` to find all logs captured during the usage ingestion.

### Sentry

- [Billing platform errors](https://github.sentry.io/issues/?project=4504834072117248&statsPeriod=7d)
- [Billing platform errors dashboard](https://github.sentry.io/projects/billing-platform/?issuesType=new&project=4504834072117248)

## References

- [The Hub: DataDog Monitor Alerting](https://thehub.github.com/epd/engineering/dev-practicals/observability/alerting/datadog-monitor-alerting/)
- [The Hub: Splunk](https://thehub.github.com/epd/engineering/products-and-services/internal/splunk/)
- [The Hub: Exception Reporting to Sentry](https://thehub.github.com/epd/engineering/dev-practicals/observability/exception-tracking/)
