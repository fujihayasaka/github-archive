// Package alerts provides types and functions to represent and manipulate alerts in the autofix system.
package alerts

import (
	"context"
	"encoding/json"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/contextsset"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"

	tools "github.com/github/codeml-autofix/go/v2/pkg/autofix/tools_suites"
)

// Rule represents a SARIF rule.
type Rule struct {
	// The short ID of the rule, e.g., `go/zipslip`.
	ID string `json:"id"`

	// The short description of the rule, e.g., `Arbitrary file write during zip extraction ("zip slip")`.
	ShortDescription string `json:"shortDescription"`

	// The full description of the rule, if available.
	FullDescription string `json:"fullDescription,omitempty"`

	// The documentation of the rule, in Markdown format, if available.
	Documentation string `json:"documentation,omitempty"`
}

// NewRule creates a new Rule.
func NewRule(id, shortDescription, fullDescription, documentation string) Rule {
	return Rule{
		ID:               id,
		ShortDescription: shortDescription,
		FullDescription:  fullDescription,
		Documentation:    documentation,
	}
}

// ToJSON converts the Rule to a JSON object.
func (r *Rule) ToJSON() (map[string]interface{}, error) {
	data, err := json.Marshal(r)
	if err != nil {
		return nil, err
	}
	var result map[string]interface{}
	err = json.Unmarshal(data, &result)
	return result, err
}

// FlowStep is a single step in a flow.
type FlowStep struct {
	// The context for this flow step, i.e., a few lines of code before and after the flow step location.
	Context codebase.ContextLines `json:"context"`

	// The location for this flow step.
	Location codebase.SourceLocation `json:"location"`

	// The message for this flow step.
	Message string `json:"message,omitempty"`
}

// NewFlowStep creates a new FlowStep.
func NewFlowStep(ctx codebase.ContextLines, location codebase.SourceLocation, message string) FlowStep {
	return FlowStep{
		Context:  ctx,
		Location: location,
		Message:  message,
	}
}

// ToJSON converts the FlowStep to a JSON object.
func (fs *FlowStep) ToJSON() (map[string]interface{}, error) {
	data, err := json.Marshal(fs)
	if err != nil {
		return nil, err
	}
	var result map[string]interface{}
	err = json.Unmarshal(data, &result)
	return result, err
}

// Equals checks if two FlowStep objects are equal.
// Note that equality is determined only using the Message and Location fields and
// specifically ignoring the Context field.
func (fs *FlowStep) Equals(other *FlowStep) bool {
	return fs.Message == other.Message && fs.Location.Equals(&other.Location)
}

// CollapsedFlowStep is a set of consecutive flow steps that are closely grouped
// together in the same file.
type CollapsedFlowStep struct {
	// AllSteps contains all the flow steps that are collapsed into this step.
	AllSteps []FlowStep
	// ContextSet contains the completed context for this collapsed flow step, i.e., all the lines
	// that are in the individual flow steps, and a few lines of code before
	// and after.
	ContextSet contextsset.IContextsSet
	// File is the file containing all the flow steps that are collapsed into this step.
	File codebase.File
}

// NewCollapsedFlowStep creates a new CollapsedFlowStep from a list of flow steps and a contexts set.
func NewCollapsedFlowStep(flowSteps []FlowStep, contextSet contextsset.IContextsSet, file codebase.File) (CollapsedFlowStep, autofix.AutofixError) {
	var newCollapsedFlowStep CollapsedFlowStep
	for _, step := range flowSteps {
		if !step.Location.File.Equals(file) {
			return newCollapsedFlowStep, autofix.NewLogicError("all flow steps in a collapsed flow step must be in the same file")
		}
	}
	newCollapsedFlowStep = CollapsedFlowStep{
		AllSteps:   flowSteps,
		ContextSet: contextSet,
		File:       file,
	}
	return newCollapsedFlowStep, nil
}

