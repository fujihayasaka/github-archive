package replacement

import (
	"fmt"
	"strings"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/hexops/gotextdiff"
	"github.com/hexops/gotextdiff/myers"
	"github.com/hexops/gotextdiff/span"
)

// DiffStyle represents different supported diff styles
type DiffStyle string

const (
	// DiffStyleAuto automatically selects the best available style
	DiffStyleAuto DiffStyle = "auto"
	// DiffStyleColor uses ANSI color codes for terminal display
	DiffStyleColor DiffStyle = "color"
	// DiffStylePlain uses plain text formatting
	DiffStylePlain DiffStyle = "plain"
	// DiffStyleGit uses git-style diff formatting
	DiffStyleGit DiffStyle = "git"
	// DiffStyleUnified uses unified diff formatting
	DiffStyleUnified DiffStyle = "unified"
)

// FormatDiff generates a diff with the specified style
func FormatDiff(originalContent, newContent, filePath, style string) (string, error) {
	if originalContent == newContent {
		return "", nil
	}

	// Use the myers algorithm to compute edits
	edits := myers.ComputeEdits(span.URIFromPath(filePath), originalContent, newContent)

	// Format according to the requested style
	switch style {
	case string(DiffStyleUnified):
		diff := gotextdiff.ToUnified(filePath, filePath, originalContent, edits)
		return fmt.Sprint(diff), nil
	case string(DiffStyleGit):
		diff := gotextdiff.ToUnified("a/"+filePath, "b/"+filePath, originalContent, edits)
		return fmt.Sprint(diff), nil
	case string(DiffStyleColor):
		// Generate colored diff for terminal display
		diff := gotextdiff.ToUnified(filePath, filePath, originalContent, edits)
		return ColorDiff(diff), nil
	case string(DiffStylePlain):
		// Use a plain unified diff without prefixes for maximum compatibility
		diff := gotextdiff.ToUnified(filePath, filePath, originalContent, edits)
		return fmt.Sprint(diff), nil
	case string(DiffStyleAuto):
		// Default to git style
		diff := gotextdiff.ToUnified("a/"+filePath, "b/"+filePath, originalContent, edits)
		return fmt.Sprint(diff), nil
	default:
		// Default to git style
		diff := gotextdiff.ToUnified("a/"+filePath, "b/"+filePath, originalContent, edits)
		return fmt.Sprint(diff), nil
	}
}

// ColorDiff adds ANSI color codes to a diff for terminal display
func ColorDiff(diff gotextdiff.Unified) string {
	var b strings.Builder

	// Add file header (hidden, but needed for parsing)
	// revive:disable:unhandled-error // strings.Builder.WriteString always returns a `nil` error.
	b.WriteString("--- ")
	b.WriteString(diff.From)
	b.WriteString("\n+++ ")
	b.WriteString(diff.To)
	b.WriteString("\n")
	// revive:enable:unhandled-error

	// Process each hunk
	for _, hunk := range diff.Hunks {
		// Add hunk header (hidden, but needed for parsing)
		// revive:disable-next-line:unhandled-error // strings.Builder.WriteString always returns a `nil` error.
		b.WriteString(fmt.Sprintf("@@ -%d,%d +%d,%d @@\n",
			hunk.FromLine, countLines(hunk, gotextdiff.Delete)+countLines(hunk, gotextdiff.Equal),
			hunk.ToLine, countLines(hunk, gotextdiff.Insert)+countLines(hunk, gotextdiff.Equal)))

		// Process each line with colored output
		for _, line := range hunk.Lines {
			switch line.Kind {
			case gotextdiff.Delete:
				// Bright red for deleted lines
				// revive:disable:unhandled-error // strings.Builder.WriteString always returns a `nil` error.
				b.WriteString("\033[31m-")
				b.WriteString(line.Content)
				b.WriteString("\033[0m")
				if !strings.HasSuffix(line.Content, "\n") {
					b.WriteString("\n")
				}
				// revive:enable:unhandled-error
			case gotextdiff.Insert:
				// Bright green for added lines
				// revive:disable:unhandled-error // strings.Builder.WriteString always returns a `nil` error.
				b.WriteString("\033[32m+")
				b.WriteString(line.Content)
				b.WriteString("\033[0m")
				if !strings.HasSuffix(line.Content, "\n") {
					b.WriteString("\n")
				}
				// revive:enable:unhandled-error
			default: // Equal
				// Gray for context lines
				// revive:disable:unhandled-error // strings.Builder.WriteString always returns a `nil` error.
				b.WriteString("\033[90m ")
				b.WriteString(line.Content)
				b.WriteString("\033[0m")
				if !strings.HasSuffix(line.Content, "\n") {
					b.WriteString("\n")
				}
				// revive:enable:unhandled-error
			}
		}
	}

	return b.String()
}

