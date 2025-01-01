package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/sarif"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/sarif/v210autofix"
)

// getAlertsFromFile extracts alerts from a SARIF file
func getAlertsFromFile(ctx context.Context, sarifFilePath, sourceRoot string) ([]alerts.Alert, autofix.AutofixError) {
	clientName := enhancedctx.ClientNameFromContext(ctx)
	if clientName == "" {
		clientName = "api-client"
	}
	ctx = enhancedctx.WithClientName(ctx, clientName)

	ctx, span := enhancedctx.StartSpan(ctx, "api.getAlertsFromFile")
	defer span.End()

	if ctx.Err() != nil {
		autofixErr := autofix.NewContextCanceledError("context canceled before processing SARIF file", ctx.Err())
		autofix.ReportErrorToTelemetry(ctx, autofixErr)
		return nil, autofixErr
	}

	if sarifFilePath == "" || sourceRoot == "" {
		return nil, autofix.NewInvalidRequestError("SARIF file path and source root must be provided")
	}

	// Create config
	cfg, err := config.NewConfigBuilder().WithEnvironment().Build()
	if err != nil {
		return nil, autofix.NewLogicError("failed to create config: " + err.Error())
	}

	// Process the SARIF file to get sarifCodebase and SARIF log
	sarifCodebase, sarifLog, err := sarif.GetCodebaseAndSarifLog(ctx, sarifFilePath, sarif.Options{ //nolint:exhaustruct
		SourceRoot: sourceRoot,
	})

	if err != nil {
		if os.IsNotExist(err) {
			return nil, autofix.NewFileNotFoundError("SARIF file not found", err, sarifFilePath)
		}
		return nil, autofix.NewLogicError("failed to process SARIF file: " + err.Error())
	}

	options := sarif.Options{ //nolint:exhaustruct // No need to specify all fields
		MakeOptions: alerts.MakeOptions{}, //nolint:exhaustruct // No need to specify any fields
		SourceRoot:  sourceRoot,
	}

	alertExtractionStartTime := time.Now()
	extractedAlerts, err := sarif.ExtractSarifAlerts(ctx, sarifCodebase, sarifLog, options, *cfg)
	if err != nil {
		return nil, autofix.NewLogicError(fmt.Sprintf("failed to extract alerts: %v", err))
	}
	enhancedctx.Statter(ctx).DistributionMs("alert_extraction.duration", nil, time.Since(alertExtractionStartTime))

	return extractedAlerts, nil
}

// getAlertsFromContent extracts alerts from SARIF content
func getAlertsFromContent(ctx context.Context, sarifContent []byte, sourceFiles map[string][]byte) ([]alerts.Alert, autofix.AutofixError) {
	clientName := enhancedctx.ClientNameFromContext(ctx)
	ctx = enhancedctx.WithClientName(ctx, clientName)

	ctx, span := enhancedctx.StartSpan(ctx, "api.getAlertsFromContent")
	defer span.End()

	// Create config
	cfg, err := config.NewConfigBuilder().WithEnvironment().Build()
	if err != nil {
		return nil, autofix.NewLogicError("failed to create config: " + err.Error())
	}

	var sarifLog v210autofix.SarifLog
	if err := json.Unmarshal(sarifContent, &sarifLog); err != nil {
		return nil, autofix.NewInvalidRequestError("failed to parse SARIF content: " + err.Error())
	}

	// Creates memory codebase from source files
	memCodebase := codebase.NewMemoryCodebase(sourceFiles)

	// Set up SARIF options
	options := sarif.Options{ //nolint:exhaustruct // No need to specify all fields
		MakeOptions: alerts.MakeOptions{}, //nolint:exhaustruct // No need to specify any fields
	}

	extractedAlerts, err := sarif.ExtractSarifAlerts(ctx, memCodebase, sarifLog, options, *cfg)
	if err != nil {
		return nil, autofix.NewLogicError(fmt.Sprintf("failed to extract alerts: %v", err))
	}

	return extractedAlerts, nil
}

// validateFixParams ensures that only one input method is specified
func (a *Autofixer) validateFixParams(params *fixParams) autofix.AutofixError {
	if params == nil {
		return autofix.NewInvalidRequestError("fix parameters cannot be nil")
	}

	inputMethodCount := 0

	if len(params.alerts) > 0 {
		inputMethodCount++
	}

	if len(params.sarifContent) > 0 {
		inputMethodCount++
		// Source files are required with SARIF content
		if len(params.sourceFiles) == 0 {
			return autofix.NewInvalidRequestError("source files must be provided with SARIF content")
		}
	}

	if params.sarifFilePath != "" {
		inputMethodCount++
		// Source root is required with SARIF file path
		if params.sourceRoot == "" {
			return autofix.NewInvalidRequestError("source root must be provided with SARIF file path")
		}
	}

	if inputMethodCount == 0 {
		return autofix.NewInvalidRequestError("no input method specified: provide only one of alerts, content+files, or file path+source root")
	}

	if inputMethodCount > 1 {
		return autofix.NewInvalidRequestError("multiple input methods specified: provide only one of alerts, content+files, or file path+source root")
	}

	return nil
}

