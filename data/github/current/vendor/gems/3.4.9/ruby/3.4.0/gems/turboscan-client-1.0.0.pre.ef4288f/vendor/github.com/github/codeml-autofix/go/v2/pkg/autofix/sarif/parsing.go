// Package sarif provides utilities for working with SARIF (Static Analysis Results Interchange Format) files.
package sarif

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/contextsset"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/prompt"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/sarif/v210autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/github/github-telemetry-go/kvp"

	tools "github.com/github/codeml-autofix/go/v2/pkg/autofix/tools_suites"
)

const (
	// CopilotCodeReviewsRuleID is the rule ID used for Copilot Code Reviews.
	CopilotCodeReviewsRuleID = "ccr/generic-alert"
)

// Options holds configuration options for processing SARIF files.
type Options struct {
	// MakeOptions holds configuration options for creating alerts.
	MakeOptions alerts.MakeOptions
	// SkipFiles is a list of file paths to be excluded from processing.
	SkipFiles []string
	// SourceRoot is the root directory of the source code being analyzed.
	SourceRoot string
	// OnlyAlertNumber specifies the index of a particular alert to process. Zero-based.
	//
	// TODO: set a better zero value for this field, as currently when this field is not
	// initialized, we will only extract the first alert.
	OnlyAlertNumber int
}

func parseSarif(ctx context.Context, sarifReader io.Reader) (v210autofix.SarifLog, error) {
	byteValue, err := io.ReadAll(sarifReader)
	if err != nil {
		return v210autofix.SarifLog{}, st.EnsureStackTrace(err, "error reading SARIF")
	}

	var sarifLog v210autofix.SarifLog
	if err := json.Unmarshal(byteValue, &sarifLog); err != nil {
		return v210autofix.SarifLog{}, st.EnsureStackTrace(err, "error unmarshalling SARIF")
	}
	enhancedctx.Logger(ctx).Info("Successfully parsed SARIF")
	return sarifLog, nil
}

func readSarifFile(ctx context.Context, sarifFilePath string, options Options) (v210autofix.SarifLog, error) {
	if _, err := os.Stat(sarifFilePath); os.IsNotExist(err) {
		return v210autofix.SarifLog{}, errors.Errorf("SARIF file not found: %s", sarifFilePath)
	}

	sarifReader, err := os.Open(sarifFilePath)
	if err != nil {
		return v210autofix.SarifLog{}, st.EnsureStackTracef(err, "error opening SARIF file %s", sarifFilePath)
	}
	defer sarifReader.Close()

	sarif, err := parseSarif(ctx, sarifReader)
	if err != nil {
		return v210autofix.SarifLog{}, st.EnsureStackTracef(err, "error parsing SARIF file %s", sarifFilePath)
	}

	totalNumResults := 0

	// Remove alerts in files that should be skipped
	if len(options.SkipFiles) > 0 {
		for i := range sarif.Runs {
			var filteredResults []*v210autofix.Result
		resultsLoop:
			for _, result := range sarif.Runs[i].Results {
				if len(result.Locations) == 0 || result.Locations[0].PhysicalLocation == nil ||
					result.Locations[0].PhysicalLocation.ArtifactLocation == nil {
					enhancedctx.Logger(ctx).Info("Skipping alert with no location", kvp.String("gh.autofix.sarif_path", sarifFilePath))
					continue resultsLoop
				}

				uri := result.Locations[0].PhysicalLocation.ArtifactLocation.Uri
				// Assumes the URI is relative to the source root
				file := filepath.Join(options.SourceRoot, uri)
				for _, skipFile := range options.SkipFiles {
					if file == skipFile {
						enhancedctx.Logger(ctx).Info("Skipping alert in file", kvp.String("gh.autofix.skip_file", file))
						continue resultsLoop
					}
				}
				filteredResults = append(filteredResults, result)
				totalNumResults++
			}
			sarif.Runs[i].Results = filteredResults
		}
	}
	enhancedctx.Logger(ctx).Info(
		"Successfully read and filtered SARIF file",
		kvp.String("gh.autofix.sarif_path", sarifFilePath),
		kvp.Int("gh.autofix.num_alerts", totalNumResults),
	)
	return sarif, nil
}

