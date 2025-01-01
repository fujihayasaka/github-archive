package prompt

import (
	"bytes"
	"embed"
	"path"
	"text/template"
)

//go:embed templates/*.md
var templates embed.FS

func ExecuteTemplate(templateName string, templateParameters interface{}, templateActions template.FuncMap) (string, error) {
	templatePath := path.Join("templates", templateName)

	template, err := template.New(templateName).Funcs(templateActions).ParseFS(templates, templatePath)
	if err != nil {
		return "", err
	}

	var templateBuffer bytes.Buffer
	if err := template.Execute(&templateBuffer, templateParameters); err != nil {
		return "", err
	}
	return templateBuffer.String(), nil
}