// buildFilePathHash generates a SHA-256 hash of the file path
func buildFilePathHash(path string) []byte {
	h := sha256.New()
	if _, err := h.Write([]byte(path)); err != nil {
		panic(fmt.Sprintf("failed to write file path to hash: %v", err)) // This should not happen
	}
	return h.Sum(nil)[:FilePathHashSize]
}

// calculateFileChecksum generates a consistent checksum for file content
func calculateFileChecksum(content []byte) string {
	h := sha256.New()
	if _, err := h.Write(content); err != nil {
		panic(fmt.Sprintf("failed to write file content to hash: %v", err)) // This should not happen
	}
	return fmt.Sprintf("%x", h.Sum(nil))
}

// calculateFileChecksums computes a SHA-256 checksum for the content of each file in the provided map.
// The input is a map where keys are file paths and values are file contents as byte slices.
// It returns a map where each key is a file path and the value is the corresponding checksum as a hex string.
// This function is useful for tracking file integrity or detecting changes in file content.
func calculateFileChecksums(files map[string][]byte) map[string]string {
	checksums := make(map[string]string, len(files))
	for path, content := range files {
		checksums[path] = calculateFileChecksum(content)
	}
	return checksums
}

// ensureProperDiffFormatFix ensures that all diffs in the suggested fix have the proper git diff header format
// This function checks if the diff content starts with "diff --git" and adds it if missing.
func ensureProperDiffFormat(files []*SuggestedFixFile) {
	if files == nil {
		return
	}

	for i, file := range files {
		if file.DiffContent == nil {
			// If there's no diff content, create an empty diff with proper headers
			files[i].DiffContent = []byte(fmt.Sprintf("diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n",
				file.FilePath, file.FilePath, file.FilePath, file.FilePath))
			continue
		}

		// If the diff doesn't start with "diff --git", add the proper header
		if !bytes.HasPrefix(file.DiffContent, []byte("diff --git")) {
			properDiff := fmt.Sprintf("diff --git a/%s b/%s\n%s",
				file.FilePath, file.FilePath, string(file.DiffContent))
			files[i].DiffContent = []byte(properDiff)
		}
	}
}

// OutputToSuggestedFix converts a fixdata.Output and associated file checksums into a SuggestedFix.
// This is a utility function that processes the raw output from the autofix process into a convenient
// (but lossy) format for further processing or display.
// It validates that the output is of kind FIX, maps file changes to the SuggestedFix structure,
// ensures that all diffs have the proper git diff header format, and returns the constructed SuggestedFix.
// Returns an AutofixError if the output is not a fix outcome.
func OutputToSuggestedFix(ctx context.Context, output *fixdata.Output, fileChecksums map[string]string) (*SuggestedFix, autofix.AutofixError) {
	if output.Outcome.Kind != fixdata.OutcomeKind_FIX {
		return nil, autofix.NewLogicError("output is not a fix outcome")
	}

	suggestedFix := &SuggestedFix{ //nolint:exhaustruct // No need to specify all fields
		Description:        output.Alert.Message,
		AiModel:            output.Model,
		AiVersion:          output.AutofixVersion,
		DependencyMetadata: mapDependencyMetadata(output.Outcome.Details.DependencyMetadata),
	}

	// Map file changes from the fix outcome to the suggested fix
	for _, diff := range output.Outcome.Diffs {
		checksum := fileChecksums[diff.Path]
		file := &SuggestedFixFile{
			FilePath:     diff.Path,
			DiffContent:  []byte(diff.Diff),
			FileChecksum: checksum,
			FilePathHash: buildFilePathHash(diff.Path),
		}
		suggestedFix.Files = append(suggestedFix.Files, file)
	}

	// Ensure proper diff format
	ensureProperDiffFormat(suggestedFix.Files)

	return suggestedFix, nil
}

// ExtractFilesFromOutput extracts the list of files affected by a fix from the given fixdata.Output.
// It validates that the output is of kind FIX, then iterates over the diffs in the output to construct
// a slice of SuggestedFixFile pointers. Each SuggestedFixFile contains the file path, diff content,
// file checksum (from the provided map), and a hash of the file path. After collecting all files,
// it ensures that each diff has the proper git diff header format. Returns the slice of files or an
// AutofixError if the output is not a fix outcome.
func ExtractFilesFromOutput(ctx context.Context, output *fixdata.Output, fileChecksums map[string]string) ([]*SuggestedFixFile, autofix.AutofixError) {
	if output.Outcome.Kind != fixdata.OutcomeKind_FIX {
		return nil, autofix.NewLogicError("output is not a fix outcome")
	}

	files := make([]*SuggestedFixFile, 0, len(output.Outcome.Diffs))
	for _, diff := range output.Outcome.Diffs {
		checksum := fileChecksums[diff.Path]
		file := &SuggestedFixFile{
			FilePath:     diff.Path,
			DiffContent:  []byte(diff.Diff),
			FileChecksum: checksum,
			FilePathHash: buildFilePathHash(diff.Path),
		}
		files = append(files, file)
	}

	// Post-processing to ensure all diffs have the proper git diff header format
	ensureProperDiffFormat(files)

	return files, nil
}

