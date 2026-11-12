// Package aigen provides AI-powered name generation for branches and sessions.
package aigen

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/invopop/jsonschema"
	"github.com/openai/openai-go"
	"go.opentelemetry.io/otel/attribute"
)

//go:embed prompts/job_data.txt
var jobDataPromptTemplate string

//go:embed prompts/job_data_improved.txt
var jobDataImprovedPromptTemplate string

var (
	// invalidCharsRegex matches any character that is not alphanumeric or hyphen
	invalidCharsRegex = regexp.MustCompile(`[^a-z0-9-]`)
	// multipleHyphensRegex matches one or more consecutive hyphens
	multipleHyphensRegex = regexp.MustCompile(`-+`)
)

const (
	// AIModelDefault is the default OpenAI model used for name generation
	AIModelDefault = "gpt-4o-mini"
	// AIModelGPT54Nano is the alternative OpenAI model used for name generation when feature flag is enabled
	AIModelGPT54Nano = "gpt-5.4-nano"
	// MaxContentLength is the maximum length of content to send to AI
	MaxContentLength = 1000
	// MaxBranchNameLength is the maximum length for branch names
	MaxBranchNameLength = 50
	// MaxSessionNameLength is the maximum length for session names
	MaxSessionNameLength = 60
)

// NameGenerator provides AI-powered name generation for branches and sessions
type NameGenerator struct {
	obsv       observability.Exporters
	capiClient capi.Client
	ffs        featureflags.Client
}

// NewNameGenerator creates a new NameGenerator instance
func NewNameGenerator(obsv observability.Exporters, capiClient capi.Client, ffs featureflags.Client) *NameGenerator {
	return &NameGenerator{
		obsv:       obsv,
		capiClient: capiClient,
		ffs:        ffs,
	}
}

// JobData holds the AI-generated data for a job
type JobData struct {
	BranchName       string `json:"branch_name"        jsonschema_description:"Name of the branch that will be created"`
	SessionName      string `json:"session_name"       jsonschema_description:"Name of the session that will be created"`
	PullRequestTitle string `json:"pull_request_title" jsonschema_description:"Name of the pull request that will be created"`
}

// GenerateSchema generates a JSON schema for the given type T
func GenerateSchema[T any]() any {
	// Structured Outputs uses a subset of JSON schema
	// These flags are necessary to comply with the subset
	reflector := jsonschema.Reflector{
		AllowAdditionalProperties: false,
		DoNotReference:            true,
	}
	var v T
	schema := reflector.Reflect(v)
	return schema
}

// JobDataResponseSchema is the JSON schema for JobData
var JobDataResponseSchema = GenerateSchema[JobData]()

// GenerateJobData generates a struct of information for a given job according to the problem statement.
// Using an LLM, it returns some AI-generated content - ex: branch name, pull request title, session name.
func (ng *NameGenerator) GenerateJobData(ctx context.Context, job *jobs.Job, branchNamePattern string) (*JobData, error) {
	ctx, span := ng.obsv.Tracer.Start(ctx, "aigen.GenerateJobData")
	defer span.End()
	logger := ng.obsv.LoggerWithTelemetry(ctx)
	logger.Info("Using AI to generate job related content")

	ps := job.ProblemStatement.Content
	// When enabled, use only the user's base-provided prompt (the event content)
	// rather than the full problem statement, which may include additional
	// derived context (issue body, PR body, etc.).
	if ng.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentAINameGenerationUseEventContent, job) && job.EventContent != "" {
		ps = job.EventContent
	}
	if ps == "" {
		return nil, goerrors.New("no problem statement content available")
	}

	// Truncate content if too long (keep it under 1000 chars for efficiency)
	if len(ps) > MaxContentLength {
		ps = ps[:MaxContentLength] + "..."
	}

	// Select the model based on feature flag
	model := AIModelDefault
	if ng.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentAINameGenerationUseGPT54Nano, job) {
		model = AIModelGPT54Nano
	}
	span.SetAttributes(attribute.String("job.aigen.model", model))

	// Select the prompt template based on feature flag
	promptTemplate := jobDataPromptTemplate
	if ng.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentAINameGenerationImprovedPrompt, job) {
		promptTemplate = jobDataImprovedPromptTemplate
	}

	if ng.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentAIBranchNameGenerationFollowsRules, job) {
		promptTemplate += "\n\nOnly if provided by the user prompt use their exact branch name and DO NOT ADD ANY EXTRA DESCRIPTIONS TO THE BRANCH NAME."
		if branchNamePattern != "" {
			promptTemplate += fmt.Sprintf("\n\n**branch name %s** ", branchNamePattern)
		}
	}

	schemaParam := openai.ResponseFormatJSONSchemaJSONSchemaParam{
		Name:        "job_data",
		Description: openai.String("Data for a Copilot Coding Agent job that is being created"),
		Schema:      JobDataResponseSchema,
		Strict:      openai.Bool(true),
	}

	response, err := ng.capiClient.ChatCompletions(ctx, fmt.Sprintf("%d", job.ActorID), job.ID, &openai.ChatCompletionNewParams{
		Model: model,
		Messages: []openai.ChatCompletionMessageParamUnion{
			openai.SystemMessage(promptTemplate),
			openai.UserMessage(ps),
		},
		ResponseFormat: openai.ChatCompletionNewParamsResponseFormatUnion{
			OfJSONSchema: &openai.ResponseFormatJSONSchemaParam{
				JSONSchema: schemaParam,
			},
		},
	})
	if err != nil {
		return nil, err
	}

	var jd *JobData
	err = json.Unmarshal([]byte(response.Choices[0].Message.Content), &jd)
	if err != nil {
		return nil, err
	}

	// Sanitize the branch name to ensure it's valid
	jd.BranchName = sanitizeBranchName(jd.BranchName)

	return jd, nil
}

// sanitizeBranchName cleans the branch name to ensure it's valid for git
func sanitizeBranchName(name string) string {
	// Convert to lowercase
	name = strings.ToLower(name)

	// Replace spaces and underscores with hyphens
	name = strings.ReplaceAll(name, " ", "-")
	name = strings.ReplaceAll(name, "_", "-")

	// Remove invalid characters (only allow alphanumeric and hyphens)
	name = invalidCharsRegex.ReplaceAllString(name, "")

	// Remove multiple consecutive hyphens
	name = multipleHyphensRegex.ReplaceAllString(name, "-")

	// Remove leading/trailing hyphens
	name = strings.Trim(name, "-")

	// Ensure it's not too long (max 50 chars for branch suffix)
	if len(name) > MaxBranchNameLength {
		name = name[:MaxBranchNameLength]
		name = strings.Trim(name, "-")
	}

	return name
}
