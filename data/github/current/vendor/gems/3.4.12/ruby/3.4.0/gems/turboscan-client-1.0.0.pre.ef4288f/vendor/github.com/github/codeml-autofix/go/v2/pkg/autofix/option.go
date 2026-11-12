package autofix

import (
	"fmt"

	"github.com/pkg/errors"
)

// CliOptions holds the command line options for the autofix tool.
type CliOptions struct {
	// Options shared between the TypeScript and Go implementations of autofix.

	Sarif           string  `json:"sarif,omitempty"`
	OnlyAlertNumber int     `json:"onlyAlertNumber,omitempty"`
	SourceRoot      string  `json:"sourceRoot,omitempty"`
	AllowedQueries  string  `json:"allowedQueries,omitempty"`
	Dev             bool    `json:"dev,omitempty"`
	AllowAllRules   bool    `json:"allowAllRules,omitempty"`
	Model           string  `json:"model,omitempty"`
	PromptTemplate  string  `json:"promptTemplate,omitempty"`
	Temperature     float64 `json:"temperature,omitempty"`
	MaxTokens       int     `json:"maxTokens,omitempty"`
	Cache           string  `json:"cache,omitempty"`
	NoCache         bool    `json:"noCache,omitempty"`
	NoRetry         bool    `json:"noRetry,omitempty"`
	Stream          bool    `json:"stream,omitempty"`
	Write           bool    `json:"write,omitempty"`
	Output          string  `json:"output,omitempty"`
	Format          string  `json:"format,omitempty"`
	DiffStyle       string  `json:"diffStyle,omitempty"`
	Transcript      string  `json:"transcript,omitempty"`
	Log             string  `json:"log,omitempty"`
	FixDescription  string  `json:"fixDescription,omitempty"`
	SarifOutput     string  `json:"sarifOutput,omitempty"`
	Verbose         bool    `json:"verbose,omitempty"`
	Quiet           bool    `json:"quiet,omitempty"`
	ClientName      string  `json:"clientName,omitempty"`
	IntegrationID   string  `json:"integrationId,omitempty"`

	// Options specific to the Go implementation of autofix.

	MockModelConversationLog string `json:"mockModelConversationLog,omitempty"`
	Passthru                 bool   `json:"passthru,omitempty"`
	PreviousAttempts         string `json:"previousAttempts,omitempty"`
}

// Validate checks that the options are valid
func (o *CliOptions) Validate() error {
	if o.Sarif == "" {
		return errors.New("sarif file is required")
	}
	return nil
}

// ToArgs converts the CliOptions to a slice of strings suitable for passing to exec.Command
func (o *CliOptions) ToArgs() []string {
	args := []string{}

	addFlag := func(name string, value interface{}) {
		switch v := value.(type) {
		case string:
			if v != "" {
				args = append(args, fmt.Sprintf("--%s", name), v)
			}
		case bool:
			if v {
				args = append(args, fmt.Sprintf("--%s", name))
			}
		case int:
			args = append(args, fmt.Sprintf("--%s", name), fmt.Sprintf("%d", v))
		case float64:
			args = append(args, fmt.Sprintf("--%s", name), fmt.Sprintf("%f", v))
		}
	}

	addFlag("sarif", o.Sarif)
	if o.OnlyAlertNumber != -1 {
		addFlag("only-alert-number", o.OnlyAlertNumber)
	}
	addFlag("source-root", o.SourceRoot)
	addFlag("allowed-queries", o.AllowedQueries)
	addFlag("dev", o.Dev)
	addFlag("allow-all-rules", o.AllowAllRules)
	addFlag("model", o.Model)
	addFlag("prompt-template", o.PromptTemplate)
	addFlag("temperature", o.Temperature)
	addFlag("max-tokens", o.MaxTokens)
	addFlag("cache", o.Cache)
	addFlag("no-cache", o.NoCache)
	addFlag("no-retry", o.NoRetry)
	addFlag("stream", o.Stream)
	addFlag("write", o.Write)
	addFlag("output", o.Output)
	addFlag("format", o.Format)
	addFlag("diff-style", o.DiffStyle)
	addFlag("transcript", o.Transcript)
	addFlag("log", o.Log)
	addFlag("fix-description", o.FixDescription)
	addFlag("sarif-output", o.SarifOutput)
	addFlag("previous-attempts", o.PreviousAttempts) // not really needed, as the TS implementation doesn't support this flag. But keeping it around in case that changes.
	addFlag("verbose", o.Verbose)
	addFlag("quiet", o.Quiet)
	addFlag("client-name", o.ClientName)
	addFlag("integration-id", o.IntegrationID)

	return args
}