// ExtractAssessmentFromOutput extracts the assessment from a fixdata.Output if the output is of kind FIX.
// If the output is not a fix outcome, it returns a logic error. Otherwise, it returns a pointer to the
// Assessment contained in the output. This function is useful for retrieving the assessment result
// associated with a fix operation.
func ExtractAssessmentFromOutput(output *fixdata.Output) (*fixdata.Assessment, autofix.AutofixError) {
	if output.Outcome.Kind != fixdata.OutcomeKind_FIX {
		return nil, autofix.NewLogicError("output is not a fix outcome")
	}

	return &output.Outcome.Assessment, nil
}

// IsValidFixOutcome determines whether the provided fixdata.Output represents a valid fix outcome.
// It returns true if the output contains a fix outcome with a valid assessment, and false otherwise.
func IsValidFixOutcome(output *fixdata.Output) bool {
	outcomeIsFix := output.Outcome.Kind == fixdata.OutcomeKind_FIX
	fixAssessmentIsValid := output.Outcome.Assessment.Outcome == fixdata.AssessmentOutcome_VALID

	return outcomeIsFix && fixAssessmentIsValid
}

// processFixResult handles a fix result and produces fix as fixdata.Output
func processFixResult(ctx context.Context, fixSuggestion *fix.FixSuggestion, fixErr *fix.FixError, alert alerts.Alert, modelName string, previousAttemptsCount int) fixdata.Output {
	if fixErr != nil {
		logFixError(ctx, previousAttemptsCount, alert, fixErr)
		recordFixError(ctx, fixErr)
		return fixdata.NewAutofixOutput(autofix.CurrentVersion, modelName, alert, fixdata.NewErrorOutcome(fixErr.Err, &fixErr.Transcript))
	}

	if fixSuggestion != nil {
		telemetry := collectFixTelemetry(fixSuggestion)
		logFixSuccess(ctx, telemetry, previousAttemptsCount, alert)
		recordFixStats(ctx, telemetry)
		logFixProblems(ctx, fixSuggestion.Assessment.Problems)
		return fixSuggestion.ToOutputFormat(autofix.CurrentVersion, modelName)
	}

	enhancedctx.Logger(ctx).Error("No fix or error returned")
	enhancedctx.Statter(ctx).Counter("fix_suggestion_generation.no_result", nil, 1)

	return fixdata.NewAutofixOutput(
		autofix.CurrentVersion,
		modelName,
		alert,
		fixdata.NewErrorOutcome(autofix.NewLogicError("no fix or error returned"), nil),
	)
}

// getPreviousAttemptsFromContext extracts previous attempts from context
func getPreviousAttemptsFromContext(ctx context.Context) []fix.PreviousAttempt {
	if val := ctx.Value(PreviousAttemptsKey); val != nil {
		if prevAttempts, ok := val.([]fix.PreviousAttempt); ok {
			return prevAttempts
		}
	}
	return nil
}

func mapDependencyMetadata(dependencies []fixdata.DependencyMetadata) []SuggestedFixDependency {
	if len(dependencies) == 0 {
		return nil
	}

	result := make([]SuggestedFixDependency, len(dependencies))

	for i, dep := range dependencies {
		advisories := make([]SuggestedFixAdvisory, len(dep.Advisories))

		for j, adv := range dep.Advisories {
			advisories[j] = SuggestedFixAdvisory{
				Id:          adv.Id,
				HtmlUrl:     adv.HtmlUrl,
				Summary:     adv.Summary,
				Description: adv.Description,
				Severity:    mapSeverity(adv.Severity),
			}
		}

		result[i] = SuggestedFixDependency{
			Name:        dep.Name,
			Version:     dep.Version,
			Description: dep.Description,
			Url:         dep.Url,
			Ecosystem:   dep.Ecosystem,
			IsMalicious: dep.IsMalicious,
			Advisories:  advisories,
		}
	}

	return result
}

func mapSeverity(severity string) SuggestedFixAdvisorySeverity {
	switch severity {
	case "low":
		return SuggestedFixAdvisorySeverityLow
	case "medium":
		return SuggestedFixAdvisorySeverityMedium
	case "high":
		return SuggestedFixAdvisorySeverityHigh
	case "critical":
		return SuggestedFixAdvisorySeverityCritical
	default:
		return SuggestedFixAdvisorySeverityUnknown
	}
}
