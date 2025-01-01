// Package text implements text sanitization.
package text

import (
	"strings"
	"unicode"

	"html"

	"github.com/microcosm-cc/bluemonday"
	"github.com/russross/blackfriday/v2"
)

var maxLength = 500

// Sanitize sanitizes the given text.
func Sanitize(text string) string {
	var tagsPolicy = bluemonday.StripTagsPolicy()

	sanitized := string(blackfriday.Run([]byte(text)))
	sanitized = strings.TrimSpace(sanitized)
	sanitized = tagsPolicy.Sanitize(sanitized)
	sanitized = html.UnescapeString(sanitized)

	ellipsis := " …"

	// truncate to the last space before max length
	if len(sanitized) > maxLength {
		sanitized = sanitized[:(maxLength - len(ellipsis))]
		lastSpaceIndex := strings.LastIndexFunc(sanitized, unicode.IsSpace)
		if lastSpaceIndex > -1 {
			sanitized = sanitized[:lastSpaceIndex] + ellipsis
		}
	}
	return sanitized
}
