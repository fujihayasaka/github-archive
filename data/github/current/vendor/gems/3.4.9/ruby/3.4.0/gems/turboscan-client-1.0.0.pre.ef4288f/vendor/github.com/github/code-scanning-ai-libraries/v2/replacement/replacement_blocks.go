// Package replacement provides logic for handling and replacing code blocks in files.
package replacement

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/codebase"
	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/rendering/snippets"
	"github.com/github/code-scanning-ai-libraries/v2/utils"

	"golang.org/x/text/unicode/norm"
)

// BlockMatch is a block of text matched from the `original lines:` of a replacement block.
type BlockMatch struct {
	// start is the line (1-indexed) in the file where the match starts.
	start codebase.LineNumber
	// end is the line (1-indexed) in the file where the match ends.
	end codebase.LineNumber
	// afterBlock is the corresponding `replacement lines` from the block, which have been adjusted based on the normalizations applied in the `original lines`.
	afterBlock string
	// round is the normalization round used to find the match (lower is less normalization).
	round int
}

// Start returns the start line number of the block match.
func (b *BlockMatch) Start() codebase.LineNumber {
	return b.start
}

// End returns the end line number of the block match.
func (b *BlockMatch) End() codebase.LineNumber {
	return b.end
}

// AfterBlock returns the normalized replacement lines for the block match.
func (b *BlockMatch) AfterBlock() string {
	return b.afterBlock
}

// Round returns the normalization round used to find the match.
func (b *BlockMatch) Round() int {
	return b.round
}

var getIndentationRegex = regexp.MustCompile("^[ \t]*")

// getIndentation returns the leading indentation (spaces/tabs) from a line of text.
func getIndentation(text string) string {
	re := getIndentationRegex
	found := re.FindString(text)
	if found == "" {
		return ""
	}
	return found
}

// abs returns the absolute value of an integer.
func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

// removeLineNumbers strips line numbers from a block of code using the snippets.LineNumberRegex.
func removeLineNumbers(block string) string {
	return snippets.LineNumberRegex.ReplaceAllString(block, "")
}

// applyIndentationMapping applies the given indentation mapping to each line in the block.
func applyIndentationMapping(
	block string,
	indentationMapping map[string]string,
) string {
	blockLines := strings.Split(block, "\n")

	// first, we generalise the indentation mapping: for any indentation t that is
	// mapped to indentation s, we look for all longer indentations t + t' that
	// are not yet mapped, and map them to s + t'

	// all indentations in the block that are not mapped yet
	unmappedBlockIndents := map[string]bool{}
	for _, line := range blockLines {
		indentation := getIndentation(line)
		_, isMapped := indentationMapping[indentation]
		if !isMapped {
			unmappedBlockIndents[indentation] = true
		}
	}

	// all indentations that are already mapped, sorted by decreasing length
	indents := []string{}
	for indentation := range indentationMapping {
		indents = append(indents, indentation)
	}
	sort.SliceStable(indents, func(i, j int) bool {
		return len(indents[i]) > len(indents[j])
	})

	for _, indent := range indents {
		mappedIndent := indentationMapping[indent]
		for otherIndent := range unmappedBlockIndents {
			if strings.HasPrefix(otherIndent, indent) {
				additionalIndent := strings.TrimPrefix(otherIndent, indent)
				mappedOtherIndent := mappedIndent + additionalIndent
				indentationMapping[otherIndent] = mappedOtherIndent
				unmappedBlockIndents[otherIndent] = false
			}
		}
	}

	// now apply the indentation mapping
	for i, line := range blockLines {
		if strings.TrimSpace(line) == "" {
			continue
		}
		indent := getIndentation(line)
		if (indentationMapping[indent]) != "" {
			blockLines[i] = indentationMapping[indent] + strings.TrimPrefix(line, indent)
		}
	}

	return strings.Join(blockLines, "\n")
}