// GetCodebaseAndSarifLog reads a SARIF file and returns a codebase and the SARIF log.
func GetCodebaseAndSarifLog(ctx context.Context, sarifFile string, options Options) (codebase.VirtualCodebase, v210autofix.SarifLog, error) {
	sarif, err := readSarifFile(ctx, sarifFile, options)
	if err != nil {
		return nil, v210autofix.SarifLog{}, err
	}

	var code codebase.VirtualCodebase
	if options.SourceRoot == "" {
		enhancedctx.Logger(ctx).Info("Creating SarifArtifactsAsCodebase")
		code = codebase.NewSarifArtifactsAsCodebase(sarifFile, sarif)
	} else {
		sourceRoot := options.SourceRoot
		if stat, err := os.Stat(sourceRoot); err != nil || !stat.IsDir() {
			return nil, v210autofix.SarifLog{}, errors.Errorf("not a directory: %s", sourceRoot)
		}
		enhancedctx.Logger(ctx).Info("Creating LocalCodebase for source root", kvp.String("gh.autofix.source_root", sourceRoot))
		code, err = codebase.NewLocalCodebase(sourceRoot)
		if err != nil {
			return nil, v210autofix.SarifLog{}, st.EnsureStackTrace(err, "error creating LocalCodebase")
		}
	}

	return code, sarif, nil
}

// ExtractSarifAlerts extracts alerts from a SARIF log and returns them as a slice of alerts.Alert.
func ExtractSarifAlerts(ctx context.Context, code codebase.VirtualCodebase, log v210autofix.SarifLog, options Options, config config.Config) ([]alerts.Alert, error) {
	var sarifAlerts []alerts.Alert
	type resultWithTool struct {
		Result v210autofix.Result
		Tool   v210autofix.Tool
	}
	var resultsToExtract []resultWithTool
	for _, run := range log.Runs {
		for _, result := range run.Results {
			resultsToExtract = append(resultsToExtract, resultWithTool{Result: *result, Tool: *run.Tool})
		}
	}
	if options.OnlyAlertNumber > -1 && options.OnlyAlertNumber < len(resultsToExtract) {
		enhancedctx.Logger(ctx).Info("OnlyAlertNumber was specified, so only extracting the specified alert", kvp.Int("gh.autofix.alert_number", options.OnlyAlertNumber))
		resultsToExtract = resultsToExtract[options.OnlyAlertNumber : options.OnlyAlertNumber+1]
	} else if options.OnlyAlertNumber != -1 {
		return nil, autofix.NewInvalidRequestError(fmt.Sprintf("Alert number %d out of range, %d alerts found total. Alert number is zero-indexed.", options.OnlyAlertNumber, len(resultsToExtract)))
	}
	for i := 0; i < len(resultsToExtract); i++ {
		result := resultsToExtract[i]
		alert, err := sarifResultToAlert(ctx, code, result.Result, result.Tool, options.MakeOptions)
		if err != nil {
			return nil, st.EnsureStackTrace(err, "error converting SARIF result to alert")
		}
		enhancedctx.Logger(ctx).Info("Extracted alert")
		sarifAlerts = append(sarifAlerts, alert)
	}
	return sarifAlerts, nil
}

