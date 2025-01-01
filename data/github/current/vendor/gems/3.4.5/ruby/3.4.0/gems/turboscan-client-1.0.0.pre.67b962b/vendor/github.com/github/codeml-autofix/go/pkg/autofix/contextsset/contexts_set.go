package contextsset

import (
	"reflect"
	"sort"

	"github.com/github/codeml-autofix/go/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/pkg/autofix/preambler"
)

/**
 * A set of {@link ContextLines} that represent multiple contexts (a section in a file between a start and end line) in a single file.
 * Some of these contexts are only added to be the preamble of the file, and do not by themselves contain any alerts or flow-steps.
 * Whether a context is only part of the preamble or not can be queried with `IsPreamble`.
 */
type IContextsSet interface {
	IsPreamble(lines codebase.ContextLines) bool
	File() codebase.File
	WithCollapsedGaps(allowedDistanceOptional ...int) IContextsSet
	WithAddedContexts(contexts []codebase.ContextLines) IContextsSet
	WithPreamble() IContextsSet
	ToSet() IContextsSet
	Contexts() []codebase.ContextLines
	GetFileContents() string
	InputContexts() []codebase.ContextLines
	PreambleContexts() []codebase.ContextLines
}

/**
 * A set of {@link ContextLines} that represent multiple contexts (a section in a file between a start and end line) in a single file.
 * Some of these contexts are only added to be the preamble of the file, and do not by themselves contain any alerts or flow-steps.
 * Whether a context is only part of the preamble or not can be queried with `isPreamble`.
 */
type ContextsSet struct {
	contexts         []codebase.ContextLines
	inputContexts    []codebase.ContextLines
	preambleContexts []codebase.ContextLines
}

var _ IContextsSet = &ContextsSet{} //nolint:exhaustruct

func NewContextsSet(inputContexts []codebase.ContextLines, preambleContextsOptional ...[]codebase.ContextLines) *ContextsSet {
	preambleContexts := []codebase.ContextLines{}
	if len(preambleContextsOptional) > 0 {
		preambleContexts = preambleContextsOptional[0]
	}
	contexts := append(preambleContexts, inputContexts...)
	return &ContextsSet{
		contexts:         contexts,
		inputContexts:    inputContexts,
		preambleContexts: preambleContexts,
	}
}

/** Whether the given context is part of the preamble. */
func (c ContextsSet) IsPreamble(lines codebase.ContextLines) bool {
	for _, context := range c.PreambleContexts() {
		if reflect.DeepEqual(context, lines) {
			return true
		}
	}
	return false
}

func (c ContextsSet) File() codebase.File {
	return (c.contexts[0].File())
}

/** The contents of the file containing the contexts. */
func (c ContextsSet) GetFileContents() string {
	return c.contexts[0].FileContents
}

/**
 * Collapses any contexts that are within `allowedDistance` lines of each other, or overlapping.
 * And ensure that the list of contexts is sorted by startLine in the output.
 */
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
	return NewContextsSet(newSnippets, c.Contexts()[:len(c.Contexts())-len(c.InputContexts())])
}

/** Returns a new ContextsSet with the given contexts added to the "main" contexts (non-preamble). */
func (c ContextsSet) WithAddedContexts(contexts []codebase.ContextLines) IContextsSet {
	return NewContextsSet(append(c.InputContexts(), contexts...), c.PreambleContexts())
}

func (c ContextsSet) WithPreamble() IContextsSet {
	// TODO consider implementing caching for this, as in ts implementation
	preamble := preambler.ExtractPreamble(
		c.File(),
		c.GetFileContents(),
		-1,
	)
	return NewContextsSet(c.InputContexts(), append(c.PreambleContexts(), preamble...))
}

func (c ContextsSet) ToSet() IContextsSet {
	return c
}

func (c ContextsSet) Contexts() []codebase.ContextLines {
	return c.contexts
}

func (c ContextsSet) InputContexts() []codebase.ContextLines {
	return c.inputContexts
}

func (c ContextsSet) PreambleContexts() []codebase.ContextLines {
	return c.preambleContexts
}
