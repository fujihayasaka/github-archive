# Monitoring

## Splunk

### Licensify logs

[`index=licensify`](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dlicensify&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-15m%40m&latest=now&sid=1711561111.12185_BBFEADC1-13E7-469C-AD3C-290EFFB13C63)

### Licensify error logs

[`index=licensify SeverityText=ERROR`](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dlicensify%20SeverityText%3DERROR&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-15m%40m&latest=now&sid=1711561173.12194_BBFEADC1-13E7-469C-AD3C-290EFFB13C63)

### Useful fields

- `gh.aqueduct.job.name` - Name of the Aqueduct job executing the process
- `gh.aqueduct.queue.name` - Name of the Aqueduct queue used to enqueue the message
- `gh.hydro.msg.topic` - Name of the Hydro topic being processed

## Sentry

- [Licensify errors](https://github.sentry.io/issues/?project=4506701748568064&statsPeriod=7d)
- [Licensify errors dashboard](https://github.sentry.io/projects/licensify/?project=4506701748568064)
