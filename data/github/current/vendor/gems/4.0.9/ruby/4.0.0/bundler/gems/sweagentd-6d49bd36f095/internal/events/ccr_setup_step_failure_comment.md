One or more custom steps from this repository's [`copilot-setup-steps.yml`](https://gh.io/copilot/actions-setup-steps) failed for this Copilot Code Review run:

```text
{{ range .FailedSteps }}{{ . }}
{{ end }}```

Setup steps run before each review. If the review above is missing context, or no review was posted at all, the failing step{{ if .Plural }}s{{ end }} above may be the cause. Update your `copilot-setup-steps.yml` and re-request a review. See the [workflow run]({{ .RunURL }}) for details.

{{ .Telemetry }}
