package codebase

// Provides types and functions for representing
// locations of alerts and their surrounding context in source code.
//
// The file defines region types for handling both line-based and
// column-based selections, as well as utilities for reading and
// manipulating these regions.
import (
	"strings"

	"github.com/github/codeml-autofix/go/pkg/autofix/sarif/v210autofix"
)

// LineNumber represents a 1-based line number in a file
type LineNumber int

// ColumnNumber represents a 1-based column number in a file
type ColumnNumber int

// LineRegion represents a range of complete lines in a file
// For example: lines 1-3 would include all characters in those lines
type LineRegion struct {
	// File is the file containing the region.
	File File
	// StartLine is the line number of the first line in the region.
	StartLine LineNumber
	// EndLine is the line number of the last line in the region.
	EndLine LineNumber
}

func (lr LineRegion) read(contents string) string {
	return ReadLineRegion(contents, lr)
}

// Region extends LineRegion to handle partial line selections via columns.
// A range of characters in a file, possibly spanning multiple lines and
// possibly starting or ending in the middle of a line.

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

func (c ContextLines) Contexts() []ContextLines {
	return []ContextLines{c}
}

func (c ContextLines) File() File {
	return c.LineRegion.File
}

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

// SourceLocation represents a region for tracking the location of an alert.
type SourceLocation struct {
	File        File
	SarifRegion v210autofix.Region
	Text        string
}

// NewSourceLocationWithContent creates a SourceLocation with its text content populated.
// This is a two-step process:
//  1. Create a temporary location to get coordinates (via NewSourceLocation)
//  2. Read the actual content using those coordinates
//
// For example, given a SARIF region that points to:
//   - Lines 10-12
//   - Columns 5-20
//
// This will:
//  1. Create empty SourceLocation to get those coordinates
//  2. Read the actual text content from the file at those coordinates
//  3. Return a new SourceLocation with both coordinates and content
//
// Parameters:
//   - file: The source file to read from
//   - sarifRegion: SARIF region containing line/column coordinates
//
// Returns:
//   - SourceLocation: Location with populated text content
//   - error: If file reading fails
func NewSourceLocationWithContent(file File, sarifRegion v210autofix.Region) (SourceLocation, error) {
	// Create fake location to get initial location
	fakeLoc := NewSourceLocation(file, sarifRegion)

	region := Region{
		LineRegion: LineRegion{
			File:      file,
			StartLine: fakeLoc.StartLine(),
			EndLine:   fakeLoc.EndLine(),
		},
		StartColumn: fakeLoc.StartColumn(),
		EndColumn:   fakeLoc.EndColumn(),
	}

	// Read with columns
	text, err := file.ReadWithColumns(region)
	if err != nil {
		return SourceLocation{}, err
	}

	return SourceLocation{
		File:        file,
		SarifRegion: sarifRegion,
		Text:        text,
	}, nil
}

// NewSourceLocation creates a new SourceLocation instance.
// first create a fake location, which gives us start/end line/column
func NewSourceLocation(file File, sarifRegion v210autofix.Region) SourceLocation {
	return SourceLocation{
		File:        file,
		SarifRegion: sarifRegion,
		Text:        "",
	}
}

// StartLine returns the start line of the region.
func (sl SourceLocation) StartLine() LineNumber {
	return LineNumber(sl.SarifRegion.StartLine)
}

// StartColumn returns the start column of the region.
func (sl SourceLocation) StartColumn() ColumnNumber {
	return ColumnNumber(sl.SarifRegion.StartColumn)
}

// EndLine returns the end line of the region.
func (sl SourceLocation) EndLine() LineNumber {
	if sl.SarifRegion.EndLine == 0 {
		return sl.StartLine()
	}
	return LineNumber(sl.SarifRegion.EndLine)
}

// EndColumn returns the end column of the region.
// TODO: Address SARIF compliance as per https://github.com/github/codeml-autofix/issues/1562
func (sl SourceLocation) EndColumn() ColumnNumber {
	return ColumnNumber(sl.SarifRegion.EndColumn)
}

// Includes checks if this location includes the given location.
func (sl SourceLocation) Includes(other SourceLocation) bool {
	if !sl.File.Equals(other.File) {
		return false
	}
	startsBefore := sl.StartLine() < other.StartLine() ||
		(sl.StartLine() == other.StartLine() && sl.StartColumn() <= other.StartColumn())
	endsAfter := sl.EndLine() > other.EndLine() ||
		(sl.EndLine() == other.EndLine() && sl.EndColumn() >= other.EndColumn())
	return startsBefore && endsAfter
}

// Equals checks if this location is equal to the given location.
func (sl SourceLocation) Equals(other *SourceLocation) bool {
	return sl.File.Equals(other.File) &&
		sl.StartLine() == other.StartLine() &&
		sl.StartColumn() == other.StartColumn() &&
		sl.EndLine() == other.EndLine() &&
		sl.EndColumn() == other.EndColumn()
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
