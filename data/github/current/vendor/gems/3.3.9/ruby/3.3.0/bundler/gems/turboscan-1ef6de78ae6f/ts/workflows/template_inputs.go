package workflows

import (
	"cmp"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/pkg/errors"
	"golang.org/x/exp/slices"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/transforms"
)

var CODEQL_LANGUAGE_MAPPING = map[string]string{
	"csharp":                "csharp",
	"c#":                    "csharp",
	"c-cpp":                 "cpp",
	"cpp":                   "cpp",
	"c":                     "cpp",
	"c++":                   "cpp",
	"go":                    "go",
	"java-kotlin":           "java",
	"java":                  "java",
	"javascript-typescript": "javascript",
	"javascript":            "javascript",
	"typescript":            "javascript",
	"python":                "python",
	"ruby":                  "ruby",
	"kotlin":                "java",
	"swift":                 "swift",
}

var NEW_CODEQL_LANGUAGE_MAPPING = map[string]string{
	"csharp":                "csharp",
	"c#":                    "csharp",
	"c-cpp":                 "c-cpp",
	"cpp":                   "c-cpp",
	"c":                     "c-cpp",
	"c++":                   "c-cpp",
	"go":                    "go",
	"java-kotlin":           "java-kotlin",
	"java":                  "java-kotlin",
	"javascript-typescript": "javascript-typescript",
	"javascript":            "javascript-typescript",
	"typescript":            "javascript-typescript",
	"python":                "python",
	"ruby":                  "ruby",
	"kotlin":                "java-kotlin",
	"swift":                 "swift",
}

var CODEQL_AUTOBUILDABLE_LANGUAGES = map[string]bool{"go": true, "java": true, "java-kotlin": true, "cpp": true, "c-cpp": true, "csharp": true, "swift": true}

// TemplateInputs holds the minimum data required to fill a workflow template
type TemplateInputs struct {
	Languages                 []string
	UsingCombinedLanguages    bool
	ValidationRun             bool
	AdjustConfiguration       bool
	ExtendedQuerySuite        bool
	BuildlessJavaExtraction   bool
	BuildlessCSharpExtraction bool
	CustomRegistries          bool
	ThreatModelInput          ts.ThreatModel

	// These inputs are defined at the repo/instance level and are not defined
	// by the config management logic.
	runnerLabel                 string
	nonGitHubHostedRunnerLabels []string
	codeqlActionVersion         string
	artifactActionVersion       string
	IncludeActionsYmlAnalysis   bool
	SetupProxy                  bool
}

func inputsFromConfig(c *ts.CodeqlConfig) *TemplateInputs {
	var runnerLabel string
	if c.UsingCSRunnerLabel {
		runnerLabel = cmp.Or(c.RunnerLabel, "code-scanning")
	}

	data := TemplateInputs{
		Languages:                 c.Languages,
		UsingCombinedLanguages:    c.UsingCombinedLanguages,
		ExtendedQuerySuite:        c.QuerySuiteType.IsExtended(),
		BuildlessJavaExtraction:   c.JavaExtractionOptions == ts.JavaExtractionOptions_BUILDLESS,
		BuildlessCSharpExtraction: c.CSharpExtractionOptions == ts.CSharpExtractionOptions_BUILDLESS,
		ThreatModelInput:          c.ThreatModel,
		runnerLabel:               runnerLabel,
	}

	return &data
}

func (d TemplateInputs) codeqlLanguages() []string {
	language_mapping := CODEQL_LANGUAGE_MAPPING
	if d.UsingCombinedLanguages {
		language_mapping = NEW_CODEQL_LANGUAGE_MAPPING
	}
	return transforms.MapUnique(d.Languages, func(in string) string { return language_mapping[strings.ToLower(in)] })
}

func (d TemplateInputs) GetFormattedLanguages() string {
	l := d.codeqlLanguages()
	return fmt.Sprintf("[ %s ]", strings.Join(l, ", "))
}

type LanguageMatrix struct {
	LanguageName string
	Category     string
	BuildMode    string
	Runner       string
}

var codeQLBuildModeMap = map[string]string{
	"csharp":                "autobuild",
	"c-cpp":                 "autobuild",
	"cpp":                   "autobuild",
	"go":                    "autobuild",
	"java-kotlin":           "autobuild",
	"java":                  "autobuild",
	"javascript":            "none",
	"javascript-typescript": "none",
	"python":                "none",
	"ruby":                  "none",
	"swift":                 "autobuild",
}

func (d TemplateInputs) getCategory(lang string) string {
	mainMap := CODEQL_LANGUAGE_MAPPING
	if d.UsingCombinedLanguages {
		mainMap = NEW_CODEQL_LANGUAGE_MAPPING
	}
	category, ok := mainMap[lang]
	if !ok {
		return fmt.Sprintf("/language:%s", lang)
	}
	return fmt.Sprintf("/language:%s", category)
}

