// Package api provides functionality for generating automated fixes for code issues.
//
// USAGE:
//
//	Integrators should use the simple API helper functions:
//
// - GenerateFixFromAlerts: When you already have alert objects
// - GenerateFixFromSarifContent: When you have SARIF content as bytes
// - GenerateFixFromSarifFile: When you have SARIF data in a file
//
// These functions handle all validation and ensure proper usage.
//
// IMPORTANT: Only ONE input method can be used at a time. The system will
// return an error if multiple input methods are specified.
package api

import (
	"context"
	"crypto/sha256"
	"fmt"
	"os"
	"slices"
	"strings"
	"time"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
	toolsuites "github.com/github/codeml-autofix/go/v2/pkg/autofix/tools_suites"

	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/code-scanning-ai-libraries/v2/llm/provider"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/prompt"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
)

// ContextKey type for context values
type ContextKey string

// Constants for model names and configuration
const (
	ModelProd = "capi-prod-4.1"
	ModelDev  = "capi-dev-4.1"

	// PreviousAttemptsKey is the context key for storing previous attempts
	PreviousAttemptsKey ContextKey = "previous_attempts"

	// FilePathHashSize is the size of the SHA-256 hash used for file paths
	FilePathHashSize = sha256.Size
)

// AutofixerOptions defines the options for generating a suggested fix.
// It allows for multiple input methods, including directly provided alerts,
// SARIF content, or a SARIF file path. It also supports previous attempts,
// custom prompt templates, and configuration options.
//
// This struct is used to pass all necessary parameters for generating fixes
type AutofixerOptions struct {
	// Input methods (use one of these)
	Alerts        []alerts.Alert // Option 1: Pre-extracted alerts
	SarifContent  []byte         // Option 2: SARIF content
	SarifFilePath string         // Option 3: Path to SARIF file

	// model configuration
	ModelName   string
	ChatModel   models.Model
	ModelConfig *config.Config

	PreviousAttempts []fix.PreviousAttempt // Previous fix attempts

	RepositoryID  string // Repository ID for associating fixes for telemetry
	IntegrationID string // Integration ID for CAPI endpoints for telemetry

	DevMode bool // use development endpoints

	// GitHub token for authentication against GH REST API. This is used
	// by the dependencies adding component.
	GitHubToken string

	// Cache folder is used to store model responses and other data.
	// If a value is provided, the model will use that value as the cache directory.
	// If a value is not provided, the model will not use caching.
	Cache string

	// The query suite used to determine if an alert is autofixable, based on the query ID.
	// If this is empty, the check for whether an alert is autofixable will be skipped.
	// Admitted values are "default", "extended", "code-scanning", "ccr".
	// When passed any of these values, the autofix system will check if the alert's query ID
	// is included in the query suite.
	QuerySuite string

	// For SARIF file path
	SourceRoot string // Source root directory
	// Client name for telemetry and logging
	// Required for telemetry. Examples: "code-review"
	ClientName string
	// For SARIF content
	SourceFiles    map[string][]byte     // Source file contents (required when using SARIF Content)
	FileChecksums  map[string]string     // File checksums (optional, will be calculated from SourceFiles if not provided)
	promptTemplate prompt.PromptTemplate // Prompt template to use for generating fixes, e.g: "plain", "reasoning".
	// Path to mock model conversation log (for testing)
	MockModelPath string
	// Whether to enable regex matching for mock model (for testing)
	MockModelEnableRegexMatching bool
}

// Autofixer provides a high-level API for generating fixes from SARIF files, contents
// and alerts. It encapsulates the model, configuration, and prompt template
// to generate fixes based on the provided options.
type Autofixer struct {
	clientName     string
	modelConfig    *config.Config
	chatModel      models.Model
	promptTemplate prompt.PromptTemplate
	querySuite     string
	// GitHub token for authentication against GH REST API.
	// Used by the dependencies adding component in order to check
	// if a dependency generated is malicious before presenting a fix.
	githubToken string
}

