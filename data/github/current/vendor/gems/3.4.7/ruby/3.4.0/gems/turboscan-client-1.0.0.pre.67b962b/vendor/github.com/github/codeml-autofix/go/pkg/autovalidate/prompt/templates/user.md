# Code
{{range .CodeSnippets}}
file path: {{.File.Path}}

```
{{.Content}}
```
{{end}}
# Alert information

- Alert type: {{ .Alert | getAlertType }}
- Rule ID: {{ .Alert.RuleId }}
- Alert message: {{ .Alert.Message }}
- Alert file: {{ .Alert.Location.Path }}
- Alert lines: {{ .Alert.Location.StartLine }}-{{ .Alert.Location.EndLine }}

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