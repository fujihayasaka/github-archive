// Package preambler provides methods for extracting a preamble from a file.
// It includes functionality to count lines of code, extract preambles, and handle comments.
package preambler

import (
	"regexp"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/codebase"
	"github.com/github/code-scanning-ai-libraries/v2/rendering/indentation"
	"github.com/github/code-scanning-ai-libraries/v2/utils"
)

// blockComments is a map of start to end block comment markers.
var blockComments = map[string]string{
	"/*":  "*/",
	`"""`: `"""`,
	"'''": "'''",
}

// blockCommentRegex is a regex for matching block comments.
var blockCommentRegex = regexp.MustCompile(`(?s)/\*.*\*/`)

// commentLineRegex is a regex for matching comment lines.
var commentLineRegex = regexp.MustCompile(`^(//|/\*|#)`)

// importMarker is a regex for matching import markers.
var importMarker = regexp.MustCompile(`\b(import|include|using|package|require\s*\()\b`)

// MinPreambleLines is the minimum number of lines to consider for a preamble
const MinPreambleLines = 10

// CountLOC counts the number of LOC (non-comment, non-blank lines) in a piece of code.
// We heuristically check for comments by looking for "//", "/*", or "#"
// at the beginning of the line and doing a simple check for block comments.
func CountLOC(code string) int {
	var expectedEndComment string
	lines := strings.Split(code, "\n")
	outCount := 0

	for _, line := range lines {
		line = blockCommentRegex.ReplaceAllString(line, "")
		line = strings.TrimSpace(line)
		if expectedEndComment == "" {
			for start, end := range blockComments {
				if strings.HasPrefix(line, start) {
					expectedEndComment = end
					break
				}
			}
		} else if strings.Contains(line, expectedEndComment) {
			isJustEndComment := line == expectedEndComment
			expectedEndComment = ""
			if isJustEndComment {
				continue
			}
		}
		if expectedEndComment == "" && line != "" && !commentLineRegex.MatchString(line) {
			outCount++
		}
	}
	return outCount
}

// ExtractPreamble extracts the first few lines of `file` as a `ContextLines`.
//
//	This extraction works in two phases:
//	1. We look for the first 10 LOC. This is to
//	   establish a minimum size for the preamble.
//	2. We parse the file into an indentation tree, and look for the first subtree
//	   (after the first 10 lines) that has indentation more than 2 spaces or 1 tab,
//	   or that doesn't have the word `import`/`include`/`package` in it.
//	   This usually indicates a function, or other complex structure, and we
//	   end the preamble there.
//
//	In the last phase we add 2 extra lines to the preamble.
//	That way the model hopefully sees all the imports, but it also sees that the import section has ended.
func ExtractPreamble(fileContents string, minLines int) []codebase.ContextLines {
	if minLines <= 0 {
		minLines = MinPreambleLines
	}

	preambleRegion := codebase.LineRegion{
		StartLine: 1,
		EndLine:   codebase.LineNumber(minLines),
	}
	lines := strings.Split(fileContents, "\n")

	// # Phase one: make sure we have at least 10 LOC.
	for CountLOC(codebase.ReadLineRegion(fileContents, preambleRegion)) < minLines &&
		int(preambleRegion.EndLine) < len(lines) {
		preambleRegion.EndLine++
	}

	// Remember where we ended phase one. preambleRegion gets modified, so this matters.
	endPhaseOneRegion := preambleRegion.EndLine

	tree := indentation.NewIndentationTreeFromFile(fileContents)

	// Phase two: look at indentation, trying to find where the imports stop.
	for _, sub := range tree.TopNodes {
		subStart := sub.StartLine
		subEnd := sub.EndLine

		if subEnd <= endPhaseOneRegion || emptySubtree(*sub, lines) {
			// no or minimal indentation => still "preamble"
			preambleRegion.EndLine = max(subEnd+2, preambleRegion.EndLine)
			continue
		}

		// if this subtree has more indentation than 2 spaces or 1 tab, then we stop here.
		// unless the following line or the first line includes "import". then we keep going.
		if hasComplexIndentation(*sub, lines) &&
			!(checkImportMarker(lines, subStart-1) ||
				checkImportMarker(lines, subEnd)) {
			// stop now
			break
		}

		// if this subtree doesn't have `import`/`include`, then we stop here.
		if !anyLineMatches(*sub, lines, importMarker) {
			// no import => stop
			break
		}
		// else, we keep going.
		// plus 2, to give some context about how the program continues.
		preambleRegion.EndLine = subEnd + 2
	}

	finalRegions := elideTopMultilineComment(preambleRegion, fileContents)
	result := utils.Map(finalRegions, func(r codebase.LineRegion) codebase.ContextLines {
		return codebase.NewContextLines(r, fileContents)
	})

	return result
}

