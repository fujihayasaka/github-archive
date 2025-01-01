// Package tags implements a way to clean up tags for use in Datadog.
package tags

import "regexp"

// keep only characters allowed by datadog: https://docs.datadoghq.com/getting_started/tagging/
var datadogForbiddenChars = regexp.MustCompile("[^A-Za-z0-9.]+")

// make sure that the first character is a letter.
var datadogAllowedStartingChars = regexp.MustCompile("^[A-Za-z]")

// remove trailing punctuations so that tags doesn't end on `_`.
var trailingPunctuations = regexp.MustCompile("[^A-Za-z0-9.]+$")

// CleanTag cleans up a string, keeping only characters allowed by datadog:
// https://docs.datadoghq.com/getting_started/tagging/
func CleanTag(s string) string {
	s = trailingPunctuations.ReplaceAllString(s, "")
	s = datadogForbiddenChars.ReplaceAllString(s, "_")

	// This is a safety measure that shouldn't be needed, however we want to be cautious here.
	if ok := datadogAllowedStartingChars.MatchString(s); !ok {
		return "tag_" + s
	}

	return s
}
