@{{ .Login }} The model{{ if .RequestedModel }} `{{ .RequestedModel }}`{{ end }} is not available for your account. This can happen if the model was disabled by your organization's policy or if your Copilot plan doesn't include access to it.

You can try again without specifying a model (just `@copilot`) to use the default, or choose a different model from the model picker.

If you want to contact GitHub about this error, please mention the following identifier so they can better serve you: `{{ .RequestID }}`

{{.Telemetry}}