// elideTopMultilineComment searches for a multiline comment block (or sequence of single-line comments) in the start of the file (and within `region`).
// If such a multiline comment block is found, two regions are returned that remove the middle of the comment block.
func elideTopMultilineComment(
	preambleRegion codebase.LineRegion,
	fileContents string,
) []codebase.LineRegion {
	if preambleRegion.StartLine != 1 {
		panic("Expected preambleRegion.StartLine to be 1")
	}

	lines := strings.Split(fileContents, "\n")
	startLine := int(preambleRegion.StartLine)
	endLine := int(preambleRegion.EndLine)

	// Possibly elide a large single‐line comment block (≥6 lines of "//", "#" or blank)

	lastCommentLine := -1 // zero-indexed
	for i := 0; i < min(len(lines), endLine); i++ {
		trim := strings.TrimSpace(lines[i])
		if !(trim == "" || strings.HasPrefix(trim, "//") || strings.HasPrefix(trim, "#")) {
			break
		}
		lastCommentLine = i
	}
	if lastCommentLine > 5 {
		// return two regions: one before the comment block (with two extra lines after), and one after the comment block (with two extra lines before).
		return []codebase.LineRegion{
			{
				StartLine: codebase.LineNumber(startLine),
				EndLine:   codebase.LineNumber(startLine + 2),
			},
			{
				StartLine: codebase.LineNumber(max(1, lastCommentLine-2)),
				EndLine:   preambleRegion.EndLine,
			},
		}
	}

	// Possibly elide a large multi‐line block comment, e.g. /* ... */, """...""", '''...'''.
	commentPairs := [][2]string{
		{"/*", "*/"},
		{`"""`, `"""`},
		{"'''", "'''"},
	}

	trimmedFirst := strings.TrimSpace(lines[0])

	matchedEnd := -1
	for _, pair := range commentPairs {
		openTag, closeTag := pair[0], pair[1]
		if strings.HasPrefix(trimmedFirst, openTag) {
			// If both open + close exist on line 0, it’s a single line => no big block
			if strings.Contains(trimmedFirst[len(openTag):], closeTag) {
				break
			}
			// Else find the line that ends with closeTag
			for i := 1; i < min(len(lines), endLine); i++ {
				if strings.HasSuffix(strings.TrimSpace(lines[i]), closeTag) {
					matchedEnd = i + 1 // region indices are 1-based
					break
				}
			}
			break
		}
	}
	if matchedEnd == -1 {
		// No big block
		return []codebase.LineRegion{preambleRegion} // no match.
	}

	// return two regions: one before the comment block (with two extra lines after), and one after the comment block (with two extra lines before).
	return []codebase.LineRegion{
		{
			StartLine: codebase.LineNumber(startLine),
			EndLine:   codebase.LineNumber(startLine + 2),
		},
		{
			StartLine: codebase.LineNumber(max(1, matchedEnd-2)),
			EndLine:   preambleRegion.EndLine,
		},
	}
}

// checkImportMarker checks if the line at the given index matches the given marker.
func checkImportMarker(lines []string, index codebase.LineNumber) bool {
	i := int(index)
	if i < 0 || i >= len(lines) {
		return false
	}
	return importMarker.MatchString(lines[i])
}

// anyLineMatches checks if any line in the subtree matches the given marker.
func anyLineMatches(sub indentation.IndentationTreeNode, lines []string, marker *regexp.Regexp) bool {
	for _, l := range indentation.LinesInTree(&sub, lines) {
		if marker.MatchString(l) {
			return true
		}
	}
	return false
}

// hasComplexIndentation checks if the subtree has complex indentation.
func hasComplexIndentation(tree indentation.IndentationTreeNode, lines []string) bool {
	for _, line := range indentation.LinesInTree(&tree, lines) {
		indent := utils.GetIndentation(line)
		if indent != "" && indent != " " && indent != "  " && indent != "\t" {
			return true
		}
	}
	return false
}

// emptySubtree checks if the subtree is empty.
func emptySubtree(tree indentation.IndentationTreeNode, lines []string) bool {
	snippet := strings.Join(indentation.LinesInTree(&tree, lines), "\n")
	return strings.TrimSpace(snippet) == ""
}
