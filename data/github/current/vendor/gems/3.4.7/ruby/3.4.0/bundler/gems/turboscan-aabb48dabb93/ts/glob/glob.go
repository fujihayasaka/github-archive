// Package glob implements glob to regex conversion.
package glob

import (
	"regexp"
	"strings"

	"github.com/github/turboscan/ts/transforms"
)

var escapedDoubleStarComponent = regexp.MustCompile(`\\\*\\\*/`)
var escapedStar = regexp.MustCompile(`\\\*`)
var escapedQuestion = regexp.MustCompile(`\\\?`)
var leadingSlash = regexp.MustCompile(`^/`)

// GlobToRegex converts a [CODEOWNERS glob pattern](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners#codeowners-syntax) to a regular expression.
func GlobToRegex(glob string, anchor bool) string {
	regex := regexp.QuoteMeta(glob)
	regex = escapedDoubleStarComponent.ReplaceAllLiteralString(regex, `(?:.*|)`)
	regex = escapedStar.ReplaceAllLiteralString(regex, `[^/]*`)
	regex = escapedQuestion.ReplaceAllLiteralString(regex, `[^/]`)
	if leadingSlash.MatchString(regex) {
		regex = leadingSlash.ReplaceAllLiteralString(regex, "")
	} else {
		regex = "(?:.*/)?" + regex
	}
	pathComponents := strings.Split(glob, "/")
	// If the glob ends with what looks like a file extension match, we don't want to match directories.
	// This is a bit of a deviation from the standard glob behavior, but it makes the language filter faster and more accurate.
	if len(pathComponents) == 0 || !strings.Contains(pathComponents[len(pathComponents)-1], "*.") {
		regex += "(?:/.*)?"
	}
	if anchor {
		regex = "^" + regex + "$"
	}
	return regex
}

var simpleGlobPattern = regexp.MustCompile(`^\*\.[._a-zA-Z0-9]+$`)

// GlobsToRegexes converts a slice of glob patterns to a regular expression that matches any of them.
func GlobsToRegexes(globs []string) string {
	// put all the simple *.ext globs into a bucket and process them separately
	// MySQL struggles to match large numbers of regexps and grouping these allows us to check them all in one go
	partitions := transforms.GroupBy(globs, simpleGlobPattern.MatchString)

	regexes := make([]string, 0, len(globs))

	if len(partitions[true]) > 0 {
		segments := strings.Join(transforms.Map(partitions[true], func(glob string) string {
			return regexp.QuoteMeta(strings.TrimPrefix(glob, "*."))
		}), "|")
		regexes = append(regexes, `(?:.*/)?[^/]*\.(?:`+segments+`)`)
	}

	// build every other pattern the hard way
	for _, glob := range partitions[false] {
		regexes = append(regexes, GlobToRegex(glob, false))
	}

	return "^(?:" + strings.Join(regexes, "|") + ")$"
}
