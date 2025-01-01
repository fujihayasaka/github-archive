package api

import (
	"context"

	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/prompt"
)

// SarifFixer provides a high-level API for generating fixes from SARIF files
//
// DEPRECATION NOTICE: This approach is maintained for backward compatibility.
// For new integrations, prefer using GenerateFixFrom* from suggested_fix.go directly,
// which provides a more flexible and simpler API without requiring SarifFixer initialization.
type SarifFixer struct {
	clientName     string
	config         *config.Config
	model          models.Model
	promptTemplate prompt.PromptTemplate
}

// SarifFixerInterface can be used to generate fixes from SARIF files.
type SarifFixerInterface interface {
	GenerateFix(ctx context.Context, sarifFilePath string, sourceRoot string, repoID string, fileChecksums map[string]string) (*SuggestedFix, autofix.AutofixError)
	GenerateFixesForAlerts(ctx context.Context, alerts []alerts.Alert, model models.Model) fixdata.AutofixResponse
}

// SarifFixerInterface is an interface for the SarifFixer
var _ SarifFixerInterface = (*SarifFixer)(nil)

// NewSarifFixer creates a new instance of SarifFixer
func NewSarifFixer(ctx context.Context, options *AutofixerOptions) (*SarifFixer, autofix.AutofixError) {
	if options == nil {
		options = &AutofixerOptions{ //nolint:exhaustruct
			ClientName: "unknown",
			ModelName:  ModelProd,
			DevMode:    false,
		}
	}

	// Use shared initialization logic
	cfg, model, promptTemplate, err := initializeAutofixer(ctx, options)
	if err != nil {
		return nil, err
	}

	return &SarifFixer{
		clientName:     options.ClientName,
		config:         cfg,
		model:          model,
		promptTemplate: promptTemplate,
	}, nil
}

// GenerateFix generates a fix for the given SARIF file
// It reads the SARIF file, extracts alerts, and generates a fix using the configured model.
func (s *SarifFixer) GenerateFix(ctx context.Context, sarifFilePath string, sourceRoot string, repoID string, fileChecksums map[string]string) (*SuggestedFix, autofix.AutofixError) {
	autofixer := &Autofixer{
		clientName:     s.clientName,
		modelConfig:    s.config,
		chatModel:      s.model,
		promptTemplate: s.promptTemplate,
	}

	autofixResponse, err := autofixer.GenerateFixFromSarifFile(
		ctx,
		sarifFilePath,
		sourceRoot,
		repoID,
		fileChecksums,
	)
	if err != nil {
		return nil, autofix.NewLogicError("failed to generate fix from SARIF file: " + err.Error())
	}

	return OutputToSuggestedFix(ctx, &autofixResponse[0], fileChecksums)
}

// GenerateFixesForAlerts processes each alert and generates fixes
func (s *SarifFixer) GenerateFixesForAlerts(ctx context.Context, alerts []alerts.Alert, model models.Model) fixdata.AutofixResponse {
	if model == nil {
		model = s.model
	}

	return generateFixesFromAlerts(ctx, alerts, model, s.promptTemplate)
}