// FindBlockMatch finds where in `fileContents` the block of text `beforeBlock` is located.
// A search is done in multiple rounds, where each round does a different normalization of the text.
// E.g. the indentation might be different between `beforeBlock` and `fileContents` if `beforeBlock` is left-aligned, but we
// can still find a match if we map the indentations in `block` to the indentations in `fileContents`.
//
// The normalizations done to `beforeBlock` are mirrored to `afterBlock`, and returned as part of the result (in `.afterBlock`).
// That way the caller can use the result to replace the block in `fileContents` with `afterBlock`, and the indentation
// will fit to the surrounding code.
//
// The normalization rounds are as follows:
// - round 0: no normalization
// - round 1: normalize indentation by creating a mapping of indentation from `block` to `fileContents`
// - round 2: normalize all whitespace, lowercase, and normalize unicode characters
// - round 3: remove all whitespace
// - round 4: remove empty lines
// - round 5: + remove all semicolons
// - round 6: + handle missing prefix / suffix on first / last line respectively
// - round 7: + ignore first line of original-lines/replace-lines if identical.
// - round 8: + ignore last line of original-lines/replace-lines if identical.
// - round 9: + ignore first/last line of original-lines/replace-lines if identical.
// - round 10: + completely ignore consistency of indentation mapping
//
//nolint:maintidx,cyclop // This function is complex.
func FindBlockMatch(
	beforeBlock string,
	fileContents string,
	afterBlock string,
	shownLines []codebase.LineNumber,
	roundOptional ...int,
) *BlockMatch {
	round := 0
	if len(roundOptional) > 0 {
		round = roundOptional[0]
	}

	if snippets.InitialLineNumberRegex.MatchString(beforeBlock) {
		// recursive with blocks without line numbers
		match := FindBlockMatch(
			removeLineNumbers(beforeBlock),
			fileContents,
			removeLineNumbers(afterBlock),
			shownLines,
			round)
		if match != nil {
			return match
		}
	}

	originalBeforeBlock := beforeBlock
	originalAfterBlock := afterBlock
	originalFileContents := fileContents

	// round 2: lowercase, and normalize unicode characters. (Happens here for performance reasons, so we don't have to do it repeatedly in the loop.)
	if round >= 2 {
		beforeBlock = normalizeCaseAndUnicode(beforeBlock)
		fileContents = normalizeCaseAndUnicode(fileContents)
	}

	// Round 6: Handle common prefixes and suffixes, including ellipses.
	if round >= 6 {
		// First, for the first line, delete any "..." prefix.
		if strings.HasPrefix(afterBlock, "...") && strings.HasPrefix(beforeBlock, "...") {
			afterBlock = afterBlock[3:]
			beforeBlock = beforeBlock[3:]
		}
		// Last line, remove "..." suffix.
		if strings.HasSuffix(afterBlock, "...") && strings.HasSuffix(beforeBlock, "...") {
			afterBlock = afterBlock[:len(afterBlock)-3]
			beforeBlock = beforeBlock[:len(beforeBlock)-3]
		}
	}

	// round 7 and later: remove some lines from before/after block if identical
	if round >= 7 {
		beforeBlockLines := strings.Split(beforeBlock, "\n")
		afterBlockLines := strings.Split(afterBlock, "\n")
		// round 7, or 9 and later: remove first line of original-lines/replace-lines if identical.
		if round != 8 && beforeBlockLines[0] == afterBlockLines[0] {
			beforeBlockLines = beforeBlockLines[1:]
			afterBlockLines = afterBlockLines[1:]
		}
		// round 8 or later: remove last line of original-lines/replacement-lines if identical.
		if round >= 8 &&
			len(beforeBlockLines) > 0 && len(afterBlockLines) > 0 &&
			beforeBlockLines[len(beforeBlockLines)-1] == afterBlockLines[len(afterBlockLines)-1] {
			beforeBlockLines = beforeBlockLines[:len(beforeBlockLines)-1]
			afterBlockLines = afterBlockLines[:len(afterBlockLines)-1]
		}
		beforeBlock = strings.Join(beforeBlockLines, "\n")
		afterBlock = strings.Join(afterBlockLines, "\n")
		if strings.TrimSpace(beforeBlock) == "" {
			return nil
		}
	}

	fileLines := strings.Split(fileContents, "\n")
	beforeBlockLines := utils.Filter(strings.Split(beforeBlock, "\n"),
		func(line string) bool {
			// round 4: remove empty lines. Earlier rounds we keep all lines.
			return round < 4 || strings.TrimSpace(line) != ""
		})

	if len(beforeBlockLines) == 0 {
		// No lines left to match, return nil
		return nil
	}

	// round 4: remove leading/trailing empty lines
	// we have to remove leading/trailing lines from afterBlock, otherwise it clashes with the empty line removal from 'beforeBlockLines'.
	if round >= 4 {
		afterBlockLines := strings.Split(afterBlock, "\n")
		for len(afterBlockLines) > 0 && strings.TrimSpace(afterBlockLines[0]) == "" {
			if len(afterBlockLines) > 1 {
				afterBlockLines = afterBlockLines[1:]
			} else {
				afterBlockLines = []string{}
			}
		}
		for len(afterBlockLines) > 0 && strings.TrimSpace(afterBlockLines[len(afterBlockLines)-1]) == "" {
			if len(afterBlockLines) > 1 {
				afterBlockLines = afterBlockLines[:len(afterBlockLines)-1]
			} else {
				afterBlockLines = []string{}
			}
		}
		afterBlock = strings.Join(afterBlockLines, "\n")
	}

	// saving if the beforeBlock is missing a prefix/suffix to match some lines in the file.
	missingPrefix := ""
	missingSuffix := ""

outer:
	for _, fileLineIndex := range shownLines {
		fileLineIndex-- // 1-indexed to 0-indexed
		skippedLines := 0
		indentationMapping := map[string]string{}

		// try to find a match for all the lines in the beforeBlock
		for blockLineIndex := 0; blockLineIndex < len(beforeBlockLines)+skippedLines; blockLineIndex++ {
			beforeBlockLine := strings.TrimSpace(beforeBlockLines[blockLineIndex-skippedLines])
			if len(fileLines) <= int(fileLineIndex)+blockLineIndex {
				// not enough lines left in file, skip to next
				continue outer
			}
			fileLine := strings.TrimSpace(fileLines[int(fileLineIndex)+blockLineIndex])

			if fileLine == "" && beforeBlockLine == "" {
				// empty line in both, continue to next line
				continue
			}

			// round 4: remove empty lines
			if round >= 4 && fileLine == "" && blockLineIndex != 0 {
				// empty line in file, and we're not in the top of the original lines, skip to next
				skippedLines++
				continue
			}

			if round == 0 && beforeBlockLine != fileLine {
				// no normalization, not exact lines, skip
				continue outer
			}

			// round 1: normalize indentation
			beforeBlockIndent := getIndentation(
				beforeBlockLines[blockLineIndex-skippedLines],
			)
			fileLineIndent := getIndentation(
				fileLines[int(fileLineIndex)+blockLineIndex],
			)

			if beforeBlockIndent != fileLineIndent {
				indentation, found := indentationMapping[beforeBlockIndent]
				if found && indentation != fileLineIndent {
					if round <= 9 {
						// round 1-9: indentation mapping must be consistent
						continue outer
					}
					// round 10: potential inconsistent indentation mapping
				}
				indentationMapping[beforeBlockIndent] = fileLineIndent
			}

			// round 6: handle missing prefix / suffix on first / last line respectively
			// this happens before some other normalization, so they don't impact the output
			if round >= 6 {
				// first line, check if we need to add missing prefix
				if blockLineIndex == 0 &&
					strings.HasSuffix(fileLine, beforeBlockLine) &&
					fileLine != beforeBlockLine {
					missingPrefix =
						fileLineIndent + fileLine[:len(fileLine)-len(beforeBlockLine)] // a spurious indentation is added, but that's ok
					beforeBlockLine = fileLine // so we don't skip the line
				}
				// last line, check if we need to add missing suffix
				if blockLineIndex == len(beforeBlockLines)+skippedLines-1 &&
					strings.HasPrefix(fileLine, beforeBlockLine) &&
					fileLine != beforeBlockLine {
					missingSuffix = fileLine[len(beforeBlockLine):]
					beforeBlockLine = fileLine // so we don't skip the line
				}

				// Single line - the beforeBlockLine might be a substring of fileLine (we need to add both a pre/suffix).
				if len(beforeBlockLines) == 1 &&
					strings.Contains(fileLine, beforeBlockLine) &&
					fileLine != beforeBlockLine {
					// Find where beforeBlockLine appears in fileLine
					index := strings.Index(fileLine, beforeBlockLine)
					if index > 0 {
						missingPrefix = fileLineIndent + fileLine[:index]
					}
					if index+len(beforeBlockLine) < len(fileLine) {
						missingSuffix = fileLine[index+len(beforeBlockLine):]
					}
					beforeBlockLine = fileLine // so we don't skip the line
				}
			}

			// round 2: normalize all whitespace
			if round >= 2 {
				blockOfWhitespaceRegex := regexp.MustCompile(`\s+`)
				beforeBlockLine = blockOfWhitespaceRegex.ReplaceAllString(beforeBlockLine, " ")
				fileLine = blockOfWhitespaceRegex.ReplaceAllString(fileLine, " ")
			}

			// round 3: remove all whitespace
			if round >= 3 {
				singleWhitespaceRegex := regexp.MustCompile(`\s`)
				beforeBlockLine = singleWhitespaceRegex.ReplaceAllString(beforeBlockLine, "")
				fileLine = singleWhitespaceRegex.ReplaceAllString(fileLine, "")
			}

			// round 5: remove all semicolons
			if round >= 5 {
				beforeBlockLine = strings.ReplaceAll(beforeBlockLine, ";", "")
				fileLine = strings.ReplaceAll(fileLine, ";", "")
			}

			// check that the lines match (minus indentation, and other normalization)
			if beforeBlockLine != fileLine {
				// no match, skip
				continue outer
			}

			// match, continue to next line
		}

		// all lines matched
		return &BlockMatch{
			start:      1 + fileLineIndex,
			end:        codebase.LineNumber(int(fileLineIndex) + len(beforeBlockLines) + skippedLines),
			afterBlock: missingPrefix + applyIndentationMapping(afterBlock, indentationMapping) + missingSuffix,
			round:      round,
		}
	}
	// we can try again, with a broader set of normalizations
	if round < 10 {
		beforeBlock = originalBeforeBlock
		afterBlock = originalAfterBlock
		fileContents = originalFileContents
		return FindBlockMatch(beforeBlock, fileContents, afterBlock, shownLines, round+1)
	}
	return nil
}