// StepsNotContainingTheirPredecessor skips steps that contain their predecessor.
func (cfs CollapsedFlowStep) StepsNotContainingTheirPredecessor() []FlowStep {
	if len(cfs.AllSteps) == 0 {
		return []FlowStep{}
	}
	result := []FlowStep{cfs.AllSteps[0]}

	for i := 1; i < len(cfs.AllSteps); i++ {
		prev := result[len(result)-1]
		next := cfs.AllSteps[i]

		if i < len(cfs.AllSteps)-1 && // always include the last step
			next.Location.Includes(prev.Location) { // skip if this step includes the previous one
			continue // skip this step
		}
		// add next
		result = append(result, next)
	}

	return result
}

// RelativePath is a relative path to a file, used in alerts to indicate related files.
type RelativePath string

// Alert represents an alert in the autofix system.
type Alert struct {
	// Rule is the rule that generated the alert.
	Rule Rule
	// Tool is the name of the tool that generated the alert. This is the name of the "driver" from the SARIF file.
	Tool tools.Tool
	// CollapsedFlow is the flow for the alert, represented as a series of collapsed steps, if any.
	CollapsedFlow []CollapsedFlowStep
	// Flow is the flow steps for the alert.
	Flow []FlowStep
	// Links is the list of links contained in the alert message.
	// The context is only defined if the location is not already covered by the alert-location or the flow.
	Links []AlertMessageLink
	// Location is the location of the alert in the source code.
	Location codebase.SourceLocation
	// Message is the message of the alert.
	Message string
	// The context for the alert location, i.e., a few lines of code before and
	// after the alert location.
	Context contextsset.IContextsSet
	// The alert language.
	Language utils.Language
	// The files that are involved in the alert, including the flow steps and links.
	RelatedFiles []RelativePath
	// An identifier that associates the alert with a fix.
	ID string
}

// AlertMessageLink is a link embedded in an alert message.
type AlertMessageLink struct {
	// Target is the location of the link.
	Target codebase.SourceLocation

	// TargetId uniquely identifies a target within an alert message.
	TargetId int

	// Text is the text of the link.
	Text string

	// The context for the link, if any.
	//
	// No context is provided for links whose target location is already covered
	// by the alert location or the flow.
	Context contextsset.IContextsSet
}

// MakeOptions contains options for creating an alert.
type MakeOptions struct {
	Language utils.Language
	DevMode  bool
}

// NewAlert creates an alert where the flow steps have been deduplicated.
func NewAlert(
	ctx context.Context,
	id string,
	message string,
	links []AlertMessageLink,
	rule Rule,
	tool tools.Tool,
	options MakeOptions,
	contextLines codebase.ContextLines,
	location codebase.SourceLocation, // TODO translate later: this should be mandatory, but that's not supported in the go version yet.
	flowOptional ...[]FlowStep,
) (Alert, error) {
	enhancedctx.Logger(ctx).Info("Creating alert")

	var flow []FlowStep
	if len(flowOptional) > 0 && len(flowOptional[0]) > 0 {
		flow = flowOptional[0]
	}
	if len(flow) > 0 {
		// deduplicate flow steps
		res := []FlowStep{flow[0]}
		for i := 1; i < len(flow); i++ {
			prev := res[len(res)-1]
			next := flow[i]
			if prev.Equals(&next) {
				continue
			}
			res = append(res, next)
		}
		flow = res
	}

	// skip steps that jump back and forth between files
	if len(flow) > 0 {
		flow = skipFileBackAndForths(flow)
	}

	// collapse the remaining flow steps
	collapsedFlow := []CollapsedFlowStep{}
	if len(flow) > 0 {
		collapsedFlow = collapseFlow(ctx, flow)
	}

	// if the user didn't specify a language, try to infer it from the query ID
	// or the filename.
	language := options.Language
	if language == "" {
		// Try to infer the language from the query ID.
		inferredLanguage := utils.LanguageFromQueryID(rule.ID)
		// If not found from query ID, try from filename
		if inferredLanguage == utils.LanguageUnknown {
			inferredLanguage = utils.LanguageFromFilename(location.File.Path)
		}

		enhancedctx.Logger(ctx).Info("Inferred language for alert",
			kvp.String("gh.autofix.language", string(inferredLanguage)),
			kvp.String("gh.autofix.query_id", rule.ID),
			kvp.String("gh.autofix.file_path", location.File.Path),
			kvp.Bool("gh.autofix.is_unknown", inferredLanguage == utils.LanguageUnknown))

		language = inferredLanguage
	}

	filteredLinks, extraContexts := linksWithOnlyRelevantContext(links, flow, contextLines)

	relatedFiles, err := relevantFiles(contextLines, collapsedFlow, filteredLinks)
	if err != nil {
		return Alert{}, err
	}

	return Alert{
		ID:            id,
		Message:       message,
		Links:         filteredLinks,
		Rule:          rule,
		Tool:          tool,
		Language:      language,
		Context:       contextsset.NewContextsSet([]codebase.ContextLines{contextLines}).WithAddedContexts(extraContexts),
		Location:      location,
		Flow:          flow,
		CollapsedFlow: collapsedFlow,
		RelatedFiles:  relatedFiles,
	}, nil
}

