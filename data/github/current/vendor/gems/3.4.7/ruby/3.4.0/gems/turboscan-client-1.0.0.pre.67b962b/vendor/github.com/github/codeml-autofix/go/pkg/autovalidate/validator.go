package autovalidate

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/github/codeml-autofix/go/pkg/autofix/codebase"
	AutofixConfig "github.com/github/codeml-autofix/go/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/provider"
	"github.com/github/codeml-autofix/go/pkg/autovalidate/fix"
	"github.com/github/codeml-autofix/go/pkg/autovalidate/model"
	"github.com/github/codeml-autofix/go/pkg/autovalidate/prompt"
	"github.com/github/github-telemetry-go/kvp"
)

type AutoValidator struct {
	config *Config
	model  models.HashableModel
}

type AutoValidatorResponse struct {
	Verdict bool     `json:"verdict"`
	Reasons []string `json:"reasons"`
}

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
		return nil, fmt.Errorf("failed to create config: %w", err)
	}

	model, err := llm.GetModel(context.Background(), config.Model, autofixConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create LLM client: %w", err)
	}

	if config.retry {
		model = provider.NewRetryModel(model)
	}

	if config.CachePath != "" {
		model = provider.NewCachingModelFromPath(model, config.CachePath)
	}

	return &AutoValidator{config: config, model: model}, nil
}

func (v *AutoValidator) Validate(ctx context.Context, fix *fix.Fix, codeBase codebase.VirtualCodebase) (*AutoValidatorResponse, error) {
	logger := enhancedctx.Logger(ctx)

	var forReasoningModel bool
	if v.model.GetModelGeneration() == provider.ModelGPT4O || v.model.GetModelGeneration() == provider.ModelGPT41 {
		forReasoningModel = false
	} else {
		forReasoningModel = true
	}

	useReplacementBlocks := false

	logger.Debug("Validation parameters",
		kvp.String("auto-validator.param.model.name", v.model.GetModelName()),
		kvp.String("auto-validator.param.model.generation", v.model.GetModelGeneration()),
		kvp.Bool("auto-validator.param.use-replacement-blocks", useReplacementBlocks),
		kvp.Bool("auto-validator.param.for-reasoning-model", forReasoningModel))

	systemPrompt, err := prompt.BuildSystemPrompt(useReplacementBlocks, forReasoningModel)
	if err != nil {
		return nil, err
	}

	role := models.ChatMessageRoleSystem

	// System message is not yet supported in o1 models (https://platform.openai.com/docs/guides/reasoning#beta-limitations)
	// TODO: remove this once o1 models support chat.
	if v.model.GetModelGeneration() == "o1-preview" || v.model.GetModelGeneration() == "o1-mini" {
		role = models.ChatMessageRoleUser
	}

	chatHistory := []models.ChatMessage{
		{
			Content: systemPrompt,
			Role:    role,
		},
	}

	modelParameters := model.DefaultModelParameters
	// TODO: get max tokens from model, currently not using it because this returns a max of 1024 tokens?
	//modelParameters.MaxPromptTokens = v.llmClient.GetMaxTokens()
	userPrompt, err := prompt.BuildUserPrompt(fix, codeBase, &modelParameters, useReplacementBlocks)
	if err != nil {
		return nil, err
	}

	logger.Debug("Prompts", kvp.String("auto-validator.prompt.system", systemPrompt), kvp.String("auto-validator.prompt.user", userPrompt))

	chatHistory = append(chatHistory, models.ChatMessage{
		Content: userPrompt,
		Role:    models.ChatMessageRoleUser,
	})

	correctVotes := 0
	invalidReasons := make([]string, 0)

	completionOptions := v.model.GetDefaultCompletionOptions()
	initialTemperature := completionOptions.Temperature
	for round := range v.config.VotingRounds {
		temperature := initialTemperature + float64(round)*0.0001
		completionOptions.Temperature = temperature
		response, autofixErr := v.model.CompleteWithOptions(context.Background(), chatHistory, &completionOptions)
		if autofixErr != nil {
			return nil, fmt.Errorf("failed to get completion from model: %w", autofixErr)
		}

		responseParts := strings.Split(response, "# Apply this fix?")
		if len(responseParts) != 2 {
			return nil, fmt.Errorf("invalid response from model: %s", response)
		}

		// The model sometimes returns the reasoning in a code block, so we need to trim it.
		reasoning := strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(responseParts[0], "```markdown"), "```"))
		verdict := strings.TrimSpace(strings.ToLower(responseParts[1]))

		logger.Debug("Validation attempt", kvp.Int("auto-validator.validation.round", round), kvp.Float64("auto-validator.validation.temperature", temperature), kvp.String("auto-validator.validation.reasoning", reasoning), kvp.String("auto-validator.validation.verdict", verdict))

		if strings.Contains(verdict, "yes") {
			correctVotes++
			continue
		} else if strings.Contains(verdict, "no") {
			invalidReasons = append(invalidReasons, reasoning)
			// If we need all the votes, short-circuit if we have a negative verdict.
			if v.config.RequiredVotes == v.config.VotingRounds {
				logger.Debug("Validation verdict", kvp.Bool("auto-validator.validation.accepted", false), kvp.Int("auto-validator.validation.correct-votes", correctVotes), kvp.Int("auto-validator.validation.required-votes", v.config.RequiredVotes))
				return &AutoValidatorResponse{Verdict: false, Reasons: invalidReasons}, nil
			}
			continue
		} else {
			return nil, fmt.Errorf("failed to get valid response from model: %s", response)
		}
	}

	if correctVotes >= v.config.RequiredVotes {
		logger.Debug("Validation verdict", kvp.Bool("auto-validator.validation.accepted", true), kvp.Int("auto-validator.validation.correct-votes", correctVotes), kvp.Int("auto-validator.validation.required-votes", v.config.RequiredVotes))
		return &AutoValidatorResponse{Verdict: true, Reasons: []string{}}, nil
	} else {
		logger.Debug("Validation verdict", kvp.Bool("auto-validator.validation.accepted", false), kvp.Int("auto-validator.validation.correct-votes", correctVotes), kvp.Int("auto-validator.validation.required-votes", v.config.RequiredVotes))
		return &AutoValidatorResponse{Verdict: false, Reasons: invalidReasons}, nil
	}
}
