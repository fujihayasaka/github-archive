# Understanding Audit Log in Actions

Most of the audit log events are generated inside GitHub and consumed there. However, there are a few audit log events that are generated from Actions side.
For example:
- `workflows.prepared_workflow_job` (api only)
- `enterprise.self_hosted_runner_updated`
- `org.self_hosted_runner_updated`

These audit logs are generated from Actions Service and then launch passes this to GitHub, via hydro.

## Further reading
For detailed audit log architecture, visit: 
- [Driftwood (hydro stream processor)](https://github.com/github/driftwood#architecture)
- [Elastic search (index templating)](https://github.com/github/audit-log/blob/master/docs/architecture.md#elasticsearch)

## Developing in Codespace
In the development environment, enable audit logs using the following script in github root directory:
- `bin/safe-ruby script/setup-development-audit-log`
- note: if you are rerunning this script, or you are aware of that audit log is bootstrapped, run with flag `--no-bootstrap`

Instead of hydro, in the development environment kafka-lite is running and launch is sending audit logs to kafka-lite. The script above will bootstrap audit log and start the stream processor that will consume audit log entries from kafka-lite and stream them to the github audit log system (driftwood). Note that using this processor is not really how the data flow works for dotcom audit-logs. Check out the links in [this section](#further-reading) for more info.

## GHES
In GHES, hydro is not running but instead kafka-lite is running. Therefore the architecture is similar to the development environment.

### Developing in GHES
If you are running GHES bp-dev, the audit log is already configured and should be working without any manual steps.
