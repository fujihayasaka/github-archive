// Package editcommands defines a small DSL for describing textual edits to a
// source file (insert before/after and replace) and applying ordered edit
// sequences safely relative to line numbers.
package editcommands

import (
	"fmt"
	"slices"
	"strings"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
)

// EditCommandKind represents the kind of textual edit to apply.
type EditCommandKind string

const (
	EditCommandKindInsertAfter  EditCommandKind = "insertAfter"
	EditCommandKindInsertBefore EditCommandKind = "insertBefore"
	EditCommandKindReplace      EditCommandKind = "replace"
)

// EditCommands holds an ordered list of edit commands to apply to a file.
type EditCommands struct {
	// The list of edit commands, sorted by first line they apply to.
	Commands []EditCommand
}

// NewEditCommands returns an EditCommands collection sorted into a deterministic
// order so later application does not invalidate earlier line numbers.
func NewEditCommands(commands []EditCommand) EditCommands {
	/* sort the edit commands by the first line they apply to. */
	slices.SortStableFunc(
		commands,
		func(a, b EditCommand) int {
			aFirstLine := a.FirstLine()
			bFirstLine := b.FirstLine()
			// if two commands start on the same line, they should logically
			// come in the order "insert before", "replace", "insert after".
			editTypeOrder := func(editType EditCommandKind) int {
				switch editType {
				case EditCommandKindInsertBefore:
					return 0
				case EditCommandKindReplace:
					return 1
				case EditCommandKindInsertAfter:
					return 2
				default:
					panic("unknown edit type")
				}
			}
			if aFirstLine == bFirstLine {
				return editTypeOrder(a.Kind()) - editTypeOrder(b.Kind())
			} else {
				return int(aFirstLine) - int(bFirstLine)
			}
		},
	)
	return EditCommands{Commands: commands}
}

// Apply this sequence of edit commands to a given text and return the
// result.
//
// For edits with valid line numbers (i.e., not beyond the last line of
// text), we apply them in reverse order, so that the line numbers for later
// edits are not affected by earlier edits.
//
// For edits beyond the last line of text, we apply them in order. In
// particular, this means that edits with line number Infinity are applied
// one after another, but do not affect each other.
//
// Edits with line numbers beyond the last line of text but _not_ Infinity
// do affect each other, which is a bit inconsistent, but on the other hand
// it's not immediately clear how to interpret such edits otherwise.
func (e EditCommands) Apply(text string) string {
	lines := strings.Split(text, "\n")
	maxLine := codebase.LineNumber(len(lines))

	// first, apply edits beyond the end of the file in order
	for _, command := range e.Commands {
		if command.FirstLine() > maxLine {
			command.Apply(&lines)
		}
	}

	// now, apply edits inside the file in reverse order, so that the line
	// numbers remain valid
	for i := len(e.Commands) - 1; i >= 0; i-- {
		command := e.Commands[i]
		if command.FirstLine() <= maxLine {
			command.Apply(&lines)
		}
	}
	return strings.Join(lines, "\n")
}

// FileEdit is a proposed edit to a file.
type FileEdit struct {
	// The file where the edits should be applied.
	FilePath string
	// The edit commands we want to apply to this file.
	EditCommands EditCommands
}

// EditCommand is implemented by concrete edit operations (insert before/after,
// replace) that can apply themselves to a slice of lines.
type EditCommand interface {
	// The kind of edit command.
	Kind() EditCommandKind
	// The code block to be inserted.
	Block() []string
	// The first line affected by this edit command (1-based).
	//
	// Note that for a command `INSERT AFTER LINE <n>`, the first line affected is
	// still `<n>`, although the command itself does not modify that line.
	FirstLine() codebase.LineNumber

	// Apply this edit command to the contents of a file represented as a list
	// of lines, updating the list in place.
	Apply(lines *[]string)

	String() string
}

var _ EditCommand = &InsertAfter{} //nolint:exhaustruct

// InsertAfter inserts a block of lines after the specified line number.
type InsertAfter struct {
	block []string
	line  codebase.LineNumber
}