// NewAutofixer creates a new Autofixer instance with the provided options.
func NewAutofixer(ctx context.Context, options *AutofixerOptions) (*Autofixer, autofix.AutofixError) {
	cfg, model, promptTemplate, err := initializeAutofixer(ctx, options)
	if err != nil {
		return nil, err
	}

	return &Autofixer{
		clientName:     options.ClientName,
		modelConfig:    cfg,
		chatModel:      model,
		promptTemplate: promptTemplate,
		querySuite:     cfg.QuerySuite,
		githubToken:    options.GitHubToken,
	}, nil
}

// initializeAutofixer contains the common logic for initializing an Autofixer
// This is used by both NewAutofixer and NewSarifFixer to avoid code duplication
// NewSarifFixer will be deprecated in the future.
func initializeAutofixer(
	ctx context.Context,
	options *AutofixerOptions,
) (*config.Config, models.Model, prompt.PromptTemplate, autofix.AutofixError) {
	if options == nil {
		return nil, nil, "", autofix.NewInvalidRequestError("autofix options cannot be nil")
	}

	if options.ClientName == "" {
		return nil, nil, "", autofix.NewInvalidRequestError("importing service name is required for telemetry and cannot be empty")
	}

	if options.ModelName == "" {
		options.ModelName = ModelProd // Default to production model
		enhancedctx.Logger(ctx).Info("Using default model name", kvp.String("model_name", options.ModelName))
	}

	// Handle mock model environment setup
	if options.MockModelPath != "" {
		os.Setenv("MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH", options.MockModelPath)
		os.Setenv("CAPI_DEV_KEY", "mock-key-for-testing")

		if options.MockModelEnableRegexMatching {
			os.Setenv("MOCK_MODEL_ENABLE_REGEX", "true")
		}
	}

	// Build config
	var cfg *config.Config
	var err autofix.AutofixError

	if options.ModelConfig != nil {
		cfg = options.ModelConfig
	} else {
		// Create API keys map for config builder
		apiKeys := map[string]string{
			"CAPI_DEV_KEY":  "",
			"CAPI_PROD_KEY": "",
		}

		// Build a new config
		cfg, err = BuildConfig(
			options.DevMode,
			options.IntegrationID,
			options.MockModelPath,
			apiKeys,
		)

		if err != nil {
			autofix.ReportErrorToTelemetry(ctx, err)
			return nil, nil, "", err.WithContext("failed to build config")
		}
	}

	// Initialize model
	var model models.Model
	if options.ChatModel != nil {
		model = options.ChatModel
	} else {
		model, err = InitializeModelForOptions(
			ctx,
			options.ModelName,
			options.MockModelPath,
			options.MockModelEnableRegexMatching,
			cfg,
		)

		if err != nil {
			autofix.ReportErrorToTelemetry(ctx, err)
			return nil, nil, "", err.WithContext("failed to initialize model")
		}
	}

	// Enable use of caching if specified
	if options.Cache != "" {
		model = provider.NewCachingModelFromPath(model, options.Cache)
	}

	if options.QuerySuite != "" {
		// Validate the query suite
		validQuerySuites := []string{"default", "extended", "code-scanning", "ccr"}
		if !slices.Contains(validQuerySuites, options.QuerySuite) {
			return nil, nil, "", autofix.NewInvalidRequestError(fmt.Sprintf("invalid query suite: %s, must be one of %v", options.QuerySuite, validQuerySuites))
		}
	}
	cfg.QuerySuite = options.QuerySuite

	// Set prompt template with fallback to default
	promptTemplate := options.promptTemplate
	if promptTemplate == "" {
		promptTemplate = prompt.PromptTemplatePlain
	}

	return cfg, model, promptTemplate, nil
}

