package glob

import (
	"regexp"
	"testing"

	"github.com/stretchr/testify/require"
)

func globToRegex(glob string) *regexp.Regexp {
	return regexp.MustCompile(GlobToRegex(glob, true))
}

func TestGlobsToRegex(t *testing.T) {
	regex1 := GlobsToRegexes([]string{
		"*.js", "*._js", "*.bones", "*.cjs", "*.es", "*.es6", "*.frag", "*.gs", "*.jake", "*.javascript", "*.jsb", "*.jscad", "*.jsfl", "*.jslib", "*.jsm", "*.jspre", "*.jss", "*.jsx", "*.mjs", "*.njs", "*.pac", "*.sjs", "*.ssjs", "*.xsjs", "*.xsjslib",
	})
	pattern := regexp.MustCompile(regex1)
	require.Equal(t, `^(?:(?:.*/)?[^/]*\.(?:js|_js|bones|cjs|es|es6|frag|gs|jake|javascript|jsb|jscad|jsfl|jslib|jsm|jspre|jss|jsx|mjs|njs|pac|sjs|ssjs|xsjs|xsjslib))$`, regex1)
	require.True(t, pattern.MatchString("foo.jss"))
	require.True(t, pattern.MatchString("path/to/foo.jss"))

	regex2 := GlobsToRegexes([]string{
		"*.js", "path/**/to.bones", "*.javascript",
	})
	pattern2 := regexp.MustCompile(regex2)
	require.True(t, pattern2.MatchString("foo.js"))
	require.True(t, pattern2.MatchString("path/foo/to.bones"))
	require.False(t, pattern2.MatchString("to.bones"))
}

func TestGlobToRegex(t *testing.T) {
	regex := globToRegex("*.go")
	require.True(t, regex.MatchString("foo.go"))
	require.True(t, regex.MatchString("path/to/foo.go"))
	require.False(t, regex.MatchString("foo.js"))
	require.False(t, regex.MatchString("path/to/foo.js"))
	require.False(t, regex.MatchString("foo.go/bar"))

	regex = globToRegex("/foo.go")
	require.True(t, regex.MatchString("foo.go"))
	require.False(t, regex.MatchString("path/to/foo.go"))

	regex = globToRegex("foo/*/bat.go")
	require.True(t, regex.MatchString("foo/bar/bat.go"))
	require.False(t, regex.MatchString("foo/bar/baz/bat.go"))

	regex = globToRegex("foo/**/bat.go")
	require.True(t, regex.MatchString("foo/bat.go"))
	require.True(t, regex.MatchString("foo/bar/bat.go"))
	require.True(t, regex.MatchString("foo/bar/baz/bat.go"))

	regex = globToRegex("foo/**")
	require.True(t, regex.MatchString("foo/bat.go"))
	require.True(t, regex.MatchString("foo/bar/bat.go"))

	regex = globToRegex("foo/**/")
	require.True(t, regex.MatchString("foo/bat.go")) // Weirdly this should match. At least it does in Git.
	require.True(t, regex.MatchString("foo/bar/bat.go"))
}
