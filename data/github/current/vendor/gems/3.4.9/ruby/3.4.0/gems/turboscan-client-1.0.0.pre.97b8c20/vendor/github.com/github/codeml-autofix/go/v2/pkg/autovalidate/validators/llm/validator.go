// Package llm provides functionality to validate code fixes using an LLM.
package llm

import (
	"context"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/code-scanning-ai-libraries/v2/llm/provider"
	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	AutofixConfig "github.com/github/codeml-autofix/go/v2/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/exec"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/fix"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/output"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/validators"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/validators/llm/model"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/validators/llm/prompt"
	"github.com/github/github-telemetry-go/kvp"
)

const validator = "llm"

// Validator is a struct that provides functionality to validate code fixes using an LLM.
type Validator struct {
	config *Config
	model  models.Model
}

// SupportedOutputFormats returns the list of output formats supported by this validator.
func (v *Validator) SupportedOutputFormats() []output.Format {
	return []output.Format{output.FormatAutofixFeedback}
}

// NewValidator creates a new AutoValidator instance with the provided configuration.
func NewValidator(config *Config) (validators.Validator, error) {
	if config == nil {
		return nil, errors.New("config cannot be nil")
	}

	autofixConfigBuilder := AutofixConfig.NewConfigBuilder()

	if config.CAPIKey != "" {
		autofixConfigBuilder.WithDevelopmentKey(config.CAPIKey).WithProductionKey(config.CAPIKey)
	}

	autofixConfig, err := autofixConfigBuilder.Build()
	if err != nil {
		return nil, st.EnsureStackTrace(err, "failed to create config")
	}

	modelConfig := autofixConfig.ToModelConfig()
	validateModel, err := utils.CreatePrevalidatingModel(context.Background(), config.Model, &modelConfig)
	if err != nil {
		return nil, st.EnsureStackTrace(err, "failed to create LLM client")
	}

	if config.Retry {
		validateModel = provider.NewRetryModel(validateModel)
	}

	if config.CachePath != "" {
		validateModel = provider.NewCachingModelFromPath(validateModel, config.CachePath)
	}

	return &Validator{config: config, model: validateModel}, nil
}

// Validate validates a code fix using the configured LLM model.
func (v *Validator) Validate(ctx context.Context, autofix *fix.Fix, codeBase codebase.VirtualCodebase, _ exec.CommandEnvironment, outputFormat output.Format) (validators.Result, error) {
	logger := enhancedctx.Logger(ctx)

	var forReasoningModel bool
	if strings.Contains(strings.ToLower(v.model.GetModelName()), "gpt") {
		forReasoningModel = false
	} else {
		forReasoningModel = true
	}

	useReplacementBlocks := false

	logger.Debug("Validation parameters",
		kvp.String("validator", "llm"),
		kvp.String("param.model.name", v.model.GetModelName()),
		kvp.String("param.model.provider", v.model.GetProviderName()),
		kvp.Bool("param.use-replacement-blocks", useReplacementBlocks),
		kvp.Bool("param.for-reasoning-model", forReasoningModel))

	systemPrompt, err := prompt.BuildSystemPrompt(useReplacementBlocks, forReasoningModel)
	if err != nil {
		return nil, err
	}

	role := models.ChatMessageRoleSystem

	// System message is not yet supported in o1 models (https://platform.openai.com/docs/guides/reasoning#beta-limitations)
	// TODO: remove this once o1 models support chat.
	if v.model.GetModelName() == "o1-preview" || v.model.GetModelName() == "o1-mini" {
		role = models.ChatMessageRoleUser
	}

	chatHistory := []models.ChatMessage{
		{ //nolint:exhaustruct // We don't need all properties
			Content: systemPrompt,
			Role:    role,
		},
	}

	modelParameters := model.DefaultParameters

	userPrompt, err := prompt.BuildUserPrompt(autofix, codeBase, &modelParameters, useReplacementBlocks)
	if err != nil {
		return nil, err
	}

	logger.Debug("Prompts",
		kvp.String("validator", "llm"),
		kvp.String("prompt.system", systemPrompt),
		kvp.String("prompt.user", userPrompt))

	chatHistory = append(chatHistory, models.ChatMessage{ //nolint:exhaustruct // We don't need all properties
		Content: userPrompt,
		Role:    models.ChatMessageRoleUser,
	})

	completionOptions := models.MkDefaultCompletionOptions()
	freshTemperature := v.config.Temperature
	completionOptions.Temperature = &freshTemperature

	response, _, _, autofixErr := v.model.Complete(ctx, chatHistory, nil, completionOptions)
	if autofixErr != nil {
		return nil, st.EnsureStackTrace(autofixErr, "failed to get completion from model")
	}

	responseParts := strings.Split(response, "# Apply this fix?")
	if len(responseParts) != 2 {
		return nil, errors.Errorf("invalid response from model: %s", response)
	}

	// The model sometimes returns the reasoning in a code block, so we need to trim it.
	reasoning := strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(responseParts[0], "```markdown"), "```"))

	// Remove an optional leading "# Classification" header that the model may include
	const classificationPrefix = "# Classification"
	if strings.HasPrefix(reasoning, classificationPrefix) {
		reasoning = strings.TrimSpace(strings.TrimPrefix(reasoning, classificationPrefix))
	}

	// Strip optional "incorrect"/"good" prefixes the model sometimes adds
	for _, prefix := range []string{"incorrect: ", "incorrect\n", "good: ", "good\n", "incorrect fix: ", "good fix: "} {
		if strings.HasPrefix(strings.ToLower(reasoning), prefix) {
			reasoning = strings.TrimSpace(reasoning[len(prefix):])
			break
		}
	}

	verdict := strings.TrimSpace(strings.ToLower(responseParts[1]))

	logger.Debug("Validation attempt",
		kvp.String("validator", "llm"),
		kvp.String("reasoning", reasoning),
		kvp.String("verdict", verdict))

	switch {
	case strings.Contains(verdict, "yes"):
		logger.Debug("Validation verdict",
			kvp.String("validator", "llm"),
			kvp.Bool("accepted", true))
		return &output.AutofixFeedbackOutput{Validator: validator, Verdict: true, Reason: ""}, nil
	case strings.Contains(verdict, "no"):
		logger.Debug("Validation verdict",
			kvp.String("validator", "llm"),
			kvp.Bool("accepted", false))
		return &output.AutofixFeedbackOutput{Validator: validator, Verdict: false, Reason: reasoning}, nil
	}

	return nil, errors.Errorf("failed to get valid response from model: %s", response)
}