/*
Filters out the context from the links that are already shown in the
alert-location or in the flow-path.

Returns the new set of links, and extra context-lines that should be shown as
part of the "main" code-snippet.
*/
func linksWithOnlyRelevantContext(
	links []AlertMessageLink,
	flow []FlowStep,
	alertContext codebase.ContextLines,
) (
	[]AlertMessageLink,
	[]codebase.ContextLines,
) {
	extraContexts := []codebase.ContextLines{}

	existingLocs := contextsset.NewContextsSet([]codebase.ContextLines{alertContext}).WithExtractedPreamble().Contexts()
	for _, f := range flow {
		existingLocs = append(
			existingLocs,
			f.Context,
		)
	}

	// filter away all the contexts that are already shown in the alert-location
	// or in the flow-path.
	linksWithFilteredContexts := make([]AlertMessageLink, len(links))
	copy(linksWithFilteredContexts, links)
	for i := range links {
		link := &linksWithFilteredContexts[i]
		// isWithinShown is true if the link is already shown in the already
		// existing locations (the alert-location or in the flow-path):
		isWithinShown := utils.Some(existingLocs, func(existingLoc codebase.ContextLines) bool {
			return link.Target.File.Equals(existingLoc.File()) &&
				link.Target.StartLine() >= existingLoc.StartLine &&
				link.Target.EndLine() <= existingLoc.EndLine
		})
		if isWithinShown {
			link.Context = nil
		}
	}

	// any remaining that are in the same file as the alert-location, add the context to the main code-snippet shown for the alert.
	for i := range linksWithFilteredContexts {
		link := &linksWithFilteredContexts[i]
		if link.Context != nil && link.Target.File.Equals(alertContext.File()) {
			extraContexts = append(extraContexts, link.Context.Contexts()...)
			link.Context = nil
		}
	}

	return linksWithFilteredContexts, extraContexts
}

