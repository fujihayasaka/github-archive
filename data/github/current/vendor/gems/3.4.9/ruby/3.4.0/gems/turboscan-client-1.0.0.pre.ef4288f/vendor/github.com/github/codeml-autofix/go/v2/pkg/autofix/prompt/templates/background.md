## Background
{{- if .Alert.Rule.Documentation }}
{{ increaseMarkdownHeaderLevels .Alert.Rule.Documentation 2 }}
{{- else }}
The {{ .Alert.Tool }} rule has the following description: {{ if .Alert.Rule.FullDescription -}}
{{ .Alert.Rule.FullDescription }}
{{- else -}}
{{ .Alert.Rule.ShortDescription }}
{{- end -}}
{{- end }}
