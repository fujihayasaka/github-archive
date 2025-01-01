//nolint:revive,stylecheck // Adding comments for the sake of adding comments is not useful
package prompt

import (
	"errors"
	"sort"
	"unicode/utf8"

	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/model"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/utils"
)

func prependLineNumbers(code string) string {
	return utils.PrependLineNumbersWithStartLine(code, 1)
}

func generateCodeSnippetsForPrompt(files []file, modelParameters *model.ModelParameters) ([]codeSnippet, bool, error) {
	maxCodeTokens := modelParameters.MaxPromptTokens - modelParameters.ReservedPromptTokens
	if maxCodeTokens <= 0 {
		return nil, false, errors.New("max prompt tokens must be greater than reserved tokens")
	}

	maxRunes := maxCodeTokens * modelParameters.CharactersPerToken
	if maxRunes <= 0 {
		return nil, false, errors.New("max code tokens must be greater than zero")
	}
	isTruncated := false

	// This implementation follows the Python version by computing the total number of characters across all relevant files,
	// before prepending line numbers. The distribution of the overflow differs and is done per file, based on the proportion of characters in each file.
	totalRunesInAllFiles := 0
	for _, file := range files {
		totalRunesInAllFiles += utf8.RuneCountInString(file.Content)
	}

	codeSnippets := make([]codeSnippet, len(files))
	overflow := totalRunesInAllFiles - maxRunes
	if overflow > 0 {
		isTruncated = true

		// Compute a weighted truncation per file.
		truncateCountPerFile := make([]int, len(files))
		totalTruncateCount := 0
		for i, file := range files {
			// Because the truncation length is a fraction of the content length and overflow < totalCodeChars, it is guaranteed that
			// truncateLen < len(file.Content).
			truncateCount := utf8.RuneCountInString(file.Content) * overflow / totalRunesInAllFiles
			truncateCountPerFile[i] = truncateCount
			totalTruncateCount += truncateCount
		}
		// Because the truncation length is computed as a proportion of the total characters, it may not sum up to the exact overflow.
		// However, any remaining overflow is guaranteed to be less than the number of files, so we can distribute it evenly across the files.
		remainingOverflow := overflow - totalTruncateCount
		if remainingOverflow > 0 {
			// Distribute the remaining overflow evenly across the files, starting with the largest files.
			sortedIndices := make([]int, len(files))
			for i := range files {
				sortedIndices[i] = i
			}
			sort.Slice(sortedIndices, func(i, j int) bool {
				return utf8.RuneCountInString(files[sortedIndices[i]].Content) > utf8.RuneCountInString(files[sortedIndices[j]].Content)
			})

			for _, idx := range sortedIndices {
				if remainingOverflow == 0 {
					break
				}

				truncateCountPerFile[idx]++
				remainingOverflow--
			}
		}

		for i := range files {
			codeSnippets[i].File = files[i]

			originalRuneCount := utf8.RuneCountInString(files[i].Content)
			contentAsRunes := []rune(prependLineNumbers(files[i].Content))
			runesToKeep := originalRuneCount - truncateCountPerFile[i]

			codeSnippets[i].Content = string(contentAsRunes[:runesToKeep])
		}
	} else {
		for i := range files {
			codeSnippets[i].File = files[i]
			codeSnippets[i].Content = prependLineNumbers(files[i].Content)
		}
	}

	return codeSnippets, isTruncated, nil
}