func sarifResultToAlert(ctx context.Context, code codebase.VirtualCodebase, result v210autofix.Result, tool v210autofix.Tool, options alerts.MakeOptions) (alerts.Alert, error) { //nolint:maintidx // Consider refactoring this function to reduce its complexity.
	enhancedctx.Logger(ctx).Info("Converting SARIF result to alert")

	message := result.Message
	ruleID := result.RuleId
	ruleIndex := result.RuleIndex
	if ruleIndex == -1 && result.Rule != nil {
		ruleIndex = result.Rule.Index
	}

	if result.Rule != nil && ruleIndex == 0 && ruleIndex != result.Rule.Index {
		// ruleIndex was omitted but rule.index was provided. Use the latter.
		ruleIndex = result.Rule.Index
	}

	if ruleID == "" && ruleIndex == -1 && (result.Rule == nil || result.Rule.Index == -1) {
		return alerts.Alert{}, autofix.NewInvalidRequestError("need at least one of ruleId, ruleIndex, or rule.index to look up rule metadata")
	}

	// `run.tool.driver`` is the tool that generated the alert
	if tool.Driver == nil {
		return alerts.Alert{}, autofix.NewInvalidRequestError("missing tool driver")
	}

	// The rule metadata can be found in a toolComponent, either `run.tool.driver` or one of the entries in `run.tool.extensions`.
	var toolComponentForRule *v210autofix.ToolComponent
	// If `result.rule.toolComponent` is defined, then the rule metadata is defined in an extension
	if result.Rule != nil && result.Rule.ToolComponent != nil {
		var ruleToolComponentIndex = result.Rule.ToolComponent.Index
		if tool.Extensions == nil {
			return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("rule references tool component at index %d but tool has no extensions: %v", ruleToolComponentIndex, tool))
		}
		if ruleToolComponentIndex < 0 || ruleToolComponentIndex >= len(tool.Extensions) {
			return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("tool component index %d out of range [0, %d)", ruleToolComponentIndex, len(tool.Extensions)))
		}
		toolComponentForRule = tool.Extensions[ruleToolComponentIndex]
	} else {
		// If `result.rule.toolComponent` is not defined, then the rule metadata is defined in the driver
		toolComponentForRule = tool.Driver
	}

	if toolComponentForRule == nil {
		return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("missing tool component defining rule %v", result.Rule))
	}

	alertTool := tools.Tool(tool.Driver.Name)
	// If the driver name isn't one of the supported tools, throw an error
	if !tools.IsSupported(alertTool) {
		return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("unsupported tool: %s", alertTool))
	}

	// If we're not in dev mode and the driver name isn't one of the enabled tools, throw an error
	if !options.DevMode && !tools.IsEnabled(alertTool) {
		return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("tool not enabled: %s", alertTool))
	}

	if toolComponentForRule.Rules == nil {
		return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("missing rules metadata: %v", toolComponentForRule))
	}

	var rule *v210autofix.ReportingDescriptor
	switch {
	case ruleIndex == -1:
		// If the rule index is missing, look it up by rule ID in the tool component
		ruleMap, err := buildRuleMap(toolComponentForRule)
		if err != nil {
			return alerts.Alert{}, err.WithContext("error building rule map")
		}
		rule = ruleMap[ruleID]
	case ruleIndex >= 0 && ruleIndex < len(toolComponentForRule.Rules):
		rule = toolComponentForRule.Rules[ruleIndex]
	default:
		return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("rule index %d out of range [0, %d)", ruleIndex, len(toolComponentForRule.Rules)))
	}

	if rule == nil {
		return alerts.Alert{}, autofix.NewInvalidRequestError("missing rule")
	}

	if rule.Id != "" && ruleID == "" {
		// This means the SARIF defined `rule` but not the legacy field `ruleId`.
		// This is permitted; the `rule` wins.
		ruleID = rule.Id
	}

	// At this point both ID values should match.
	if rule.Id != ruleID {
		return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("rule ID mismatch: %s !== %s", rule.Id, ruleID))
	}

	if rule.ShortDescription == nil {
		return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("missing rule short description: %v", rule))
	}

	var primaryAlertLocation *v210autofix.PhysicalLocation

	if len(result.Locations) != 0 {
		primaryAlertLocation = result.Locations[0].PhysicalLocation
	}

	if primaryAlertLocation == nil {
		return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("missing primary location: %v", result))
	}

	contextLines, location, err := extractAlertLocations(code, *primaryAlertLocation)
	if location == nil { // this is expected if the file doesn't exist, which is an expected case
		return alerts.Alert{}, autofix.NewInvalidRequestError(fmt.Sprintf("missing file for alert: %v", primaryAlertLocation))
	}
	if err != nil { // unexpected error happened.
		return alerts.Alert{}, st.EnsureStackTracef(err, "error extracting alert %v", primaryAlertLocation)
	}

	if message == nil {
		return alerts.Alert{}, autofix.NewParsingError("missing message in result",
			errors.New("null message in SARIF"))
	}

	messageText, links, err := processMessage(ctx, *message, code, result, *primaryAlertLocation)
	if err != nil {
		return alerts.Alert{}, st.EnsureStackTrace(err, "error processing message")
	}

	var flow []alerts.FlowStep
	if len(result.CodeFlows) > 0 && len(result.CodeFlows[0].ThreadFlows) > 0 {
		flow = []alerts.FlowStep{}
		steps := result.CodeFlows[0].ThreadFlows[0].Locations
		for _, step := range steps {
			physicalLocation := step.Location.PhysicalLocation
			if physicalLocation == nil {
				return alerts.Alert{}, errors.Errorf("missing flow location: %v", step)
			}
			stepContext, location, err := extractAlertLocations(code, *physicalLocation)

			// always silently skip a flow-step, it's assumed that the missing steps are in library code, and are not needed to understand the alert.
			if err != nil || location == nil {
				continue
			}
			if step.Location != nil && step.Location.Message != nil && step.Location.Message.Text != "" {
				message := step.Location.Message.Text
				flow = append(flow, alerts.FlowStep{Context: stepContext, Location: *location, Message: message})
			}
		}
	}

	var help string
	if rule.Help != nil {
		help = rule.Help.Markdown
	}

	// Check for qhelp overrides
	// Most qhelp is embedded directly in turboscan. However, the prompt-templates/qhelps directory
	// contains custom overrides for specific rules.
	// It is not a failure if we don't find a custom help file, we just use the default help text from turboscan.

	// CCR currently pretends to be CodeQL, so check the rule ID too.
	if alertTool == tools.ToolCodeQL && ruleID != CopilotCodeReviewsRuleID {
		// Replace help text with custom help file, if it exists.
		customQHelp := prompt.FindQHelpOverride(ruleID)
		if customQHelp != "" {
			help = customQHelp
			enhancedctx.Logger(ctx).Info("Using custom help file", kvp.String("gh.autofix.custom_help_file", ruleID))
		} else {
			enhancedctx.Logger(ctx).Info("Didn't find custom help file", kvp.String("gh.autofix.custom_help_file", ruleID))
		}
	} else {
		enhancedctx.Logger(ctx).Info("Not using custom help file", kvp.String("gh.autofix.rule_id", ruleID))
	}

	// Remove `# References` section, if present.
	if help != "" {
		re := regexp.MustCompile(`\n#+ References\n[\s\S]*$`)
		help = re.ReplaceAllString(help, "")
	}

	// TODO Make sure the rule is fully populated, or use a default value.
	// The FullDescription missing was observed in the CI checks.
	if rule.FullDescription == nil {
		rule.FullDescription = &v210autofix.MultiformatMessageString{
			Markdown: "",
			Text:     "",
		}
	}

	return alerts.NewAlert(
		ctx,
		result.Guid,
		messageText,
		links,
		alerts.Rule{ID: ruleID, ShortDescription: rule.ShortDescription.Text, FullDescription: rule.FullDescription.Text, Documentation: help},
		alertTool,
		options,
		contextLines,
		*location,
		flow,
	)
}