// generateFixesFromAlerts processes each alert and generates fixes
func generateFixesFromAlerts(ctx context.Context, allAlerts []alerts.Alert, model models.Model, promptTemplate prompt.PromptTemplate) fixdata.AutofixResponse {
	var response fixdata.AutofixResponse
	startTime := time.Now()
	modelName := models.GetPrettyModelName(model)

	previousAttempts := getPreviousAttemptsFromContext(ctx)
	previousAttemptsCount := len(previousAttempts)

	for i := 0; i < len(allAlerts); i++ {
		alert := allAlerts[i]
		fixStart := time.Now()
		fixSuggestion, fixErr := fix.FixAlert(ctx, alert, model, promptTemplate, previousAttempts)
		recordFixDuration(ctx, time.Since(fixStart), fixErr != nil)

		output := processFixResult(ctx, fixSuggestion, fixErr, alert, modelName, previousAttemptsCount)

		response = append(response, output)
	}

	recordTotalDuration(ctx, time.Since(startTime))
	return response
}

// fixParams contains just the parameters needed for generating a fix
type fixParams struct {
	// Input methods (only one should be set)
	alerts        []alerts.Alert
	sarifContent  []byte
	sarifFilePath string

	// Context information
	sourceRoot       string
	sourceFiles      map[string][]byte
	fileChecksums    map[string]string
	repositoryID     string
	previousAttempts []fix.PreviousAttempt
}

// generateFix generates a suggested fix based on the provided parameters.
// It validates the input, extracts alerts from the specified method,
// and generates fixes using the configured model and prompt template.
func (a *Autofixer) generateFix(
	ctx context.Context,
	params *fixParams,
) (response fixdata.AutofixResponse, autofixError autofix.AutofixError) {
	ctx = enhancedctx.StartInteraction(ctx)
	ctx = enhancedctx.WithClientName(ctx, a.clientName)

	ctx, span := enhancedctx.StartSpan(ctx, "api.Autofixer.generateFix")
	defer span.End()

	if autofixError = autofix.NewErrorFromContextErr(ctx, "context cancelled before processing"); autofixError != nil {
		return response, autofixError
	}

	requestStartTime := time.Now()
	defer finishGenerateFix(ctx, &response, autofixError, requestStartTime)

	// Validate input parameters to ensure only one input method is used
	if autofixError = a.validateFixParams(params); autofixError != nil {
		return response, autofixError
	}

	// Apply previous attempts via context if provided
	requestCtx := ctx
	if len(params.previousAttempts) > 0 {
		requestCtx = context.WithValue(ctx, PreviousAttemptsKey, params.previousAttempts)
	}

	// Pass on the query suite the client has been initialised with along with the context.
	requestCtx = context.WithValue(requestCtx, toolsuites.QuerySuiteKey, a.querySuite)

	// Also thread in the request the GitHub Token passed from our client
	requestCtx = context.WithValue(requestCtx, config.GitHubTokenKey, a.githubToken)

	// Extract alerts using the appropriate provided input options
	var extractedAlerts []alerts.Alert
	var alertsToFix []alerts.Alert

	switch {
	case len(params.alerts) > 0:
		// Option 1: Use pre-extracted alerts
		alertsToFix = params.alerts
		enhancedctx.Logger(ctx).Info("Using directly provided alerts",
			kvp.Int("gh.autofix.alert_count", len(alertsToFix)))

	case len(params.sarifContent) > 0:
		// Option 2: Extract alerts from SARIF content
		extractedAlerts, autofixError = getAlertsFromContent(ctx, params.sarifContent, params.sourceFiles)
		if autofixError != nil {
			return response, autofixError
		}
		alertsToFix = extractedAlerts

	case params.sarifFilePath != "":
		// Option 3: Extract alerts from SARIF file
		extractedAlerts, autofixError = getAlertsFromFile(ctx, params.sarifFilePath, params.sourceRoot)
		if autofixError != nil {
			return response, autofixError
		}
		alertsToFix = extractedAlerts
	}

	// The API requires exactly one alert to generate a fix.
	if len(alertsToFix) != 1 {
		autofixError = autofix.NewNotAutofixableError(fmt.Sprintf("expected exactly one alert, got %d", len(alertsToFix)))
		response = nil
		return response, autofixError
	}

	// Generate fixes using the already initialized model and prompt template
	response = generateFixesFromAlerts(requestCtx, alertsToFix, a.chatModel, a.promptTemplate)

	if len(response) == 0 {
		autofixError = autofix.NewLogicError("empty autofix response")
		response = nil
		return response, autofixError
	}

	return response, nil
}

