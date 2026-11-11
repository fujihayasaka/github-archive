package agenticapp

import "regexp"

// matchMentionWithModel strips backtick-enclosed content from body, then
// attempts to match the given mentionWithModel regexp. Returns the captured
// model ID and true when a match is found.
func matchMentionWithModel(body string, re *regexp.Regexp) (string, bool) {
	bodyWithoutBackticks := backtickContentPattern.ReplaceAllString(body, "")

	matches := re.FindStringSubmatch(bodyWithoutBackticks)
	if len(matches) >= 2 {
		return matches[1], true
	}

	return "", false
}