func buildRuleMap(toolComponent *v210autofix.ToolComponent) (map[string]*v210autofix.ReportingDescriptor, autofix.AutofixError) {
	ruleMap := make(map[string]*v210autofix.ReportingDescriptor)
	if toolComponent.Rules != nil {
		for _, rule := range toolComponent.Rules {
			if rule.Id != "" {
				// Check for duplicate rule IDs
				if _, exists := ruleMap[rule.Id]; exists {
					return nil, autofix.NewInvalidRequestError(fmt.Sprintf("duplicate rule ID: Rule ID %s is defined more than once in the SARIF file", rule.Id))
				}
				ruleMap[rule.Id] = rule
			}
		}
	}
	return ruleMap, nil
}

// linkRegex finds references of the form `[label](targetID)`
var linkRegex = regexp.MustCompile(`\[([^\]]+)\]\(([^)]+)\)`)

// linkTarget represents a hyperlink target found in a SARIF message.
// It contains the display text, the target ID referenced in the message,
// and the physical location in the source code that the link points to.
type linkTarget struct {
	text                   string
	targetID               int
	targetPhysicalLocation v210autofix.PhysicalLocation
}

// processMessageLink processes a single markdown-style link reference found in a SARIF message.
// It expects a regex match group containing the link label and a numeric target ID.
// The function attempts to resolve the target ID to a related location in the SARIF result.
// If the related location is found and is different from the primary alert location,
// it appends a linkTarget to the provided linkTargets slice and returns a formatted markdown link
// referencing the target ID. If the related location matches the primary alert location,
// it returns only the link text without a link. Returns an error if the target ID is invalid
// or the related location cannot be found.
func processMessageLink(ctx context.Context, groups []string, result v210autofix.Result, primaryAlertLocation v210autofix.PhysicalLocation, linkTargets *[]linkTarget) (string, error) {
	enhancedctx.Logger(ctx).Debug("Processing message link")

	text := groups[1]                        //nolint:gosec // This is safe
	targetID, err := strconv.Atoi(groups[2]) //nolint:gosec // This is safe
	if err != nil {
		return "", err
	}

	location := result.FindRelatedLocation(targetID)
	if location == nil {
		return "", errors.Errorf("missing related location: %d", targetID)
	}

	// Check if PhysicalLocation is nil
	if location.PhysicalLocation == nil {
		return "", errors.Errorf("nil physical location for related location: %d", targetID)
	}

	targetPhysicalLocation := *location.PhysicalLocation

	// Check if ArtifactLocation or Region is nil
	if targetPhysicalLocation.ArtifactLocation == nil {
		return "", errors.Errorf("nil artifact location for related location: %d", targetID)
	}
	if targetPhysicalLocation.Region == nil {
		return "", errors.Errorf("nil region for related location: %d", targetID)
	}
	// Check if primaryAlertLocation or Region is nil
	if primaryAlertLocation.ArtifactLocation == nil {
		return "", errors.Errorf("nil primary alert artifact location: %v", primaryAlertLocation)
	}
	if primaryAlertLocation.Region == nil {
		return "", errors.Errorf("nil primary alert region: %v", primaryAlertLocation)
	}

	// skip links that point to the same line as the primary alert location
	if targetPhysicalLocation.ArtifactLocation.Uri == primaryAlertLocation.ArtifactLocation.Uri &&
		targetPhysicalLocation.Region.StartLine == primaryAlertLocation.Region.StartLine {
		return text, nil
	}

	// Replace references of the form `[label](targetId)` with `[label](#targetId)`.
	*linkTargets = append(*linkTargets, linkTarget{text, targetID, targetPhysicalLocation})
	return fmt.Sprintf("[%s](#%d)", text, targetID), nil
}