// GenerateFixFromAlerts generates fixes from pre-extracted alerts.
func (a *Autofixer) GenerateFixFromAlerts(
	ctx context.Context,
	alerts []alerts.Alert,
	sourceFiles map[string][]byte,
	repositoryID string,
) (fixdata.AutofixResponse, autofix.AutofixError) {
	ctx = enhancedctx.StartInteraction(ctx)
	ctx = enhancedctx.WithClientName(ctx, a.clientName)

	enhancedctx.Logger(ctx).Info("Generating fix from alerts",
		kvp.Int("gh.autofix.alert_count", len(alerts)))

	params := &fixParams{ //nolint:exhaustruct // No need to specify all fields
		alerts:       alerts,
		sourceFiles:  sourceFiles,
		repositoryID: repositoryID,
	}
	return a.generateFix(ctx, params)
}

// GenerateSuggestedFixFromAlerts generates a suggested fix from a slice of pre-extracted alerts.
//
// This method takes a context, a slice of alerts, a map of source file contents, and a repository ID.
// It validates the input, generates fixes for the provided alerts, and returns the first suggested fix
// as a SuggestedFix object. The function also calculates file checksums for the provided source files
// to include in the SuggestedFix.
//
// Parameters:
//   - ctx: The context for controlling cancellation and deadlines.
//   - alerts: A slice of alerts.Alert objects representing code issues to fix. Must contain exactly one alert.
//   - sourceFiles: A map of file paths to their contents, used for fix generation and checksum calculation.
//   - repositoryID: The repository identifier for associating the fix.
//
// Returns:
//   - *SuggestedFix: The generated suggested fix for the first alert.
//   - autofix.AutofixError: An error object if the operation fails.
//
// Errors:
//   - Returns an error if fix generation fails or if the response is empty.
func (a *Autofixer) GenerateSuggestedFixFromAlerts(
	ctx context.Context,
	alerts []alerts.Alert,
	sourceFiles map[string][]byte,
	repositoryID string,
) (*SuggestedFix, autofix.AutofixError) {
	res, err := a.GenerateFixFromAlerts(ctx, alerts, sourceFiles, repositoryID)
	if err != nil {
		return nil, err
	}
	if len(res) == 0 {
		return nil, autofix.NewLogicError("empty autofix response")
	}

	// Get first response as the fix
	output := res[0]

	checkSums := calculateFileChecksums(sourceFiles)

	return OutputToSuggestedFix(ctx, &output, checkSums)
}

// GenerateFixFromSarifContent is a helper function to generate fixes from SARIF content.
func (a *Autofixer) GenerateFixFromSarifContent(
	ctx context.Context,
	content []byte,
	sourceFiles map[string][]byte,
	repositoryID string,
) (fixdata.AutofixResponse, autofix.AutofixError) {
	ctx = enhancedctx.WithClientName(ctx, a.clientName)
	enhancedctx.Logger(ctx).Info("Generating fix from alerts")

	if len(content) == 0 {
		return nil, autofix.NewInvalidRequestError("SARIF content cannot be empty")
	}

	if sourceFiles == nil {
		return nil, autofix.NewInvalidRequestError("source files map cannot be nil")
	}

	params := &fixParams{ //nolint:exhaustruct // No need to specify all fields
		sarifContent: content,
		sourceFiles:  sourceFiles,
		repositoryID: repositoryID,
	}
	return a.generateFix(ctx, params)
}

