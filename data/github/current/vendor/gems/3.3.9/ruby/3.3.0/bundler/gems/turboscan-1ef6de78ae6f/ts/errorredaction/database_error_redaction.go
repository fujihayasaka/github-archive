// Package errorredaction provides a Gorm hook to find and redact secrets in SQL.
package errorredaction

import (
	"regexp"
	"strings"

	"github.com/pkg/errors"

	"github.com/jinzhu/gorm"
)

// redactionString is the string we replace anything we redact with.
const redactionString = "[REDACTED]"

// minimumRedactionLength specifies the shortest string we will redact. This avoids redacting things like single letters in the error message. It's unlikely data could be shorter than this and also confidential.
const minimumRedactionLength = 4

// ignoredCharactersToRedact is a regex of characters that we will ignore when deciding whether to redact part of a string. By ignoring special characters, we avoid having to care about how the database or Vitess escapes them in error messages.
var ignoredCharactersToRedact = regexp.MustCompile("[^a-zA-Z0-9 ]")

// redactStringForward replaces all prefixes of variable in errorString with redactionString provided they are longer than minimumRedactionLength.
func redactStringForward(errorString string, variable string, redactionString string) string {
	variableWithOnlyCharactersToRedact := ignoredCharactersToRedact.ReplaceAllString(variable, "")
	if len(variableWithOnlyCharactersToRedact) < minimumRedactionLength {
		return errorString
	}

	startIndex := -1
	endIndex := -1
	matchedCharacters := 0
	rangesToReplace := [][]int{}
	variableWithOnlyCharactersToRedactAsRunes := []rune(variableWithOnlyCharactersToRedact)

	// Our outer loop controls where in the error string we start trying to match the variable.
	// This is needed because while matching we may need to backtrack and start matching again from a point in the string before we successfully matched up to.
	// For example, consider the string "aaabbb" and the variable "aabb". From the start of the string, we match the first two characters and fail on the third. At this point we have to backtrack to the second character and try to start the match from there rather than continuing from where we failed.
	for offset := 0; offset < len(errorString); offset++ {
		// Whilst the outer loop iterates through the error string, the inner loop effectively iterates through the variable.
		// It actually looks at the error string instead, because we need to skip ignored characters, but you can think of it as iterating through the variable.
		for index := offset; index < len(errorString); index++ {
			character := rune(errorString[index])
			// If the character is ignored then skip it.
			if ignoredCharactersToRedact.MatchString(string(character)) {
				// This is an optimization that allows us to avoid looking at the same ignored characters multiple times. We never need to backtrack over ignored characters.
				if index == offset {
					break
				}
				continue
			}

			// If we have reached a charater in the variable that is not ignored and doesn't match the error string then we can stop matching.
			if matchedCharacters >= len(variableWithOnlyCharactersToRedactAsRunes) || character != variableWithOnlyCharactersToRedactAsRunes[matchedCharacters] {
				// If we've managed to match a prefix of at least the minimum length, then we can add the range to the list of ranges to redact.
				if matchedCharacters >= minimumRedactionLength && startIndex != -1 {
					rangesToReplace = append(rangesToReplace, []int{startIndex, endIndex})
					// We also can advance the outer loop, since once we've decided to redact something there's no need to backtrack over it.
					offset = endIndex
				}
				// Reset all the state.
				startIndex = -1
				endIndex = -1
				matchedCharacters = 0
				// Break out of the inner loop, to continue looking for more matches later in the error string.
				break
			}

			// If we have a successful character match then we update the state to record this.
			if matchedCharacters < len(variableWithOnlyCharactersToRedactAsRunes) && character == variableWithOnlyCharactersToRedactAsRunes[matchedCharacters] {
				// Set a start index if we're looking at the first character in the variable (i.e. we haven't set a start index already).
				if startIndex == -1 {
					startIndex = index
				}
				// Update the end index.
				endIndex = index
				// Increment the number of matched characters.
				matchedCharacters++
			}
		}
	}
	// If we've reached the end of the string, and we had a match that never ended, we can also redact this.
	if matchedCharacters >= minimumRedactionLength && startIndex != -1 {
		rangesToReplace = append(rangesToReplace, []int{startIndex, endIndex})
	}

	// Now just go and replace the ranges we've decided to redact.
	redactedString := strings.Builder{}
	stopReplaceIndex := 0
	for _, rangeToReplace := range rangesToReplace {
		redactedString.WriteString(errorString[stopReplaceIndex:rangeToReplace[0]])
		redactedString.WriteString(redactionString)
		stopReplaceIndex = rangeToReplace[1] + 1
	}
	redactedString.WriteString(errorString[stopReplaceIndex:])

	return redactedString.String()
}

func reverseString(str string) string {
	runes := []rune(str)
	reversed := []rune{}
	for index := len(runes) - 1; index >= 0; index-- {
		reversed = append(reversed, runes[index])
	}
	return string(reversed)
}

func RedactString(errorString string, variable string) string {
	// First redact the string in the forwards direction.
	redactedError := redactStringForward(errorString, variable, redactionString)
	// Then redact it in reverse. This handles cases where only a suffix of the variable is present in the string.
	redactedError = reverseString(redactStringForward(reverseString(redactedError), reverseString(variable), reverseString(redactionString)))
	return redactedError
}

type RedactedDatabaseError struct {
	redactedError string
	originalError error
}

func (r *RedactedDatabaseError) Error() string {
	return r.redactedError
}

func (r *RedactedDatabaseError) Unwrap() error {
	return r.originalError
}

// DatabaseRedactionCallback is a GORM callback that redacts any query variables from errors returned by GORM.
func DatabaseRedactionCallback(scope *gorm.Scope) {
	if scope.DB().Error == nil || errors.Is(scope.DB().Error, gorm.ErrRecordNotFound) {
		return
	}
	errorString := scope.DB().Error.Error()
	for _, variable := range scope.SQLVars {
		if typedVariable, ok := variable.(string); ok {
			errorString = RedactString(errorString, typedVariable)
		}
	}
	scope.DB().Error = &RedactedDatabaseError{redactedError: errorString, originalError: scope.DB().Error}
}
