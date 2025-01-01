package contextsset

import (
	"github.com/github/codeml-autofix/go/pkg/autofix/codebase"
)

type MockContextsSet struct {
	File_                codebase.File
	TextWithLineNumbers_ string
	Contexts_            []codebase.ContextLines
}

var _ IContextsSet = &MockContextsSet{} //nolint:exhaustruct

func (m MockContextsSet) File() codebase.File {
	return m.File_
}

func (m MockContextsSet) TextWithLineNumbers() (string, error) {
	return m.TextWithLineNumbers_, nil
}

func (m MockContextsSet) IsPreamble(lines codebase.ContextLines) bool {
	return false
}

func (m MockContextsSet) ToSet() IContextsSet {
	return m
}

func (m MockContextsSet) Contexts() []codebase.ContextLines {
	return m.Contexts_
}

func (m MockContextsSet) WithCollapsedGaps(allowedDistanceOptional ...int) IContextsSet {
	return m
}

func (m MockContextsSet) WithAddedContexts(contexts []codebase.ContextLines) IContextsSet {
	panic("WithAddedContexts not implemented")
}

func (m MockContextsSet) WithPreamble() IContextsSet {
	// TODO: It would be more robust to modify the contexts set here to have an effect
	// visible in tests.
	return m
}

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

func (m MockContextsSet) InputContexts() []codebase.ContextLines {
	panic("InputContexts not implemented")
}

func (m MockContextsSet) PreambleContexts() []codebase.ContextLines {
	panic("PreambleContexts not implemented")
}
