// Package codebase provides types and helpers for representing source code
// locations and extracting contextual regions from file contents.
package codebase

// Provides types and functions for representing
// locations of alerts and their surrounding context in source code.
//
// The file defines region types for handling both line-based and
// column-based selections, as well as utilities for reading and
// manipulating these regions.
import (
	"strings"
)

// LineNumber represents a 1-based line number in a file
type LineNumber int

// ColumnNumber represents a 1-based column number in a file
type ColumnNumber int

// LineRegion represents a range of complete lines in a file
// For example: lines 1-3 would include all characters in those lines
type LineRegion struct {
	// StartLine is the line number of the first line in the region.
	StartLine LineNumber
	// EndLine is the line number of the last line in the region.
	EndLine LineNumber
}

func (lr LineRegion) read(contents string) string {
	return ReadLineRegion(contents, lr)
}

// Region represents a range of characters in a file, possibly spanning multiple
// lines and possibly starting or ending in the middle of a line.
//
// Region extends LineRegion to handle partial line selections via columns.
//
// For example: From line 1, column 5 to line 3, column 10:
// - First line starts at column 5
// - Middle lines are complete
// - Last line ends at column 10
type Region struct {
	LineRegion
	// StartColumn is the column number of the first character in the region.
	StartColumn ColumnNumber
	// EndColumn is the column number one past the last character in the region.
	EndColumn ColumnNumber
}

func (r Region) read(contents string) string {
	return ReadFullRegion(contents, r)
}

// ContextLines represents a region of lines in a file for tracking context of an alert.
type ContextLines struct {
	LineRegion
	Text         string
	FileContents string
}

// Contexts returns this ContextLines instance in a single-element slice.
func (c ContextLines) Contexts() []ContextLines {
	return []ContextLines{c}
}

// GetFileContents returns the full file contents this context was derived from.
func (c ContextLines) GetFileContents() string {
	return c.FileContents
}

// RegionReader is an interface for reading a region of a file.
type RegionReader interface {
	read(contents string) string
}

// NewContextLines creates a new ContextLines instance.
func NewContextLines(lineRegion LineRegion, fileContents string) ContextLines {
	return ContextLines{
		LineRegion:   lineRegion,
		Text:         ReadLineRegion(fileContents, lineRegion),
		FileContents: fileContents,
	}
}

// readLines extracts the specified line range from content.
// Handles 1-based line numbers and converts to 0-based slice indices
func readLines(content string, startLine, endLine LineNumber) []string {
	lines := strings.Split(content, "\n")
	totalLines := LineNumber(len(lines))

	// Validate and adjust line numbers
	if startLine < 1 {
		startLine = 1
	}
	if endLine > totalLines {
		endLine = totalLines
	}
	if startLine > endLine {
		return []string{}
	}

	// Slicing is zero-based and end-exclusive
	return lines[startLine-1 : endLine]
}

// ReadLineRegion reads full lines specified by LineRegion
func ReadLineRegion(content string, region LineRegion) string {
	lines := readLines(content, region.StartLine, region.EndLine)
	return strings.Join(lines, "\n")
}

// ReadFullRegion reads Region with column-specific slicing
// Handles both single and multi-line regions
func ReadFullRegion(content string, region Region) string {
	lines := readLines(content, region.StartLine, region.EndLine)

	// If StartColumn and EndColumn are zero, return the entire lines
	if region.StartColumn == 0 && region.EndColumn == 0 {
		return strings.Join(lines, "\n")
	}

	// Otherwise, perform column-specific slicing
	return strings.Join(readLinesWithColumns(lines, region.StartColumn, region.EndColumn), "\n")
}

// readLinesWithColumns slices the first and last line based on the start and end columns.
func readLinesWithColumns(lines []string, startCol, endCol ColumnNumber) []string {
	if len(lines) == 0 {
		return lines
	}

	// Convert 1-based columns to 0-based indices
	colStart := int(startCol) - 1
	colEnd := int(endCol) - 1

	if len(lines) == 1 {
		colEnd = max(0, min(colEnd, len(lines[0])))
		colStart = max(0, min(colStart, colEnd))
		lines[0] = lines[0][colStart:colEnd]
		return lines
	}

	colStart = max(0, min(colStart, len(lines[0])))
	lines[0] = lines[0][colStart:]

	colEnd = max(0, min(colEnd, len(lines[len(lines)-1])))
	lines[len(lines)-1] = lines[len(lines)-1][:colEnd]

	return lines
}