func normalizeCaseAndUnicode(text string) string {
	// Normalize unicode characters
	text = norm.NFKD.String(text)
	// Lowercase the text
	text = strings.ToLower(text)
	// Replace common Unicode punctuation with ASCII equivalents.
	unicodeReplacer := strings.NewReplacer(
		"−", "-", // minus sign
		"–", "-", // en dash
		"—", "-", // em dash
		"‒", "-", // figure dash
		"‐", "-", // hyphen
		"“", "\"", "”", "\"", // curly double quotes
		"‘", "'", "’", "'", // curly single quotes
		"„", "\"", // double low-9 quotation mark
		"«", "\"", "»", "\"", // guillemets
		"‹", "'", "›", "'", // single guillemets
		"…", "...", // ellipsis
		" ", " ", // non-breaking space
		"　", " ", // ideographic space
		"•", "*", // bullet
		"·", "*", // middle dot
		"×", "x", // multiplication sign
		"÷", "/", // division sign
		"≈", "~", // almost equal to
		"≠", "!=", // not equal to
		"≤", "<=", // less than or equal to
		"≥", ">=", // greater than or equal to
		"©", "(c)", // copyright
		"®", "(r)", // registered trademark
		"™", "(tm)", // trademark
	)
	text = unicodeReplacer.Replace(text)
	return text
}

