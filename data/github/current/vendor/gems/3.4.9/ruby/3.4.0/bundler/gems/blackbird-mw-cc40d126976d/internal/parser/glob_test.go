package parser

import (
	"regexp"
	"testing"

	"github.com/stretchr/testify/require"
)

func assertMatch(t *testing.T, pattern string, content string) {
	t.Helper()
	rs := ConvertGlobToRegex(pattern)
	re, err := regexp.Compile(rs)
	require.NoError(t, err, "ConvertGlobToRegex produced invalid regexp")
	require.True(t, re.Match([]byte(content)), "no match for glob %q converted to regex %q", pattern, re)
}

func assertNoMatch(t *testing.T, pattern string, content string) {
	t.Helper()
	rs := ConvertGlobToRegex(pattern)
	re, err := regexp.Compile(rs)
	require.NoError(t, err, "ConvertGlobToRegex produced invalid regexp")
	require.False(t, re.Match([]byte(content)), "unexpected match for glob %q converted to regex %q", pattern, re)
}

func TestConvertGlob(t *testing.T) {
	require.Equal(t, "(^|/)[^/]*\\.js$", ConvertGlobToRegex("*.js"))
	require.Equal(t, "^src/.*/[^/]*\\.js$", ConvertGlobToRegex("/src/**/*.js"))

	// Leading **/ should match start or any number of dirs
	require.Equal(t, ".*(^|/)test\\.js$", ConvertGlobToRegex("**/test.js"))
}

func TestGlobMatch(t *testing.T) {
	assertMatch(t, "*.min.js", "http://google.com/search.min.js")

	assertNoMatch(t, "*.min.js", "http://google.com/search.min.js.com")

	assertMatch(t, "c*linwm", "colinwm")
	assertMatch(t, "c?linwm", "colinwm")
	assertMatch(t, "colin??", "colinwm")

	assertNoMatch(t, "colin?", "colinwm")

	assertMatch(t, "*/js/*.js", "src/js/utils.js")
	assertNoMatch(t, "*/js/*.js", "src/js/app/utils.js")

	assertNoMatch(t, "*/*.js", "src/app.jsx")
	assertNoMatch(t, "src/*/*.js", "src/js/lib/module.js")

	assertMatch(t, "asdf$)/*/*.js", "asdf$)/lib/module.js")

	assertMatch(t, "/src/**/*.js", "src/js/utils.js")
	assertNoMatch(t, "/src/*.js", "/src/js/utils.js")
}

func TestGlobMatchWithEscaping(t *testing.T) {
	assertMatch(t, "my_crazy_\\*_file", "my_crazy_*_file")
	assertNoMatch(t, "my_crazy_\\*_file", "my_crazy_weird_file")

	assertMatch(t, "file_with_qmark\\?", "file_with_qmark?")
	assertNoMatch(t, "file_with_qmark\\?", "file_with_qmark+")

	assertMatch(t, "file_with_backslash\\\\", "file_with_backslash\\")
}

func TestGlobAnchoring(t *testing.T) {
	assertMatch(t, "/*.txt", "file.txt")
	assertNoMatch(t, "/*.txt", "src/file.txt")

	assertMatch(t, "**/*.txt", "src/file.txt")
	assertMatch(t, "**/file.txt", "src/file.txt")

	// Don't anchor at start unless prefixed with /
	assertMatch(t, "test/**/file.txt", "src/test/zzz/file.txt")
	assertNoMatch(t, "/test/**/file.txt", "src/test/zzz/file.txt")
}

func TestGlobUnicode(t *testing.T) {
	assertMatch(t, "/你好吗*.txt", "你好吗text.txt")
	assertMatch(t, "*.txt", "你好世界/file.txt")
	assertMatch(t, "/**/*.txt", "你好世界/file.txt")
}

func TestGlobAdditionalCases(t *testing.T) {
	assertMatch(t, "blackbird*", "github/blackbird-fe")
	assertNoMatch(t, "blackbird*", "github/fe-blackbird")

	assertMatch(t, "git*/*-search", "github/code-search")
	assertMatch(t, "git*/*-search", "git/blackbird-search")
	assertNoMatch(t, "git*/*-search", "hubgit/blackbird-search")
	assertNoMatch(t, "git*/*-search", "hubgit/blackbird-search-string")

	assertMatch(t, "**/filename.txt", "filename.txt")
	assertMatch(t, "**/filename.txt", "a/filename.txt")
	assertMatch(t, "**/filename.txt", "a/b/filename.txt")
	assertNoMatch(t, "**/filename.txt", "a/b/cfilename.txt")
}
