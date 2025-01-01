package fixstate

import (
	"context"
	"regexp"
	"strings"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
)

// BaseFixState is a fix that is not based on any existing fixes.
// This FixState works with the `plain` and `reasoning` templates.
type BaseFixState struct {
	Alert alerts.Alert
	// TODO port rest from ts later
	IsFalsePositive bool
	FixDescription  string // TODO port parsing of the fix description from ts later
	// ParsedEdits is the parsed edits that the model has suggested.
	ParsedEdits []editcommands.FileEdit

	// PackagesToInstall is the list of packages that the model has suggested to install.
	PackagesToInstall []string
	// SingleFileFlowContext is a region of code that contains the alert and all the flow steps, if they are contained within a single file.
	SingleFileFlowContext *alerts.CollapsedFlowStep
	DependencyMetadata    []fixdata.DependencyMetadata
	// Transcript is the transcript of the conversation with the model.
	Transcript string
}

// NewBaseFixState constructs a BaseFixState for an alert, collapsing flow
// steps into a single context if they all reside in one file.
func NewBaseFixState(alert *alerts.Alert) (BaseFixState, autofix.AutofixError) {
	ret := BaseFixState{ //nolint:exhaustruct
		Alert: *alert,
	}
	file := alert.Location.File
	var err autofix.AutofixError
	if alert.Flow != nil && utils.Every(alert.Flow, func(f alerts.FlowStep) bool {
		return f.Location.File.Equals(file)
	}) {
		// every step along the flow, the alert-location, and the preamble.
		completeContext := alert.Context.WithExtractedPreamble().WithAddedContexts(
			utils.Map(alert.Flow, func(f alerts.FlowStep) codebase.ContextLines {
				return f.Context
			}),
		)

		var collapsedFlowStep alerts.CollapsedFlowStep
		collapsedFlowStep, err = alerts.NewCollapsedFlowStep(alert.Flow, completeContext, file)
		if err != nil {
			return ret, autofix.NewParsingError(
				"Failed to collapse flow steps",
				err)
		}
		ret.SingleFileFlowContext = &collapsedFlowStep
	}
	return ret, nil
}

// SeenFiles returns all unique files the model has seen.
func (f BaseFixState) SeenFiles() []alerts.RelativePath {
	return f.Alert.RelatedFiles
}

// ParseModelResponse parses the LLM response, extracting fix description,
// replacement blocks and dependency additions. It sets flags for false
// positives and accumulates parsed edits and packages to install.
func (f *BaseFixState) ParseModelResponse(
	ctx context.Context,
	modelResponse string,
	processReplacementBlocksSection func(ctx context.Context, content string, seenFiles []string, alert *alerts.Alert) ([]editcommands.FileEdit, error),
) autofix.AutofixError {
	ctx, span := enhancedctx.StartSpan(ctx, "fixstate.BaseFixState.ParseModelResponse")
	defer span.End()

	if ctxErr := autofix.NewErrorFromContextErr(ctx, "Context canceled while parsing model response"); ctxErr != nil {
		autofix.ReportErrorToTelemetry(ctx, ctxErr)
		return ctxErr
	}

	// Extract the part that comes before the `### Discussion` header and
	// look for an FP conclusion there. If it is a false positive, we can
	// return early and skip the rest of the parsing logic. (The model might decide to skip the remaining sections)
	discussion := ""
	discussionHeaderRegex := regexp.MustCompile(`(?is)^.*?#+\s*Discussion([\s\S]*?)(?:\n#[^\n]*)?$`)
	dMatch := discussionHeaderRegex.FindStringSubmatch(modelResponse)
	if len(dMatch) >= 2 {
		discussion = dMatch[1] // the discussion section is entirely optional
	}

	// Normalize text: lowercase, strip markdown emphasis, collapse whitespace.
	normalized := strings.ToLower(strings.TrimSpace(discussion))
	normalized = strings.ReplaceAll(normalized, "*", "")
	normalized = regexp.MustCompile(`\s+`).ReplaceAllString(normalized, " ")

	// If the model concluded the alert is a false positive, we can return early.
	if strings.Contains(normalized, "conclusion: fp") || strings.Contains(normalized, "conclusion: false positive") {
		f.IsFalsePositive = true
		f.FixDescription = "The alert is a false positive"
		f.ParsedEdits = []editcommands.FileEdit{}
		f.PackagesToInstall = []string{}
		return nil
	}

	// Break down the response into its three sections (after the FP discussion)
	fixDescription, replacementBlocks, dependenciesToAdd, getSectionsErr := getSectionsFromModelResponse(modelResponse)
	if getSectionsErr != nil {
		return getSectionsErr
	}

	// Extract the fix description: everything after `### Fix description` and
	// before `### Replacement blocks`.
	if fixDescription == "" {
		err := autofix.NewParsingError(
			"Model response missing fix description section",
			nil)
		autofix.ReportErrorToTelemetry(ctx, err)
		return err
	}
	f.FixDescription = fixDescription + "\n"

	// Process the edit commands: everything after `### Replacement blocks` and
	// before `### Dependencies to add`, or the end of the response if there are no dependencies.
	seenFilesStr := utils.Map(f.SeenFiles(), func(p alerts.RelativePath) string {
		return string(p)
	})
	parsedEdits, processReplacementErr := processReplacementBlocksSection(ctx, replacementBlocks, seenFilesStr, &f.Alert)
	if processReplacementErr != nil {
		var err autofix.AutofixError
		if autofixErr, ok := processReplacementErr.(autofix.AutofixError); ok {
			err = autofixErr.WithContext("Failed to process replacement blocks")
		} else {
			err = autofix.NewParsingError(
				"Failed to process replacement blocks",
				processReplacementErr)
		}
		autofix.ReportErrorToTelemetry(ctx, err)
		return err
	}
	f.ParsedEdits = parsedEdits

	// Process the dependencies to add: everything after `### Dependencies to add`,
	// or the empty string if there are no dependencies to add.
	packagesToInstall, err := processDependenciesToAddSection(dependenciesToAdd)
	if err != nil {
		return err
	}
	f.PackagesToInstall = packagesToInstall

	return nil
}

// getSectionsFromModelResponse parses a raw model response and extracts three
// distinct sections:
//
//  1. Fix description (natural language description of the fix)
//  2. Replacement blocks (strict format to specify code edits)
//  3. Dependencies to add (optional)
//
// The input string is expected to contain markdown with headers of the form
// “# Fix description”, “# Replacement blocks”, and “# Dependencies to add”.
func getSectionsFromModelResponse(modelResponse string) (fixDescription, replacementBlocks, dependenciesSection string, err autofix.AutofixError) {
	var ModelResponsePattern = regexp.MustCompile(`(?si)^.*?(?:#+ Fix description)(.*?)(?:#+ Replacement blocks?)(.*?)(?:#+ Dependencies to add(.*?))?$`)
	matches := ModelResponsePattern.FindAllStringSubmatch(modelResponse, -1)
	if len(matches) == 0 {
		err := autofix.NewParsingError(
			"Model response does not match expected format (missing sections)",
			nil)
		return "", "", "", err
	}
	match := matches[0]
	match = utils.Map(match, func(m string) string {
		return strings.TrimSpace(m)
	})

	fixDescription = match[1]
	replacementBlocks = match[2]
	dependenciesSection = match[3]
	return
}