// FindBestBlockMatch finds the best matching block and is a utility function for applyReplacementBlock to use.
func FindBestBlockMatch(
	beforeBlock string,
	fileContents string,
	afterBlock string,
	shownLines []codebase.LineNumber,
) (*BlockMatch, errors.LLMError) {
	matches := []BlockMatch{}

	// Find all possible matches
	for len(shownLines) > 0 {
		match := FindBlockMatch(
			beforeBlock,
			fileContents,
			afterBlock,
			shownLines,
		)
		if match == nil {
			break
		}
		matches = append(matches, *match)
		shownLines = utils.Filter(shownLines, func(line codebase.LineNumber) bool {
			return line > match.start
		})
	}

	if len(matches) == 0 {
		return nil, errors.NewBlockMismatchError(
			"Failed to find original lines in file",
			nil,
			"")
	}

	// If we have a line number to differentiate, use that to find the match closest to the line number
	lineNumberMatch := snippets.InitialLineNumberRegex.FindString(beforeBlock)
	if lineNumberMatch != "" {
		firstLine, err := strconv.Atoi(strings.TrimSuffix(strings.TrimSpace(lineNumberMatch), ":"))
		if err != nil {
			return nil, errors.NewBlockMismatchError(fmt.Sprintf("failed to parse line number in file: %s", lineNumberMatch), err, "")
		}

		type BlockMatchWithDistance struct {
			match    BlockMatch
			distance int
		}
		closestMatches := []BlockMatchWithDistance{}
		for _, match := range matches {
			closestMatches = append(closestMatches, BlockMatchWithDistance{
				match:    match,
				distance: abs(int(match.start) - firstLine),
			})
		}

		sort.SliceStable(closestMatches, func(i, j int) bool {
			return closestMatches[i].distance < closestMatches[j].distance
		})
		closestDistance := closestMatches[0].distance

		// Keep only matches with the closest distance
		matches = []BlockMatch{}
		for _, matchWithDistance := range closestMatches {
			if matchWithDistance.distance == closestDistance {
				matches = append(matches, matchWithDistance.match)
			}
		}
	}

	// Select the match using the least rounds of normalization
	minRoundsMatch := matches[0]
	for _, match := range matches {
		if match.round < minRoundsMatch.round {
			minRoundsMatch = match
		}
	}

	matches = utils.Filter(matches, func(match BlockMatch) bool {
		return match.round == minRoundsMatch.round
	})

	if len(matches) > 1 {
		return &matches[0], errors.NewBadModelOutputError(fmt.Sprintf("multiple matches for the original lines: %v", matches), nil)
	}

	return &matches[0], nil
}

