{{- if not .OmitCodeBlocks -}}
Consider the code below from file {{ .Alert.Location.File.Path }}.

{{ codeBlock (textWithLineNumbers .ContextSet) .FilePath }}

On line {{ .Alert.Location.StartLine }}, {{ .Alert.Tool }} highlights {{ code .Alert.Location.Text }} as an error with the description "{{ .Message }}".
{{- else -}}
On line {{ .Alert.Location.StartLine }} of `{{ .Alert.Location.File.Path }}`, {{ .Alert.Tool }} highlights {{ code .Alert.Location.Text }} as an error with the description "{{ .Message }}".
{{- end -}}
