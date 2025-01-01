package alerts

import (
	"regexp"

	"github.com/github/turboscan/ts"
)

type classifier struct {
	reason string
	re     *regexp.Regexp
}

var classifiers = []*classifier{
	{reason: "generated", re: regexp.MustCompile("(^|/)gen/")},
	{reason: "generated", re: regexp.MustCompile("(^|/)generated")},
	{reason: "generated", re: regexp.MustCompile("(^|/).generated")},
	{reason: "generated", re: regexp.MustCompile(`[^-.]*[-.]min([-.].*)?\.(js|jsx|mjs|ts|tsx|es|es6)$`)}, // minified JavaScript
	{reason: "generated", re: regexp.MustCompile(`(^|/)obj/(Release|Debug)/`)},                           // .Net object files

	{reason: "test", re: regexp.MustCompile("__tests__")},
	{reason: "test", re: regexp.MustCompile("(^|/)test|test_?case")},
	{reason: "test", re: regexp.MustCompile("(^|/)benchmark/")},
	{reason: "test", re: regexp.MustCompile("(^|/)benchmarks/")},
	{reason: "test", re: regexp.MustCompile("(^|/)spec/")},  // RSpec
	{reason: "test", re: regexp.MustCompile(`\.spec\.ts$`)}, // TypeScript specs
	{reason: "test", re: regexp.MustCompile(`\.Test(s?)/`)}, // .Net Tests
	{reason: "test", re: regexp.MustCompile(`_test\.go$`)},  // Go tests

	{reason: "library", re: regexp.MustCompile("(^|/)third-party/")},
	{reason: "library", re: regexp.MustCompile("(^|/)third_party/")},
	{reason: "library", re: regexp.MustCompile("(^|/)thirdparty/")},
	{reason: "library", re: regexp.MustCompile("(^|/)external/")},
	{reason: "library", re: regexp.MustCompile("(^|/)vendor/")},
	{reason: "library", re: regexp.MustCompile("(^|/)3rdparty/")},
	{reason: "library", re: regexp.MustCompile("(^|/)_vendor/")},
	{reason: "library", re: regexp.MustCompile("(^|/)node_modules/")},
	{reason: "library", re: regexp.MustCompile("(^|/)bower_components")},
	{reason: "library", re: regexp.MustCompile(`(^|/).+-\d+\.\d+`)}, // Directories with version numbers in the name such as commons-io-1.5

	{reason: "documentation", re: regexp.MustCompile("(^|/)doc/")},
	{reason: "documentation", re: regexp.MustCompile("(^|/)docs/")},
	{reason: "documentation", re: regexp.MustCompile("(^|/)documentation")},
}

// reason returns the reason for the given path. It returns empty if there is not such a reason
func (c *classifier) getReason(path string) *string {
	if c.re.MatchString(path) {
		return &c.reason
	}
	return nil
}

// classifyFileByPath returns possible reasons why alerts in a file at
// the given path might be less interesting.
func classifyFileByPath(path string) ts.FileClassification {
	result := []string{}
	for _, cf := range classifiers {
		if r := cf.getReason(path); r != nil {
			result = append(result, *r)
		}
	}
	return result
}
