// Package contextsset provides functionality for managing sets of code contexts
// from a file, including handling of preambles and context merging.
package contextsset

import (
	"sort"

	"github.com/github/code-scanning-ai-libraries/v2/codebase"
	"github.com/github/code-scanning-ai-libraries/v2/rendering/preambler"
)

// ContextsSet is a set of {@link ContextLines} that represent multiple contexts (a section in a file between a start and end line) in a single file.
// Some of these contexts are only added to be the preamble of the file, and do not by themselves contain any alerts or flow-steps.
// Whether a context is only part of the preamble or not can be queried with `isPreamble`.
type ContextsSet struct {
	contexts         []codebase.ContextLines
	inputContexts    []codebase.ContextLines
	preambleContexts []codebase.ContextLines
}

// NewContextsSet creates a new ContextsSet with the given contexts.
func NewContextsSet(inputContexts []codebase.ContextLines) *ContextsSet {
	return NewContextsSetWithPreamble(inputContexts, nil)
}

// NewContextsSetWithPreamble creates a new ContextsSet with the given contexts and preamble contexts.
func NewContextsSetWithPreamble(inputContexts, preambleContexts []codebase.ContextLines) *ContextsSet {
	contexts := make([]codebase.ContextLines, 0, len(preambleContexts)+len(inputContexts))
	contexts = append(contexts, preambleContexts...)
	contexts = append(contexts, inputContexts...)
	return &ContextsSet{
		contexts:         contexts,
		inputContexts:    inputContexts,
		preambleContexts: preambleContexts,
	}
}

// GetFileContents returns the file contents of the first context in the set.
func (c ContextsSet) GetFileContents() string {
	return c.contexts[0].FileContents
}

// WithCollapsedGaps returns a new ContextsSet with gaps between contexts collapsed.
// Collapses any contexts that are within `allowedDistance` lines of each other, or overlapping.
// And ensure that the list of contexts is sorted by startLine in the output.
func (c ContextsSet) WithCollapsedGaps(allowedDistanceOptional ...int) *ContextsSet {
	allowedDistance := 0
	if len(allowedDistanceOptional) > 0 {
		allowedDistance = allowedDistanceOptional[0]
	}

	prevSnippets := make([]codebase.ContextLines, len(c.InputContexts()))
	copy(prevSnippets, c.InputContexts())
	sort.Slice(prevSnippets, func(i, j int) bool {
		return prevSnippets[i].StartLine < prevSnippets[j].StartLine
	})

	newSnippets := []codebase.ContextLines{prevSnippets[0]}
	for i := 1; i < len(prevSnippets); i++ {
		prev := prevSnippets[i-1]
		curr := prevSnippets[i]
		// within the distance or the two are overlapping pop the previous, and add a new one that spans both
		if int(curr.StartLine-prev.EndLine) <= allowedDistance ||
			curr.StartLine <= prev.EndLine {
			newSnippets[len(newSnippets)-1] = codebase.NewContextLines(
				codebase.LineRegion{
					StartLine: prev.StartLine,
					EndLine:   curr.EndLine,
				},
				prev.FileContents,
			)
		} else {
			newSnippets = append(newSnippets, curr)
		}
	}
	return NewContextsSetWithPreamble(newSnippets, c.PreambleContexts())
}

// WithAddedContexts returns a new ContextsSet with the given contexts added to the "main" contexts (non-preamble).
func (c ContextsSet) WithAddedContexts(contexts []codebase.ContextLines) *ContextsSet {
	return NewContextsSetWithPreamble(append(c.InputContexts(), contexts...), c.PreambleContexts())
}

// WithExtractedPreamble extracts the preamble from the file contents and returns a new ContextsSet with the preamble contexts included.
func (c ContextsSet) WithExtractedPreamble() *ContextsSet {
	preamble := preambler.ExtractPreamble(
		c.GetFileContents(),
		-1,
	)
	return NewContextsSetWithPreamble(c.InputContexts(), append(c.PreambleContexts(), preamble...))
}

// ToSet returns the ContextsSet as itself, providing compatibility with interfaces.
func (c ContextsSet) ToSet() ContextsSet {
	return c
}

// Contexts returns all contexts, including both input contexts and preamble contexts.
func (c ContextsSet) Contexts() []codebase.ContextLines {
	return c.contexts
}

// InputContexts returns only the input contexts (non-preamble).
func (c ContextsSet) InputContexts() []codebase.ContextLines {
	return c.inputContexts
}

// PreambleContexts returns only the preamble contexts.
func (c ContextsSet) PreambleContexts() []codebase.ContextLines {
	return c.preambleContexts
}
