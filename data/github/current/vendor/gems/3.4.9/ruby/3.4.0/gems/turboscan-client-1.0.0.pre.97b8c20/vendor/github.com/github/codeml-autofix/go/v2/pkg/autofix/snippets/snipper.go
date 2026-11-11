package snippets

import (
	"context"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/contextsset"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixstate"
	"github.com/github/github-telemetry-go/kvp"
)

// InitialLineNumberRegex matches a leading (possibly fractional) line number like "12:" or "1.5:".
var InitialLineNumberRegex = regexp.MustCompile(`^[\d.]+: ?`) // the model occasionally uses fractional line numbers, e.g. 1.5

// LineNumberRegex matches line numbers at the start of any line in multi-line text.
var LineNumberRegex = regexp.MustCompile(`(?m)` + InitialLineNumberRegex.String())

// TextWithLineNumbers renders a context set to a code snippet including line numbers.
func TextWithLineNumbers(ctx context.Context, c contextsset.IContextsSet) (string, error) {
	rendered, err := RenderCodeSnippet(ctx, c, nil)
	if err != nil {
		return "", st.EnsureStackTrace(err, "failed to render code snippet")
	}
	return rendered, nil
}

// GetShownLinesForFile returns the sorted unique set of line numbers that will
// be shown for the given file in the prompt (across alert context, collapsed
// flow, links, etc.).
func GetShownLinesForFile(ctx context.Context, alert *alerts.Alert, file codebase.File) ([]codebase.LineNumber, error) {
	ctx, span := enhancedctx.StartSpan(ctx, "snippets.GetShownLinesForFile")
	defer span.End()

	result := map[codebase.LineNumber]bool{} // a set

	addLinesFromRenderedLines := func(renderedLines string) {
		lineNumbers := LineNumberRegex.FindAllString(renderedLines, -1)
		for _, line := range lineNumbers {
			trimmed := strings.TrimSuffix(strings.TrimSpace(line), ":")
			lineNumber, err := strconv.Atoi(trimmed)
			if err != nil {
				enhancedctx.Logger(ctx).WithError(err).Error("failed to parse line number",
					kvp.String("gh.autofix.line_number", trimmed),
				)
				continue
			}
			result[codebase.LineNumber(lineNumber)] = true
		}
	}

	baseFixState, err := fixstate.NewBaseFixState(alert)
	if err != nil {
		return nil, st.EnsureStackTrace(err, "failed to create base fix state")
	}

	singleFlowContext := baseFixState.SingleFileFlowContext
	if singleFlowContext != nil {
		txt, err := TextWithLineNumbers(ctx, singleFlowContext.ContextSet.WithExtractedPreamble())
		if err != nil {
			return nil, st.EnsureStackTrace(err, "failed to get text with line numbers from single file flow context")
		}
		addLinesFromRenderedLines(txt)
	} else {
		txt, err := TextWithLineNumbers(ctx, alert.Context.WithExtractedPreamble())
		if err != nil {
			return nil, st.EnsureStackTrace(err, "failed to get text with line numbers from alert context")
		}
		addLinesFromRenderedLines(txt)
	}

	if alert.CollapsedFlow != nil {
		for _, step := range alert.CollapsedFlow {
			if step.File.Equals(file) {
				txt, err := TextWithLineNumbers(ctx, step.ContextSet.WithExtractedPreamble())
				if err != nil {
					return nil, st.EnsureStackTrace(err, "failed to get text with line numbers from collapsed flow")
				}
				addLinesFromRenderedLines(txt)
			}
		}
	}

	for _, link := range alert.Links {
		if link.Target.File.Equals(file) && link.Context != nil {
			txt, err := TextWithLineNumbers(ctx, link.Context.ToSet().WithExtractedPreamble())
			if err != nil {
				return nil, st.EnsureStackTrace(err, "failed to get text with line numbers from link context")
			}
			addLinesFromRenderedLines(txt)
		}
	}

	sortedResult := make([]codebase.LineNumber, 0, len(result))
	for line := range result {
		sortedResult = append(sortedResult, line)
	}
	sort.Slice(sortedResult, func(i, j int) bool {
		return sortedResult[i] < sortedResult[j]
	})

	return sortedResult, nil
}
