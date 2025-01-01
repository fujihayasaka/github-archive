package contextsset

import (
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
)

// MockContextsSet is a test double implementing IContextsSet for unit tests.
type MockContextsSet struct {
	File_                codebase.File           //nolint:revive // to avoid conflict with methods
	TextWithLineNumbers_ string                  //nolint:revive // to avoid conflict with methods
	Contexts_            []codebase.ContextLines //nolint:revive // to avoid conflict with methods
}

var _ IContextsSet = &MockContextsSet{} //nolint:exhaustruct

// File returns the mock file.
func (m MockContextsSet) File() codebase.File {
	return m.File_
}

// TextWithLineNumbers returns preconfigured text with line numbers.
func (m MockContextsSet) TextWithLineNumbers() (string, error) {
	return m.TextWithLineNumbers_, nil
}

// ToSet returns the mock as-is.
func (m MockContextsSet) ToSet() IContextsSet {
	return m
}

// Contexts returns provided context slices.
func (m MockContextsSet) Contexts() []codebase.ContextLines {
	return m.Contexts_
}

// WithCollapsedGaps is a no-op for the mock implementation.
func (m MockContextsSet) WithCollapsedGaps(allowedDistanceOptional ...int) IContextsSet {
	return m
}

// WithAddedContexts is not implemented for the mock and panics.
func (m MockContextsSet) WithAddedContexts(contexts []codebase.ContextLines) IContextsSet {
	panic("WithAddedContexts not implemented")
}

// WithExtractedPreamble is a no-op for the mock.
func (m MockContextsSet) WithExtractedPreamble() IContextsSet {
	// TODO: It would be more robust to modify the contexts set here to have an effect
	// visible in tests.
	return m
}

// GetFileContents reads file contents from the underlying mock file.
func (m MockContextsSet) GetFileContents() string {
	if m.File_.Codebase == nil {
		panic("GetFileContents: Codebase is nil")
	}
	contents, err := m.File_.ReadContents()
	if err != nil {
		panic("GetFileContents: " + err.Error())
	}
	return contents
}

// InputContexts panics (not implemented) in the mock.
func (m MockContextsSet) InputContexts() []codebase.ContextLines {
	panic("InputContexts not implemented")
}

// PreambleContexts panics (not implemented) in the mock.
func (m MockContextsSet) PreambleContexts() []codebase.ContextLines {
	panic("PreambleContexts not implemented")
}
