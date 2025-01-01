package utils

import "regexp"

// RegexReplaceFunc replaces each match of a regular expression with the result of a function.
// The function is called with the match and should return the replacement string.
func RegexReplaceFunc(str string, re *regexp.Regexp, repl func(group []string) (string, error)) (string, error) {
	result := ""
	// use FindAllStringSubmatchIndex to build up the result.
	prevEnd := 0
	for _, loc := range re.FindAllStringSubmatchIndex(str, -1) {
		start, end := loc[0], loc[1]
		// append the text before the match.
		result += str[prevEnd:start]
		// append the replacement for this match.
		match := make([]string, 0, len(loc)/2)
		for i := 0; i < len(loc); i += 2 {
			match = append(match, str[loc[i]:loc[i+1]])
		}
		replacement, err := repl(match)
		if err != nil {
			return "", err
		}
		result += replacement
		prevEnd = end
	}
	// append the text after the last match.
	result += str[prevEnd:]
	return result, nil
}