// Helper to count lines of a specific kind in a hunk
func countLines(hunk *gotextdiff.Hunk, kind gotextdiff.OpKind) int {
	count := 0
	for _, line := range hunk.Lines {
		if line.Kind == kind {
			count++
		}
	}
	return count
}

// DiffFile creates a diff between the original file and after applying edits
func DiffFile(
	file codebase.File,
	edits editcommands.EditCommands,
	style string,
) (string, error) {
	oldContents, err := file.ReadContents()
	if err != nil {
		return "", err
	}
	newContents := edits.Apply(oldContents)
	if newContents == oldContents {
		return "", nil
	}
	return FormatDiff(oldContents, newContents, file.Path, style)
}

// ParseEditCommandsFromContents parses edit commands from old and new content
func ParseEditCommandsFromContents(oldText, newText string) []editcommands.EditCommand {
	// Normalize line endings again to ensure consistency
	oldText = utils.NormalizeLineEndings(oldText)
	newText = utils.NormalizeLineEndings(newText)
	edits := myers.ComputeEdits(span.URIFromPath("old"), oldText, newText)
	diff := gotextdiff.ToUnified("old", "new", oldText, edits)
	return ParseEditCommandsFromDiff(diff.Hunks)
}

// ParseEditCommandsFromDiff parses edit commands from diff hunks
func ParseEditCommandsFromDiff(hunks []*gotextdiff.Hunk) []editcommands.EditCommand {
	commands := make([]editcommands.EditCommand, 0)

	for _, hunk := range hunks {
		// We want to identify runs of deleted lines followed by runs of added
		// lines (either of which may be empty), and emit an edit command for
		// each such run.
		//
		// To do so, we walk over the lines in the hunk one by one, keeping
		// track of two arrays `deletedLines` and `addedLines`, such that at any
		// point in time the current line in the hunk is preceded by
		// `deletedLines` and `addedLines`, in that order. Either or both of
		// these arrays may be empty.
		//
		// We also keep track of the line in the old file we're currently
		// looking at, meaning the line the next context line or deleted line
		// refers to.
		//
		// Whenever we see a deleted line after an added line, or a context line
		// after a run of deleted or added lines, this means that we have
		// identified a (maximal) run of deleted and added lines, so we emit an
		// edit command for that run.
		//
		// Lines that do not start with `+`, `-`, or ` ` are completely ignored.
		// (This includes lines like `\ No newline at end of file`.)
		curLine := hunk.FromLine - 1
		deletedLines := []string{}
		addedLines := []string{}

		emitCommand := func() {
			// if there are no deleted lines, emit an insertion command
			if len(deletedLines) == 0 {
				// use InsertAfter, except for the first line, where we use InsertBefore
				// curLine tracks the last line number in the original file we've advanced past.
				// At the very start of a hunk (before seeing any context/delete lines), curLine == 0.
				// In that case, a pure insertion should be inserted before line 1. Otherwise, insert after curLine.
				if curLine == 0 {
					commands = append(commands,
						editcommands.NewInsertBefore(codebase.LineNumber(1), addedLines),
					)
				} else {
					commands = append(commands,
						editcommands.NewInsertAfter(codebase.LineNumber(curLine), addedLines),
					)
				}
			} else {
				// otherwise, emit a replace command
				commands = append(commands,
					editcommands.NewReplace(
						codebase.LineNumber(curLine-len(deletedLines)+1),
						codebase.LineNumber(curLine),
						addedLines,
					),
				)
			}
			deletedLines = []string{}
			addedLines = []string{}
		}

		for _, line := range hunk.Lines {
			content := strings.TrimRight(line.Content, "\n")
			switch line.Kind {
			case gotextdiff.Delete:
				if len(addedLines) > 0 {
					emitCommand()
				}
				deletedLines = append(deletedLines, content)
				curLine++
			case gotextdiff.Insert:
				addedLines = append(addedLines, content)
			case gotextdiff.Equal:
				if len(deletedLines) > 0 || len(addedLines) > 0 {
					emitCommand()
				}
				curLine++
			default:
				// ignore other lines
			}
		}
		if (len(deletedLines) > 0) || (len(addedLines) > 0) {
			emitCommand()
		}
	}

	return commands
}