// GenerateSuggestedFixFromSarifContent generates a suggested fix from SARIF content.
//
// This method takes a context, SARIF content as a byte slice, a map of source file contents,
// and a repository ID. It validates the input, generates fixes for the alerts found in the SARIF content,
// and returns the first suggested fix as a SuggestedFix object. The function also calculates file checksums
// for the provided source files to include in the SuggestedFix.
//
// Parameters:
//   - ctx: The context for controlling cancellation and deadlines.
//   - content: The SARIF content as a byte slice, containing code analysis results.
//   - sourceFiles: A map of file paths to their contents, used for fix generation and checksum calculation.
//   - repositoryID: The repository identifier for associating the fix.
//
// Returns:
//   - *SuggestedFix: The generated suggested fix for the first alert found in the SARIF content.
//   - autofix.AutofixError: An error object if the operation fails.
//
// Errors:
//   - Returns an error if fix generation fails or if the response is empty.
//   - Returns an error if the SARIF content does not contain exactly one alert.
func (a *Autofixer) GenerateSuggestedFixFromSarifContent(
	ctx context.Context,
	content []byte,
	sourceFiles map[string][]byte,
	repositoryID string,
) (*SuggestedFix, autofix.AutofixError) {
	res, err := a.GenerateFixFromSarifContent(ctx, content, sourceFiles, repositoryID)
	if err != nil {
		return nil, err
	}
	if len(res) == 0 {
		return nil, autofix.NewLogicError("empty autofix response")
	}

	// Get first response as the fix
	output := res[0]

	checkSums := calculateFileChecksums(sourceFiles)

	return OutputToSuggestedFix(ctx, &output, checkSums)
}

// GenerateFixFromSarifFile is a helper function to generate fixes from a SARIF file.
func (a *Autofixer) GenerateFixFromSarifFile(
	ctx context.Context,
	sarifFilePath string,
	sourceRoot string,
	repositoryID string,
	fileChecksums map[string]string,
) (fixdata.AutofixResponse, autofix.AutofixError) {
	ctx = enhancedctx.StartInteraction(ctx)
	ctx = enhancedctx.WithClientName(ctx, a.clientName)

	enhancedctx.Logger(ctx).Info("Generating fix from alerts",
		kvp.String("gh.autofix.sarif_path", sarifFilePath))

	params := &fixParams{ //nolint:exhaustruct // No need to specify all fields
		sarifFilePath: sarifFilePath,
		sourceRoot:    sourceRoot,
		fileChecksums: fileChecksums,
		repositoryID:  repositoryID,
	}
	return a.generateFix(ctx, params)
}

// GenerateSuggestedFixFromSarifFile generates a suggested fix from a SARIF file.
//
// This method takes a context, the path to a SARIF file, the source root directory,
// a repository ID, and a map of file checksums. It generates fixes for the alerts
// found in the SARIF file and returns the first suggested fix as a SuggestedFix object.
//
// Parameters:
//   - ctx: The context for controlling cancellation and deadlines.
//   - sarifFilePath: The file path to the SARIF file containing code analysis results.
//   - sourceRoot: The root directory of the source code, used for resolving file paths.
//   - repositoryID: The repository identifier for associating the fix.
//   - fileChecksums: A map of file paths to their checksums, used for integrity verification.
//     The checksums are supposed to be SHA-256 hashes of the file contents.
//
// Returns:
//   - *SuggestedFix: The generated suggested fix for the first alert found in the SARIF file.
//   - autofix.AutofixError: An error object if the operation fails.
//
// Errors:
//   - Returns an error if fix generation fails or if the response is empty.
//   - Returns an error if the SARIF file does not contain exactly one alert.
func (a *Autofixer) GenerateSuggestedFixFromSarifFile(
	ctx context.Context,
	sarifFilePath string,
	sourceRoot string,
	repositoryID string,
	fileChecksums map[string]string,
) (*SuggestedFix, autofix.AutofixError) {
	res, err := a.GenerateFixFromSarifFile(ctx, sarifFilePath, sourceRoot, repositoryID, fileChecksums)
	if err != nil {
		return nil, err
	}
	if len(res) == 0 {
		return nil, autofix.NewLogicError("empty autofix response")
	}
	// Get first response as the fix
	output := res[0]
	checkSums := fileChecksums

	return OutputToSuggestedFix(ctx, &output, checkSums)
}

