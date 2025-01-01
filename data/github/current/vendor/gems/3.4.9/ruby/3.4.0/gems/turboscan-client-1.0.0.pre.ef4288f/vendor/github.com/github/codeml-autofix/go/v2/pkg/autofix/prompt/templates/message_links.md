{{- if (not (eq (len .Alert.Links) 0)) -}}
{{- range .Alert.Links -}}
{{- if .Context -}}
In the alert message, the string "[{{ .Text }}](#{{ .TargetId }})" is a link to {{ code .Target.Text }} on line {{ .Target.StartLine }} in {{ .Target.File.Path }} shown below.

{{ codeBlock (textWithLineNumbers .Context.WithExtractedPreamble) .Context.File.Path }}
{{- else -}}
In the alert message, the string "[{{ .Text }}](#{{ .TargetId }})" is a link to {{ code .Target.Text }} on line {{ .Target.StartLine }} in {{ .Target.File.Path }}.
{{- end }}

{{ end -}}
{{- end -}}