// Kind returns the edit kind discriminator.
func (i InsertAfter) Kind() EditCommandKind {
	return EditCommandKindInsertAfter
}

// Block returns the block of lines to insert.
func (i InsertAfter) Block() []string {
	return i.block
}

// FirstLine returns the reference line for the edit (the line after which the block is inserted).
func (i InsertAfter) FirstLine() codebase.LineNumber {
	return i.line
}

// Apply mutates the provided lines slice by inserting the block after the reference line.
func (i InsertAfter) Apply(lines *[]string) {
	newLen := len(*lines) + len(i.block)
	newLines := make([]string, 0, newLen)
	newLines = append(newLines, (*lines)[:i.line]...)
	newLines = append(newLines, i.block...)
	newLines = append(newLines, (*lines)[i.line:]...)
	*lines = newLines
}

// String returns a human readable description of the edit.
func (i InsertAfter) String() string {
	return fmt.Sprintf("insert after line %d", i.line)
}

// NewInsertAfter creates an InsertAfter edit.
func NewInsertAfter(line codebase.LineNumber, block []string) InsertAfter {
	return InsertAfter{
		line:  line,
		block: block,
	}
}

var _ EditCommand = &InsertBefore{} //nolint:exhaustruct

// InsertBefore inserts a block before the specified line number.
type InsertBefore struct {
	line  codebase.LineNumber
	block []string
}

// Kind returns the edit kind discriminator.
func (i InsertBefore) Kind() EditCommandKind {
	return EditCommandKindInsertBefore
}

// Block returns the block of lines to insert.
func (i InsertBefore) Block() []string {
	return i.block
}

// FirstLine returns the reference line for the edit (the line before which the block is inserted).
func (i InsertBefore) FirstLine() codebase.LineNumber {
	return i.line
}

// Apply mutates the provided lines slice by inserting the block before the reference line.
func (i InsertBefore) Apply(lines *[]string) {
	newLen := len(*lines) + len(i.block)
	newLines := make([]string, 0, newLen)

	newLines = append(newLines, (*lines)[:i.line-1]...)
	newLines = append(newLines, i.block...)
	newLines = append(newLines, (*lines)[i.line-1:]...)
	*lines = newLines
}

// String returns a human readable description of the edit.
func (i InsertBefore) String() string {
	return fmt.Sprintf("insert before line %d", i.line)
}

// NewInsertBefore creates an InsertBefore edit.
func NewInsertBefore(line codebase.LineNumber, block []string) InsertBefore {
	return InsertBefore{
		line:  line,
		block: block,
	}
}

var _ EditCommand = &Replace{} //nolint:exhaustruct

// Replace replaces a contiguous range of lines with a new block.
type Replace struct {
	block     []string
	startLine codebase.LineNumber
	endLine   codebase.LineNumber
}

// Kind returns the edit kind discriminator.
func (r Replace) Kind() EditCommandKind {
	return EditCommandKindReplace
}

// Block returns the replacement block.
func (r Replace) Block() []string {
	return r.block
}

// FirstLine returns the first line being replaced.
func (r Replace) FirstLine() codebase.LineNumber {
	return r.startLine
}

// Apply mutates the provided lines slice by replacing the target line range with the block.
func (r Replace) Apply(lines *[]string) {
	replacedBlockLength := int(r.endLine) - int(r.startLine) + 1
	newLinesLength := len(*lines) - replacedBlockLength + len(r.block)
	newLines := make([]string, 0, newLinesLength)
	newLines = append(newLines, (*lines)[:r.startLine-1]...)
	newLines = append(newLines, r.block...)
	newLines = append(newLines, (*lines)[r.endLine:]...)

	*lines = newLines
}

// String returns a human readable description of the edit.
func (r Replace) String() string {
	return fmt.Sprintf("replace lines %d-%d with %d lines", r.startLine, r.endLine, len(r.block))
}

// NewReplace creates a Replace edit covering the inclusive line range.
func NewReplace(startLine codebase.LineNumber, endLine codebase.LineNumber, block []string) *Replace {
	return &Replace{
		startLine: startLine,
		endLine:   endLine,
		block:     block,
	}
}