// processMessage extracts message text and alert message links from a SARIF message object.
func processMessage(ctx context.Context, message v210autofix.Message, cb codebase.VirtualCodebase, result v210autofix.Result, primaryAlertLocation v210autofix.PhysicalLocation) (string, []alerts.AlertMessageLink, error) {
	linkTargets := []linkTarget{}

	if message.Text == "" {
		// If the message text is empty, we return an empty string and no links.
		enhancedctx.Logger(ctx).Debug("Message text is empty, returning empty message text and no links")
		return "", []alerts.AlertMessageLink{}, errors.Errorf("missing alert message: %v", message)
	}

	messageText := ""
	// We discard all but the first line of the message to avoid duplication from
	// multiple messages with different references.
	firstLine := strings.Split(message.Text, "\n")[0]
	messageText, err := utils.RegexReplaceFunc(firstLine, linkRegex, func(groups []string) (string, error) {
		return processMessageLink(ctx, groups, result, primaryAlertLocation, &linkTargets)
	})
	if err != nil {
		// If an error occurred during link extraction, we're happy logging the error
		// and then proceeding like normal. This is because we can get an error if the
		// link extraction failed, but in effect we get the first error from the link
		// extraction process above and bail, which is too aggressive.
		enhancedctx.Logger(ctx).Error("Error processing alert message", kvp.String("error", err.Error()), kvp.String("message", message.Text))
	}
	if messageText == "" {
		// We still want to return the message text, even if it is empty - this way, we're not
		// degrading the user experience by not showing the message text at all.
		// If no links were found, we use the first line of the message as the message text.
		// This is a fallback to ensure that we always have some message text to display.
		messageText = firstLine
		enhancedctx.Logger(ctx).Debug("No links found in message, using first line as message text", kvp.String("message", messageText))
	}

	links := []alerts.AlertMessageLink{}
	for _, linkTarget := range linkTargets {
		var context codebase.ContextLines
		context, target, err := extractAlertLocations(cb, linkTarget.targetPhysicalLocation)
		if err != nil || target == nil {
			continue // Skip links that point to non-existent files, or where we fail to extract the location.
		}
		links = append(links, alerts.AlertMessageLink{Target: *target, TargetId: linkTarget.targetID, Text: linkTarget.text, Context: contextsset.NewContextsSet([]codebase.ContextLines{context})})
	}

	return messageText, links, nil
}