/*
Skip the steps that are in a back-and-forth between files. I.e. if the steps `a
-> b -> c` jump from file `A.js` to file `B.js` and then back to file `A.js`,
then we skip the step `b`, if the step `c` is included by `a`. This can e.g.
happen in a call to a function in another file. In that case `a` will be an
argument to the function, `b` will be inside the function, and `c` will be
contain the returned value.

Historically these kinds of steps have been skipped entirely by the CodeQL JS
analysis, as the steps inside the called function would always be part of a
summary. However, the shared dataflow library include these steps.

The reason we skip these steps is that they are not very interesting to the
model, and they can make the prompt very long, as we have to present the file
`A.js` twice.
*/
func skipFileBackAndForths(steps []FlowStep) []FlowStep {
	// first skip some steps. If a step jumps from A to B where B is in another
	// file, but we later come back to a location C that is included by A, then
	// we skip all the steps between A and C.
	skips := make(map[int]bool)
	for i := 0; i < len(steps)-1; i++ {
		_, isInSkips := skips[i]
		if isInSkips {
			// we've already skipped this step, we cannot find any more steps to
			// skip from it
			continue
		}
		// assume a list [a,b,c,d,e,f], and i = 1
		prev := steps[i]         // b
		next := steps[i+1]       // c
		following := steps[i+2:] // [d,e,f]
		if prev.Location.File.Equals(next.Location.File) {
			// if we're in the same file, then we don't need to skip anything
			continue
		}
		// we now know that b -> c jumps to another file

		// find a step back in the original file that includes the previous step
		// `b`
		includesIdx := utils.FindIdx(following, func(f FlowStep) bool {
			return f.Location.File.Equals(prev.Location.File) &&
				f.Location.StartLine() == prev.Location.StartLine()
		})

		if includesIdx != -1 {
			// one of the following steps includes the previous step, so we can skip all the steps between them
			for j := i; j < includesIdx; j++ {
				skips[j] = true
			}
		}
	}

	// return the steps that are not skipped
	ret := []FlowStep{}
	for i, step := range steps {
		if !skips[i] {
			ret = append(ret, step)
		}
	}
	return ret
}

/*
Collapses a list of flow steps, into a list of collapsed flow steps. Each
collapsed flow step is a list of flow steps from the same file that are close
enough to each other to be collapsed into a single code-snippet.
*/
func collapseFlow(ctx context.Context, steps []FlowStep) []CollapsedFlowStep {
	current := []FlowStep{steps[0]}
	result := []CollapsedFlowStep{}
	collapse := func(current []FlowStep) (CollapsedFlowStep, error) {
		file := current[0].Location.File
		currentContexts := []codebase.ContextLines{}
		for _, step := range current {
			currentContexts = append(currentContexts, step.Context)
		}
		collapsed, err := NewCollapsedFlowStep(
			current,
			contextsset.NewContextsSet(currentContexts),
			file)

		if err != nil {
			enhancedctx.Logger(ctx).WithError(err).Error("failed to collapse flow")
		}

		return collapsed, err
	}

	for _, step := range steps {
		if len(current) == 0 {
			current = append(current, step)
			continue
		}
		prev := current[len(current)-1]
		if prev.Location.File.Path == step.Location.File.Path {
			// if we're in the same file, assume the steps close enough. If we
			// didn't collapse them, then we would show the preamble twice.
			current = append(current, step)
		} else {
			collapsed, err := collapse(current)
			if err != nil {
				continue
			}
			result = append(result, collapsed)
			current = []FlowStep{step}
		}
	}

	if len(current) > 0 {
		collapsed, err := collapse(current)
		if err != nil {
			return result
		}
		result = append(result, collapsed)
	}
	return result
}

// relevantFiles is the set of files that hold relevant context for an alert.
func relevantFiles(contextLines codebase.ContextLines, collapsedFlow []CollapsedFlowStep, links []AlertMessageLink) ([]RelativePath, error) {
	// Create a set of relevant files
	seen := make(map[RelativePath]struct{})
	result := []RelativePath{}
	addFile := func(file codebase.File) {
		if _, ok := seen[RelativePath(file.Path)]; !ok {
			seen[RelativePath(file.Path)] = struct{}{}
			result = append(result, RelativePath(file.Path))
		}
	}
	cb := contextLines.File().Codebase
	addFile(contextLines.File())
	for _, step := range collapsedFlow {
		if !step.File.Codebase.Equals(cb) {
			return nil, errors.New("all relevant files for an alert must be in the same codebase")
		}
		addFile(step.File)
	}
	for _, link := range links {
		if !link.Target.File.Codebase.Equals(cb) {
			return nil, errors.New("all relevant files for an alert must be in the same codebase")
		}
		addFile(link.Target.File)
	}

	return result, nil
}

// GetRule returns the rule that generated the alert.
func (a *Alert) GetRule() Rule {
	return a.Rule
}