// BuildConfig builds a configuration object based on the provided parameters.
// It sets up the environment, development mode, root path, integration ID,
// mock model path, and API keys as needed.
func BuildConfig(
	devMode bool,
	integrationID string,
	mockModelPath string,
	apiKeys map[string]string,
) (*config.Config, autofix.AutofixError) {
	configBuilder := config.NewConfigBuilder().
		WithEnvironment()

	// Build initial config
	cfg, err := configBuilder.Build()
	if err != nil {
		return nil, autofix.NewInvalidRequestError("failed to build config: " + err.Error())
	}

	if mockModelPath != "" {
		cfg.MockModelConversationLogPath = mockModelPath
	}

	if integrationID != "" {
		if devMode {
			cfg.CAPIIntegrationIDDev = integrationID
		} else {
			cfg.CAPIIntegrationID = integrationID
		}
	}

	if apiKeys != nil {
		if key, ok := apiKeys["CAPI_DEV_KEY"]; ok && key != "" {
			cfg.CAPIDevKey = key
		}
		if key, ok := apiKeys["CAPI_PROD_KEY"]; ok && key != "" {
			cfg.CAPIProdKey = key
		}
	}

	return cfg, nil
}

// InitializeModelForOptions initializes a model based on the provided options.
func InitializeModelForOptions(ctx context.Context, modelName string, mockModelPath string, enableRegexMatching bool, cfg *config.Config) (models.Model, autofix.AutofixError) {
	// Handle mock models
	pathToUse := mockModelPath

	if pathToUse == "" && cfg != nil && cfg.MockModelConversationLogPath != "" {
		pathToUse = cfg.MockModelConversationLogPath
	}

	if pathToUse == "" {
		pathToUse = os.Getenv("MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH")
	}

	// If we have a path and a mock model name, use the mock path for tests
	if pathToUse != "" && strings.HasPrefix(strings.ToLower(modelName), "mock") {
		mockModel, err := provider.NewMockModelFromConversationFile(
			pathToUse,
			"gpt-4o",
			models.MkDefaultCompletionOptions(),
		)

		if err != nil {
			return nil, autofix.NewLogicError(fmt.Sprintf("failed to initialize mock model: %v", err))
		}

		if enableRegexMatching || os.Getenv("MOCK_MODEL_ENABLE_REGEX") == "true" {
			mockModel.EnableRegexMatching()
		}

		return mockModel, nil
	}

	enhancedctx.Logger(ctx).Info("Using model from registry",
		kvp.String("gh.autofix.model_name", modelName))

	modelConfig := cfg.ToModelConfig()
	model, err := utils.CreatePrevalidatingModel(ctx, modelName, &modelConfig)
	if err != nil {
		return nil, autofix.NewLogicError(fmt.Sprintf("failed to get model: %v", err))
	}

	return model, nil
}

// Finishes the generateFix operation by logging the result.
func finishGenerateFix(ctx context.Context, response *fixdata.AutofixResponse, autofixError autofix.AutofixError, requestStartTime time.Time) {
	if autofixError != nil {
		if autofixError.Type() == autofix.ErrorTypeContextCanceled {
			enhancedctx.Statter(ctx).Counter("request_cancelled", stats.Tags{}, 1)
			return
		}
		logResult(ctx, autofixError, requestStartTime)

		// At this point,response is nil, so return early
		return
	}

	// We should have exactly one response, but if we are recovering from a panic
	// then response may be empty.
	if response == nil || len(*response) == 0 {
		enhancedctx.Logger(ctx).Error("generateFix returned an empty response",
			kvp.String("gh.autofix.error", "empty response"))
		return
	}
	logResult(ctx, (*response)[0].Outcome.AutofixError, requestStartTime)
}

func logResult(ctx context.Context, autofixError autofix.AutofixError, requestStartTime time.Time) {
	success := autofixError == nil
	tags := stats.Tags{
		"success": fmt.Sprintf("%t", success),
	}
	if !success {
		tags["error_type"] = autofixError.Type()
	}
	enhancedctx.Statter(ctx).Counter("request", tags, 1)
	enhancedctx.Statter(ctx).DistributionMs("request.duration", tags, time.Since(requestStartTime))
}
