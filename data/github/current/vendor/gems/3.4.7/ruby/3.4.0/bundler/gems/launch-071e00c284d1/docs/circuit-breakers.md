# Circuit Breakers

## Generating a tuning dashboard

If new breaker configurations are added to `utils/abreaker/config.go` you'll need to update the circuit breaker tuning dashboard to include that new configuration. This is something that could be automated if you're feeling bored. 😉 Here's how to do it manually:
1. Make your change.
1. Add config reference to `cmd/grapher/dashboard.go`
1. Open a Terminal Window in a Codespace that includes the `launch` repo (e.g. a [new github/github Codespace](https://github.com/codespaces/new?hide_repo_select=true&ref=master&repo=3&skip_quickstart=true&devcontainer_path=.devcontainer%2Factions%2Fdevcontainer.json)).
1. `cd /workspaces/actions/launch` (or equivalent for your Codespace or filesystem layout)
1. Run the following commands from the Codespace Terminal Window:
```
cd cmd/grapher
go run ./... > /tmp/circuit-breaker-tuning-dashboard.json
code /tmp/circuit-breaker-tuning-dashboard.json
```
1. Copy the content of `/tmp/circuit-breaker-tuning-dashboard.json` (should already be visible in your VSCode window) to your clipboard.
1. Open the [Circuit Breaker Tuning Dashboard](https://app.datadoghq.com/dashboard/ui7-cs4-2cm), and locate the settings icon (:gear:) near the top-right of the page.
1. Click `Import dashboard JSON...` and paste the JSON you copied to your clipboard earlier.
1. Check that any new configs successfully populate on the updated datadog dashboard.
1. That's it.  You're done!

### What if the script does not run?
If you're seeing `bin/grapher: No such file or directory`, try running the script in a codespace instead.

### What if the new dashboard has empty/blank graphs?

It is possible that there's no data to graph out yet.
If you see that there is also no Y-Axis, you will need to enable `SUM` aggregations.
    1. Click pencil icon to start editing graph
    2. Click `sum by`
    3. There will be a dropdown list where `sum by ` is greyed out along with a link to `Metric Summary`
    4. Add a `Group by SUM & Rollup by AVG` aggregation and save
    5. Refresh the dashboards

### What if there's an error?

I found that if there is an error in updating the dashboard configuration, that there will be a failed XHR request (400 status code) in the network tab of the developer tools. If you read the response in that request, it should be enough to start troubleshooting what went wrong.

## Automating Generation Further

- I'm not sure how often we'll do this, so I'm not automating it end to end right now. Though it should be fairly easy.
- Since the dashboard is managed, we could make a workflow that detects if a diff is produced when running the dashboard generation command. If yes, it could be configured to open a PR on `github/datadog-monitoring`.
- We would need to convert the JSON to YAML and make sure it matches the format over on `github/datadog-monitoring`. But that's trivial, since we're using structs to describe the widgets, and YAML is just another serialization format in this case. It's worth noting that we may be sending more keys that expected for `github/datadog-monitoring`'s format or even less if they have some special fields.