// Extract the alert location and context from a PhysicalLocation.
// Or a nil `SourceLocation` if the file could not be found.
func extractAlertLocations(code codebase.VirtualCodebase, physicalLocation v210autofix.PhysicalLocation) (codebase.ContextLines, *codebase.SourceLocation, error) {
	// Extract the file and alert location
	file, err := extractFile(code, physicalLocation)
	if err != nil {
		contextLines := codebase.ContextLines{} //nolint:exhaustruct // effectively a nil value. The caller should check whether the SourceLocation is nil.
		// returning nil SourceLocation here, as described in the docstring, because the file didn't exist
		return contextLines, nil, nil //nolint:nilerr // Yes, not returning an error here is intentional.
	}

	if physicalLocation.Region == nil {
		return codebase.ContextLines{}, nil,
			autofix.NewParsingError("missing region in physical location",
				errors.New("null region in SARIF"))
	}

	alertLoc, err := codebase.NewSourceLocationWithContent(file, *physicalLocation.Region)
	if err != nil {
		return codebase.ContextLines{}, nil, err
	}

	// Extract the context lines
	contextLines, err := extractContextLines(file, alertLoc, physicalLocation.ContextRegion)
	if err != nil {
		return codebase.ContextLines{}, nil, err
	}

	return contextLines, &alertLoc, nil
}

func extractFile(cb codebase.VirtualCodebase, location v210autofix.PhysicalLocation) (codebase.File, error) {
	if location.ArtifactLocation == nil {
		return codebase.File{}, autofix.NewParsingError("missing artifact location",
			errors.New("null artifact location in SARIF"))
	}

	uri := location.ArtifactLocation.Uri
	if uri == "" {
		locationJSON, err := json.MarshalIndent(location, "", "  ")
		if err != nil {
			return codebase.File{}, st.EnsureStackTrace(err, "error marshalling location to JSON")
		}
		return codebase.File{}, errors.Errorf("missing artifact location URI: %s", locationJSON)
	}

	return cb.GetFile(uri)
}

// extractContextLines converts a SARIF Region to a ContextLines object.
func extractContextLines(
	file codebase.File,
	alertLoc codebase.SourceLocation,
	sarifRegion *v210autofix.Region,
) (codebase.ContextLines, error) {
	// if no context region is specified, use the alert region plus four lines of
	// context after the alert, extended to minContextLines
	if sarifRegion == nil {
		sarifRegion = &v210autofix.Region{ //nolint:exhaustruct // No need to fill all fields, just the ones we use.
			StartLine: int(alertLoc.StartLine()),
			EndLine:   int(alertLoc.EndLine() + 4),
		}
	}

	if sarifRegion.StartLine == 0 {
		sarifRegionJSON, _ := json.MarshalIndent(sarifRegion, "", "  ")
		return codebase.ContextLines{}, errors.Errorf("missing context start line: %s", sarifRegionJSON)
	}

	fileContents, err := file.ReadContents()
	if err != nil {
		return codebase.ContextLines{}, st.EnsureStackTrace(err, "error reading file contents")
	}

	endLine := sarifRegion.EndLine
	if endLine == 0 {
		endLine = sarifRegion.StartLine
	}

	return codebase.NewContextLines(
		codebase.LineRegion{
			File:      file,
			StartLine: codebase.LineNumber(sarifRegion.StartLine),
			EndLine:   codebase.LineNumber(endLine),
		},
		fileContents,
	), nil
}
