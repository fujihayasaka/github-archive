// Package autovalidate provides functionality to validate code fixes using an LLM.
package autovalidate

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
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/fix"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/model"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/prompt"
	"github.com/github/github-telemetry-go/kvp"
)

// AutoValidator is a struct that provides functionality to validate code fixes using an LLM.
type AutoValidator struct {
	config *Config
	model  models.Model
}

// AutoValidatorResponse represents the response from the AutoValidator after validating a fix. Contains both the verdict and the reasoning behind it (if the verdict is negative).
type AutoValidatorResponse struct {
	Verdict bool   `json:"verdict"`
	Reason  string `json:"reason"`
}

// NewAutoValidator creates a new AutoValidator instance with the provided configuration.
func NewAutoValidator(config *Config) (*AutoValidator, error) {
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

	if config.retry {
		validateModel = provider.NewRetryModel(validateModel)
	}

	if config.CachePath != "" {
		validateModel = provider.NewCachingModelFromPath(validateModel, config.CachePath)
	}

	return &AutoValidator{config: config, model: validateModel}, nil
}

// Validate validates a code fix using the configured LLM model.
func (v *AutoValidator) Validate(ctx context.Context, autofix *fix.Fix, codeBase codebase.VirtualCodebase) (*AutoValidatorResponse, error) {
	logger := enhancedctx.Logger(ctx)

	var forReasoningModel bool
	if strings.Contains(strings.ToLower(v.model.GetModelName()), "gpt") {
		forReasoningModel = false
	} else {
		forReasoningModel = true
	}

	useReplacementBlocks := false

	logger.Debug("Validation parameters",
		kvp.String("auto-validator.param.model.name", v.model.GetModelName()),
		kvp.String("auto-validator.param.model.provider", v.model.GetProviderName()),
		kvp.Bool("auto-validator.param.use-replacement-blocks", useReplacementBlocks),
		kvp.Bool("auto-validator.param.for-reasoning-model", forReasoningModel))

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
		{
			Content: systemPrompt,
			Role:    role,
		},
	}

	modelParameters := model.DefaultModelParameters

	userPrompt, err := prompt.BuildUserPrompt(autofix, codeBase, &modelParameters, useReplacementBlocks)
	if err != nil {
		return nil, err
	}

	logger.Debug("Prompts", kvp.String("auto-validator.prompt.system", systemPrompt), kvp.String("auto-validator.prompt.user", userPrompt))

	chatHistory = append(chatHistory, models.ChatMessage{
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

	logger.Debug("Validation attempt", kvp.String("auto-validator.validation.reasoning", reasoning), kvp.String("auto-validator.validation.verdict", verdict))

	switch {
	case strings.Contains(verdict, "yes"):
		logger.Debug("Validation verdict", kvp.Bool("auto-validator.validation.accepted", true))
		return &AutoValidatorResponse{Verdict: true, Reason: ""}, nil
	case strings.Contains(verdict, "no"):
		logger.Debug("Validation verdict", kvp.Bool("auto-validator.validation.accepted", false))
		return &AutoValidatorResponse{Verdict: false, Reason: reasoning}, nil
	}

	return nil, errors.Errorf("failed to get valid response from model: %s", response)
}
