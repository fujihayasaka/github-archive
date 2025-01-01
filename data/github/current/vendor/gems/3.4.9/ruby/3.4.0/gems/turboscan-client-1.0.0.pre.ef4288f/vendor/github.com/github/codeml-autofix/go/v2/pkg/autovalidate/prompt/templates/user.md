# Code
{{range .CodeSnippets}}
file path: {{.File.Path}}

```
{{.Content}}
```
{{end}}
# Alert information

In {{ .Alert.Location.Path }} on line {{ .Alert.Location.StartLine }}, Code Scanning highlights ```{{ .AlertSnippet }}``` as an error with the message "{{ .Alert.Message }}".
The error type is: {{ .Alert | getAlertType }} ({{ .Alert.RuleId }})

# Suggested fix
{{- if .UseReplacementBlocks }}
{{range .Diffs}}
file path: {{.Path}}
{{range convertDiffToReplacementBlocks .Diff}}
original lines:
```
{{.OriginalLines}}
```
replacement lines:
```
{{.ReplacementLines}}
```
{{end -}}
{{end -}}
{{else}}
{{range .Diffs}}
```diff
{{.Diff}}
```
{{end -}}
{{end -}}