func (d TemplateInputs) GetLanguageMatrix() []LanguageMatrix {
	return transforms.Map(d.codeqlLanguages(), func(lang string) LanguageMatrix {
		buildMode, ok := codeQLBuildModeMap[lang]
		if !ok {
			buildMode = "autobuild"
		}
		if lang == "java" || lang == "java-kotlin" || lang == "kotlin" {
			if d.BuildlessJavaExtraction {
				buildMode = "none"
			} else {
				buildMode = "autobuild"
			}
		} else if lang == "csharp" || lang == "c#" {
			if d.BuildlessCSharpExtraction {
				buildMode = "none"
			} else {
				buildMode = "autobuild"
			}
		}
		runner := d.GetRunnerAsJSON()
		if lang == "swift" {
			runner = d.GetMacOSRunnerAsJSON()
		}
		return LanguageMatrix{
			LanguageName: lang,
			Category:     d.getCategory(lang),
			BuildMode:    buildMode,
			Runner:       runner,
		}
	})
}

func (d TemplateInputs) GetLanguages() []string {
	return d.codeqlLanguages()
}

func appendLabel(items []string, item string) []string {
	if item == "" || slices.Contains(items, item) {
		return items
	}
	return append(items, item)
}

func (d TemplateInputs) runnerLabels() []string {
	labels := appendLabel(d.nonGitHubHostedRunnerLabels, d.runnerLabel)
	if len(labels) == 0 {
		return []string{"ubuntu-latest"}
	}
	return labels
}

func (d TemplateInputs) macOSRunnerLabels() []string {
	labels := appendLabel(d.nonGitHubHostedRunnerLabels, d.runnerLabel)
	if len(labels) == 0 {
		return []string{"macos-latest"}
	}
	return appendLabel(labels, "macOS")
}

func (d TemplateInputs) GetRunnerLabels() string {
	labels := d.runnerLabels()

	if len(labels) == 1 {
		return labels[0]
	}
	return fmt.Sprintf("[ %s ]", strings.Join(labels, ", "))
}

func (d TemplateInputs) GetRunnerAsJSON() string {
	labels := d.runnerLabels()

	jsonData, _ := json.Marshal(labels)
	return string(jsonData)
}

func (d TemplateInputs) GetMacOSRunnerAsJSON() string {
	labels := d.macOSRunnerLabels()

	jsonData, _ := json.Marshal(labels)
	return string(jsonData)
}

func (d TemplateInputs) IncludeValidation() bool {
	return d.ValidationRun
}

func (d TemplateInputs) AutoAdjustValidation() bool {
	return d.AdjustConfiguration
}

func (d TemplateInputs) AnalyzeJobContinueOnError() string {
	if d.AdjustConfiguration {
		return "true"
	}
	return "false"
}

func (d TemplateInputs) CodeQLActionVersion() string {
	return d.codeqlActionVersion
}

func (d TemplateInputs) ArtifactActionVersion() string {
	return d.artifactActionVersion
}

// IncludeAutobuild returns true if the workflow should include autobuild.
// We include the Autobuild step if there is at least one language that requires it.
// Note: For interpreted languages the autobuild is a no-op. Therefore, if a repo contains both a traced and an interpreted language, it is fine to include the autobuild step.
func (d TemplateInputs) IncludeAutobuild() bool {
	for _, l := range d.codeqlLanguages() {
		if _, ok := CODEQL_AUTOBUILDABLE_LANGUAGES[l]; ok {
			return true
		}
	}
	return false
}

func (d TemplateInputs) Validate() error {
	if d.codeqlActionVersion == "" {
		return errors.New("no codeql-action version provided")
	}
	if d.artifactActionVersion == "" {
		return errors.New("no artifact action version provided")
	}
	return nil
}

// Queries returns the query suite to use for the workflow.
// Currently the codeql-action expects to only pass the queries input if the query suite is not the default.
// For consistency, if the query suite is the default, we pass an empty string.
func (d TemplateInputs) Queries() string {
	querySuite := `"" # Default query suite`

	if d.ExtendedQuerySuite {
		querySuite = "security-extended"
	}
	return querySuite
}

func (d TemplateInputs) ThreatModel() string {
	if d.ThreatModelInput == ts.ThreatModel_REMOTE_LOCAL {
		return "local"
	}
	return ""
}

func (d TemplateInputs) SetupGo() bool {
	for _, l := range d.codeqlLanguages() {
		if l == "go" {
			return true
		}
	}
	return false
}

func (d TemplateInputs) HasSwift() bool {
	for _, l := range d.codeqlLanguages() {
		if l == "swift" {
			return true
		}
	}
	return false
}