// SplitNonConsecutiveLines splits a block that contains code with line numbers into blocks of consecutive lines.
//
// E.g. for the code
//
//	1: some code
//	2: some more code
//	5: other code
//
// The result will be ["1: some code\n2: some more code", "5: other code"]
func SplitNonConsecutiveLines(block string) ([]string, errors.LLMError) {
	lines := strings.Split(block, "\n")
	result := []string{}
	currentBlock := ""
	previousLineNumber := 0

	for i, line := range lines {
		match := snippets.InitialLineNumberRegex.FindString(line)
		if match == "" {
			// if any line without a line number is found, return the original block.
			return []string{block}, nil
		}

		lineNumber, err := strconv.Atoi(strings.TrimSuffix(strings.TrimSpace(match), ":"))
		if err != nil {
			return nil, errors.NewParsingError(
				fmt.Sprintf("failed to parse line number in block: %s", match),
				err,
			)
		}

		// Check if current line is consecutive.
		if lineNumber == previousLineNumber+1 || i == 0 {
			if currentBlock != "" {
				currentBlock += "\n"
			}
			currentBlock += line
		} else {
			// Not consecutive, push the current block to result and start a new one.
			result = append(result, currentBlock)
			currentBlock = line
		}
		previousLineNumber = lineNumber
	}

	// Don't forget to add the last block.
	if currentBlock != "" {
		result = append(result, currentBlock)
	}

	return result, nil
}

// IsEllipsis returns whether a line matches a known ellipsis pattern for a line of code
func IsEllipsis(line string) bool {
	ellipsisCandidates := []string{
		"...",
		"[...]",
		"// ...",
		"// [...]",
		"# ...",
		"# [...]",
	}
	lineTrim := strings.TrimSpace(line)
	return utils.Some(ellipsisCandidates, func(ellipsis string) bool { return lineTrim == ellipsis })
}

// SplitOnEllipses splits a block of text into segments separated by ellipses.
func SplitOnEllipses(block string) []string {
	lines := strings.Split(block, "\n")
	res := []string{""}
	for _, line := range lines {
		if IsEllipsis(line) {
			res = append(res, "")
		} else {
			res[len(res)-1] += line + "\n"
		}
	}

	for i := range res {
		if res[i] != "" {
			res[i] = strings.TrimSuffix(res[i], "\n")
		}
	}

	// filter out empty regions, e.g. if the block starts/ends with an ellipsis
	return utils.Filter(res, func(region string) bool { return region != "" })
}
