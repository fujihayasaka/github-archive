// Package contextsset provides a collection abstraction over multiple code contexts
// (line regions) within a single file, including support for collapsing nearby regions
// and extracting preamble sections.
package contextsset

import (
	"sort"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/preambler"
)

// IContextsSet is a set of ContextLines that represent multiple contexts (a section in a file between a start and end line) in a single file.
// Some of these contexts are only added to be the preamble of the file, and do not by themselves contain any alerts or flow-steps.
// Whether a context is only part of the preamble or not can be queried with `IsPreamble`.
type IContextsSet interface {
	File() codebase.File
	WithCollapsedGaps(allowedDistanceOptional ...int) IContextsSet
	WithAddedContexts(contexts []codebase.ContextLines) IContextsSet
	WithExtractedPreamble() IContextsSet
	ToSet() IContextsSet
	Contexts() []codebase.ContextLines
	GetFileContents() string
	InputContexts() []codebase.ContextLines
	PreambleContexts() []codebase.ContextLines
}

// ContextsSet implements IContextsSet, and is a set of ContextLines that represent multiple contexts (a section in a file between a start and end line) in a single file.
// Some of these contexts are only added to be the preamble of the file, and do not by themselves contain any alerts or flow-steps.
// Whether a context is only part of the preamble or not can be queried with `isPreamble`.
type ContextsSet struct {
	contexts         []codebase.ContextLines
	inputContexts    []codebase.ContextLines
	preambleContexts []codebase.ContextLines
}

var _ IContextsSet = &ContextsSet{} //nolint:exhaustruct

// NewContextsSet constructs a ContextsSet from the provided context slices.
func NewContextsSet(inputContexts []codebase.ContextLines) *ContextsSet {
	return NewContextsSetWithPreamble(inputContexts, nil)
}

// NewContextsSetWithPreamble constructs a ContextsSet providing an explicit preamble contexts slice.
func NewContextsSetWithPreamble(inputContexts []codebase.ContextLines, preambleContexts []codebase.ContextLines) *ContextsSet {
	contexts := append(preambleContexts, inputContexts...)
	return &ContextsSet{
		contexts:         contexts,
		inputContexts:    inputContexts,
		preambleContexts: preambleContexts,
	}
}

// File returns the file shared by all contexts in the set.
func (c ContextsSet) File() codebase.File {
	return (c.contexts[0].File())
}

// GetFileContents gets the contents of the file containing the contexts.
func (c ContextsSet) GetFileContents() string {
	return c.contexts[0].FileContents
}

// WithCollapsedGaps collapses any contexts that are within `allowedDistance` lines of each other, or overlapping.
// And ensure that the list of contexts is sorted by startLine in the output.
func (c ContextsSet) WithCollapsedGaps(allowedDistanceOptional ...int) IContextsSet {
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
		if int(curr.StartLine-prev.EndLine) <= allowedDistance || /* within the distance, */
			curr.StartLine <= prev.EndLine /* or the two are overlapping */ {
			// pop the previous, and add a new one that spans both
			newSnippets[len(newSnippets)-1] = codebase.NewContextLines(
				codebase.LineRegion{
					File:      prev.File(),
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
func (c ContextsSet) WithAddedContexts(contexts []codebase.ContextLines) IContextsSet {
	return NewContextsSetWithPreamble(append(c.InputContexts(), contexts...), c.PreambleContexts())
}

// WithExtractedPreamble augments the set with an extracted preamble.
func (c ContextsSet) WithExtractedPreamble() IContextsSet {
	preamble := preambler.ExtractPreamble(
		c.File(),
		c.GetFileContents(),
		-1,
	)
	return NewContextsSetWithPreamble(c.InputContexts(), append(c.PreambleContexts(), preamble...))
}

// ToSet returns the receiver as an IContextsSet (identity).
func (c ContextsSet) ToSet() IContextsSet {
	return c
}

// Contexts returns all contexts (preamble + main) in order.
func (c ContextsSet) Contexts() []codebase.ContextLines {
	return c.contexts
}

// InputContexts returns the original non-preamble contexts supplied.
func (c ContextsSet) InputContexts() []codebase.ContextLines {
	return c.inputContexts
}

// PreambleContexts returns contexts considered part of the preamble.
func (c ContextsSet) PreambleContexts() []codebase.ContextLines {
	return c.preambleContexts
}
