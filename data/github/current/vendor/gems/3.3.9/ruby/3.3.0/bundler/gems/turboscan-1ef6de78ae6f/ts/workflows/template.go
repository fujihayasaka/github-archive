// Package workflows provides methods for generating Actions workflow files
// to run CodeQL analysis.
package workflows

import (
	"bytes"
	"cmp"
	"embed"
	"strings"
	"text/template"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"
	"go.uber.org/zap/zapcore"
)

//go:embed versions/*.codeql.template
var templateVersions embed.FS

// CodeQLActionVersionV3 defines the tag/branch for the codeql-action.
// For testing, we use the RC branch.
const (
	CodeQLActionVersionV3 = "v3"
	CodeQLActionRCVersion = "default-setup-testing"
)

// Defines the versions of actions/upload-artifact and actions/download-artifact
const (
	ArtifactActionVersionV3 = "v3-node20"
	ArtifactActionVersionV4 = "v4"
)

type WorkflowTemplate struct {
	Version  string
	template *template.Template

	// These values are set at the template level
	defaultNonGitHubHostedRunnerLabel string
	codeqlActionVersion               string
	artifactActionVersion             string
	useCustomRegistries               bool
	includeActionsYmlAnalysis         bool
	setupProxy                        bool
}

func (t *WorkflowTemplate) AsKVP() zapcore.Field {
	return kvp.String("gh.turboscan.workflow_template_version", t.Version)
}

func (t *WorkflowTemplate) GetVersion() string {
	return t.Version
}

// CodeQLValidationWorkflow creates a workflow file for validating the CodeQL setup
func (t *WorkflowTemplate) CodeQLValidationWorkflow(c *ts.CodeqlConfig, autoAdjustConfig bool) (string, error) {
	data := inputsFromConfig(c)
	data.ValidationRun = true
	data.AdjustConfiguration = autoAdjustConfig
	return t.CreateWorkflowString(*data)
}

// CodeQLWorkflow creates a workflow file for running CodeQL analysis
func (t *WorkflowTemplate) CodeQLWorkflow(c *ts.CodeqlConfig) (string, error) {
	data := inputsFromConfig(c)
	return t.CreateWorkflowString(*data)
}

// CreateWorkflowString creates a workflow string for running CodeQL analysis.
func (t *WorkflowTemplate) CreateWorkflowString(data TemplateInputs) (string, error) {
	if t.Version == "" {
		return "", errors.New("no template version provided")
	}

	data.runnerLabel = cmp.Or(data.runnerLabel, t.defaultNonGitHubHostedRunnerLabel)
	data.codeqlActionVersion = t.codeqlActionVersion
	data.artifactActionVersion = t.artifactActionVersion
	data.CustomRegistries = t.useCustomRegistries
	data.IncludeActionsYmlAnalysis = t.includeActionsYmlAnalysis
	data.SetupProxy = t.setupProxy
	err := data.Validate()
	if err != nil {
		return "", err
	}

	if t.template == nil {
		c, err := templateVersions.ReadFile("versions/" + t.Version + ".codeql.template")
		if err != nil {
			return "", err
		}
		tmpl := template.New("Workflow")
		// We use custom delimeters because "{{" and "}}" already occur in the file
		tmpl.Delims("[TS ", " TS]")
		tmpl.Funcs(template.FuncMap{"toUnderscore": dashToUnderscore})
		tmpl = template.Must(tmpl.Parse(string(c)))
		t.template = tmpl
	}

	var b bytes.Buffer
	err = t.template.Execute(&b, data)
	if err != nil {
		return "", errors.Wrap(err, "populating the workflow template failed")
	}
	return b.String(), nil
}

func dashToUnderscore(in string) string {
	return strings.ReplaceAll(in, "-", "_")
}
