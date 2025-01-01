## The detected `{{ .Alert.Rule.ShortDescription }}` error
The previous section provided background information about this general kind of error, but you cannot directly use it to fix the code. This section is about the concrete error to fix in the current codebase.

{{ if .SingleFileFlowContext -}}
Consider the code below from file {{ .Alert.Location.File.Path }}.

{{ codeBlock (textWithLineNumbers .SingleFileFlowContext.ContextSet.WithExtractedPreamble) .Alert.Context.File.Path }}

On line {{ .Alert.Location.StartLine }}, {{ .Alert.Tool }} highlights {{ code .Alert.Location.Text }} as an error with the description "{{ .Alert.Message }}".

Moreover, {{ .Alert.Tool }} has identified the following path along which untrusted data flow from an untrusted source to a vulnerable sink in the snippet:
{{- range .SingleFileFlowContext.StepsNotContainingTheirPredecessor }}
  - line {{ .Location.StartLine }}: {{ code .Location.Text }} is tainted.
{{- end }}

{{/* TODO: reference the template directly */ -}}
{{ .MessageLinks -}}
{{ else -}}
Consider the code below from file {{ .Alert.Location.File.Path }}.

{{ codeBlock (textWithLineNumbers .Alert.Context.WithExtractedPreamble) .Alert.Context.File.Path }}

On line {{ .Alert.Location.StartLine }}, {{ .Alert.Tool }} highlights {{ code .Alert.Location.Text }} as an error with the description "{{ .Alert.Message }}".

{{ .MessageLinks }}
{{ if .Alert.CollapsedFlow -}}
Moreover, {{ .Alert.Tool }} has identified the following path along which untrusted data flow from an untrusted source to a vulnerable sink along the steps highlighted in the snippets below:

{{ range $index, $node := .Alert.CollapsedFlow -}}
### Snippet {{inc $index}} ({{ $node.File.Path }}):
{{ codeBlock (textWithLineNumbers $node.ContextSet.WithExtractedPreamble) $node.ContextSet.File.Path }}
The data flows through the above snippet with the following steps:
{{- range $node.StepsNotContainingTheirPredecessor }}
  - line {{ .Location.StartLine }}: {{ code .Location.Text }} is tainted.
{{- end }}

{{ end -}}
{{ end -}}
{{- end -}}
