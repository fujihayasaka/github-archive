## The detected `{{ .Alert.Rule.ShortDescription }}` error
The previous section provided background information about this general kind of error, but you cannot directly use it to fix the code. This section is about the concrete error to fix in the current codebase.

{{ if .SingleFileFlowContext -}}
{{ call .RenderAlert .SingleFileFlowContext.ContextSet.WithExtractedPreamble .Alert.Context.File.Path }}

Moreover, {{ .Alert.Tool }} has identified the following path along which untrusted data flow from an untrusted source to a vulnerable sink in the snippet:
{{- range .SingleFileFlowContext.StepsNotContainingTheirPredecessor }}
  - line {{ .Location.StartLine }}: {{ code .Location.Text }} is tainted.
{{- end }}

{{/* TODO: reference the template directly */ -}}
{{ (index .VariantsWithLinksPrompts 0).MessageLinksPrompt -}}
{{ else -}}
{{ call .RenderAlert .Alert.Context.WithExtractedPreamble .Alert.Context.File.Path }}

{{ (index .VariantsWithLinksPrompts 0).MessageLinksPrompt -}}
{{ if .Alert.CollapsedFlow -}}
Moreover, {{ .Alert.Tool }} has identified the following path along which untrusted data flow from an untrusted source to a vulnerable sink along the steps highlighted in the snippets below:

{{ range $index, $node := .Alert.CollapsedFlow -}}
{{- if not $.OmitCodeBlocks -}}
### Snippet {{inc $index}} ({{ $node.File.Path }}):
{{ codeBlock (textWithLineNumbers $node.ContextSet.WithExtractedPreamble) $node.ContextSet.File.Path }}
The data flows through the above snippet with the following steps:
{{- else -}}
### Step {{inc $index}} ({{ $node.File.Path }}):
The data flows with the following steps:
{{- end }}
{{- range $node.StepsNotContainingTheirPredecessor }}
  - line {{ .Location.StartLine }}: {{ code .Location.Text }} is tainted.
{{- end }}

{{ end -}}
{{ end -}}
{{- end -}}
{{ if gt (len .VariantsWithLinksPrompts) 1 }}
## Alert Variants

There are {{ len .VariantsWithLinksPrompts }} detected variants of this alert in total; the {{ len (slice .VariantsWithLinksPrompts 1) }} additional variants (beyond the first described above) occur at the same location with differing messages and/or links. If possible, make a single fix addressing them all; otherwise fixing each variant individually is still valuable.

{{ range $i, $v := .VariantsWithLinksPrompts -}}
{{ if gt $i 0 -}}
### Additional Alert Variant {{ $.AlertNumber }}{{ indexToLetters $i }}

Alert variant description: {{ $v.Message }}

{{ $v.MessageLinksPrompt -}}

{{ end -}}
{{ end -}}

{{ end -}}
