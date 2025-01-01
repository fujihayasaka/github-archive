// Package replacement_block provides logic for handling and replacing code blocks in files.
package replacement_block

import (
	"strconv"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/utils"
)

// ReplacementBlock represents a change in a file (original lines => replacement lines).
type ReplacementBlock struct {
	File             string
	OriginalLines    string
	ReplacementLines string
}

// FromUnifiedDiff parses a unified diff string into a list of ReplacementBlocks.
func FromUnifiedDiff(diff string) ([]ReplacementBlock, error) {
	replacementBlocks := make([]ReplacementBlock, 0)
	var fromFilePath string
	var originalLines []string
	var replacementLines []string
	var originalStartLine, replacementStartLine int
	var err error
	inHunk := false
	diffLines := strings.Split(diff, "\n")
	for i, line := range diffLines[1:] {
		switch {
		// An empty line indicates the end of the diff
		case line == "":
			if i != len(diffLines)-2 {
				return nil, errors.New("unexpected end of diff")
			}
		// Parse the from file to get the file path.
		case strings.HasPrefix(line, "--- a/"):
			parts := strings.SplitN(line, "/", 2)
			if len(parts) < 2 {
				return nil, errors.New("invalid from file path")
			}
			fromFilePath = parts[1]
		// Simply ignore the to file path, we assume the from and to paths are the same.
		case strings.HasPrefix(line, "+++ b/"):
			continue
		// Parse the hunk descriptor to get the start line numbers for the original and replacement lines.
		case strings.HasPrefix(line, "@@") && strings.HasSuffix(line, "@@"):
			{
				if fromFilePath == "" {
					return nil, errors.New("missing from file path")
				}

				// If this is not the first hunk, we need to add the previous hunk to the replacement blocks.
				if inHunk {
					var originalLinesAsString string
					var replacementLinesAsString string

					if len(originalLines) > 0 {
						originalLinesAsString = utils.PrependLineNumbersWithStartLine(strings.Join(originalLines, "\n"), originalStartLine)
					}
					if len(replacementLines) > 0 {
						replacementLinesAsString = utils.PrependLineNumbersWithStartLine(strings.Join(replacementLines, "\n"), replacementStartLine)
					}

					replacementBlocks = append(replacementBlocks, ReplacementBlock{
						File:             fromFilePath,
						OriginalLines:    originalLinesAsString,
						ReplacementLines: replacementLinesAsString,
					})
					originalLines = make([]string, 0)
					replacementLines = make([]string, 0)
				}
				inHunk = true
				// The hunk descriptor is in the format @@ -<original start line>,<original line count> +<replacement start line>,<replacement line count> @@
				hunkDescriptor := strings.TrimPrefix(line, "@@")
				hunkDescriptor = strings.TrimSuffix(hunkDescriptor, "@@")
				hunkDescriptor = strings.TrimSpace(hunkDescriptor)
				// The context is of the format -<original start line>,<original line count> +<replacement start line>,<replacement line count>
				// We split on the space to get the original and replacement start lines.
				hunkRanges := strings.Split(hunkDescriptor, " ")
				if len(hunkRanges) < 2 {
					return nil, errors.New("invalid hunk range specification")
				}
				originalRange := strings.TrimSpace(hunkRanges[0])

				originalStartLine, err = strconv.Atoi(strings.Split(originalRange, ",")[0][1:])
				if err != nil {
					return nil, errors.New("invalid original start line")
				}

				replacementRange := strings.TrimSpace(hunkRanges[1])
				replacementStartLine, err = strconv.Atoi(strings.Split(replacementRange, ",")[0][1:])
				if err != nil {
					return nil, errors.New("invalid replacement start line")
				}
			}
		// If if starts with a '+', it is a replacement line.
		case strings.HasPrefix(line, "+"):
			replacementLines = append(replacementLines, line[1:])
		// If it starts with a '-', it is an original line.
		case strings.HasPrefix(line, "-"):
			originalLines = append(originalLines, line[1:])
		// If it starts with a space, it is a context line.
		case strings.HasPrefix(line, " "):
			originalLines = append(originalLines, line[1:])
			replacementLines = append(replacementLines, line[1:])
		default:
			return nil, errors.New("go unexpected line in diff: " + line)
		}
	}
	// If this is the last hunk, we need to add it to the replacement blocks.
	if inHunk {
		var originalLinesAsString string
		var replacementLinesAsString string

		if len(originalLines) > 0 {
			originalLinesAsString = utils.PrependLineNumbersWithStartLine(strings.Join(originalLines, "\n"), originalStartLine)
		}
		if len(replacementLines) > 0 {
			replacementLinesAsString = utils.PrependLineNumbersWithStartLine(strings.Join(replacementLines, "\n"), replacementStartLine)
		}

		replacementBlocks = append(replacementBlocks, ReplacementBlock{
			File:             fromFilePath,
			OriginalLines:    originalLinesAsString,
			ReplacementLines: replacementLinesAsString,
		})
	}
	return replacementBlocks, nil
}
