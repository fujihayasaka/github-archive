package workflowparser

import (
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_compileGlob(t *testing.T) {
	examples := []struct {
		glob     string
		positive []string
		negative []string
	}{
		{
			glob: `v[0-9]+.[0-9]+.[0-9]+-*`,
			positive: []string{
				"v1.2.3-alpha",
				"v1.2.3-3",
				"v1.2.3-",
				"v12.23.3-",
				"v9102312.090923.0000030-hi there",
			},
			negative: []string{
				"v1.2.3.4-alpha",
				"v1.2.3.4",
				"v1.f.3",
				"v1..2.3",
			},
		},
		{
			glob: `(a|b)`,
			positive: []string{
				"(a|b)",
			},
			negative: []string{
				"a",
				"b",
				"a|b",
				"",
			},
		},
		{
			glob: `*`,
			positive: []string{
				"",
				"test.rb",
				"test",
				"weird file",
			},
			negative: []string{
				"docs/thing.rb",
			},
		},
		{
			glob: `docs/*`,
			positive: []string{
				"docs/test.rb",
				"docs/some-test.rb",
			},
			negative: []string{
				"test.rb",
				"",
				"docs",
			},
		},
		{
			glob: `**`,
			positive: []string{
				"",
				"test.rb",
				"test",
				"weird file",
				"docs/thing.rb",
			},
		},
		{
			glob: `docs/**`,
			positive: []string{
				"docs/test.rb",
				"docs/sub/test.rb",
			},
			negative: []string{
				"test.rb",
				"",
				"docs",
			},
		},
		{
			glob: `**/docs/**`,
			positive: []string{
				"a/docs/b/test.rb",
				"a/docs/test.rb",
				"docs/thing",
				"docs/thing.rb",
			},
			negative: []string{
				"docs",
			},
		},
		{
			glob: `*/docs/**`,
			positive: []string{
				"a/docs/test.rb",
				"b/docs/b/test.rb",
			},
			negative: []string{
				"docs/thing.rb",
				"a/b/docs/thing",
				"docs",
			},
		},
		{
			glob: `a+b`,
			positive: []string{
				"ab",
				"aaaab",
			},
			negative: []string{
				"",
				"b",
			},
		},
		{
			glob: `[1-5]`,
			positive: []string{
				"1",
				"3",
				"5",
			},
			negative: []string{
				"[1-5]",
				"7",
				"a",
				"",
			},
		},
		{
			glob: `a[1-5]+`,
			positive: []string{
				"a1",
				"a123523123",
			},
			negative: []string{
				"a[1-5]]",
				"a7",
				"123",
				"a",
			},
		},
		{
			glob: `[a-c]z[B-U]`,
			positive: []string{
				"azB",
				"bzM",
				"czU",
			},
			negative: []string{
				"zzB",
				"AzM",
				"azu",
				"z",
			},
		},
		{
			glob: `za?`,
			positive: []string{
				"za",
				"z",
			},
			negative: []string{
				"a",
				"za?",
			},
		},
		{
			glob: `z[ab]?`,
			positive: []string{
				"za",
				"zb",
				"z",
			},
			negative: []string{
				"zaa",
				"zab",
			},
		},
		{
			glob: `z[^ab]`,
			positive: []string{
				"zc",
				"zo",
			},
			negative: []string{
				"za",
				"zb",
				"z",
			},
		},
		{
			glob: `releases/alpha`,
			positive: []string{
				`releases/alpha`,
			},
		},
		{
			glob: `releases\/alpha`,
			positive: []string{
				`releases/alpha`,
			},
		},
		{
			glob: `releases\\alpha`,
			positive: []string{
				`releases\alpha`,
			},
		},
		{
			glob: `yay\\o/`,
			positive: []string{
				`yay\o/`,
			},
		},
		{
			glob: `\\`,
			positive: []string{
				`\`,
			},
		},
		{
			glob: `z\*`,
			positive: []string{
				`z*`,
			},
			negative: []string{
				`z\*`,
				`zzzzzzz`,
			},
		},
		{
			glob: `weird-\[name\]`,
			positive: []string{
				`weird-[name]`,
			},
			negative: []string{
				`weird-n`,
				`weird-name`,
			},
		},
		{
			glob: `c\+\+.md`,
			positive: []string{
				`c++.md`,
			},
			negative: []string{
				`cccccc.md`,
				`c++++++++++++++.md`,
			},
		},
		{
			// dot is just a literal for us
			glob: `.+`,
			positive: []string{
				"....",
				".",
			},
			negative: []string{
				"",
				".+",
			},
		},
		{
			// we don't support ()
			glob: `(x+x+)+z`,
			positive: []string{
				"(xxx)))z",
				"(xx)z",
			},
			negative: []string{
				"xx",
				"xxxxz",
			},
		},
		{
			// we don't support (?:)
			glob: `(?:a)`,
			positive: []string{
				"(:a)",
			},
			negative: []string{
				"a",
			},
		},
		{
			// we don't support {}
			glob: `a{,1}`,
			positive: []string{
				"a{,1}",
			},
			negative: []string{
				"a",
			},
		},
		{
			// we don't support |
			glob: `(a|b)`,
			positive: []string{
				"(a|b)",
			},
			negative: []string{
				"a",
				"b",
				"",
			},
		},
		{
			glob: `**/README.md`,
			positive: []string{
				`README.md`,
				`docs/README.md`,
			},
		},
	}
	for _, eg := range examples {
		t.Run(fmt.Sprintf("glob '%s'", eg.glob), func(t *testing.T) {
			g, err := compileGlobV2(eg.glob)
			require.NoError(t, err)

			positiveFailed := []string{}
			for _, p := range eg.positive {
				if m := g.Match(p); !m {
					positiveFailed = append(positiveFailed, p)
				}
			}
			negativeFailed := []string{}
			for _, p := range eg.negative {
				if m := g.Match(p); m {
					negativeFailed = append(negativeFailed, p)
				}
			}
			assert.Empty(t, positiveFailed, "failed positive examples")
			assert.Empty(t, negativeFailed, "failed negative examples")
		})
	}
}

func TestCompileGlobsRejectsInvalid(t *testing.T) {
	egs := map[string]error{
		`***`:             errTooManyStars,
		`********`:        errTooManyStars,
		`foo*+`:           errPlusAfterStar,
		`foo++`:           errTooManyPlusses,
		`[9-1]`:           errInvalidCharacterRange,
		`[9-a]`:           errInvalidCharacterRange,
		`[🍪-🙉]`:           errInvalidCharacterRange,
		`[0-9`:            errUnterminatedCharacterRange,
		`[-9`:             errUnterminatedCharacterRange,
		`a??`:             errTooManyQuestions,
		`\`:               errTrailingBackslash,
		`??`:              errTooManyQuestions,
		`*?`:              errQuestionAfterStar,
		`a**?`:            errQuestionAfterStar,
		`a+?`:             errQuestionAfterPlus,
		`[^^]`:            errInvalidCharacterRange,
		`[^a^]`:           errInvalidCharacterRange,
		`a**+`:            errPlusAfterStar,
		`foo[-9[*`:        errUnterminatedCharacterRange,
		`foo[[[[[[[]0-9]`: errInvalidCharacterRange,
		`[[:word:]]`:      errInvalidCharacterRange,
		`*[a-b][*`:        errUnterminatedCharacterRange,
		`[0-9]++`:         errTooManyPlusses,
	}
	for input, expectedErr := range egs {
		_, err := compileGlobV2(input)
		assert.EqualError(t, err, expectedErr.Error(), fmt.Sprintf("for glob '%s'", input))
	}
}

func TestGlobSequenceLogic(t *testing.T) {
	examples := []struct {
		globs    []string
		positive [][]string
		negative [][]string
	}{
		// base case - positive patterns
		{
			globs: []string{
				"*.js",
			},
			positive: [][]string{
				{
					"random.js",
				},
				{
					"thing.js",
					"thing.rb",
				},
			},
			negative: [][]string{
				{
					"this.rb",
				},
			},
		},
		// check that we can negate after a match
		{
			globs: []string{
				"*.js",
				"!thing.js",
			},
			positive: [][]string{
				{
					"other.js",
				},
				{
					"other.js",
					"thing.js",
				},
			},
			negative: [][]string{
				{
					"thing.js",
				},
				{
					"thing.js",
					"thing.rb",
				},
				{
					"readme.md",
				},
			},
		},
		// check that we can re-include after a negation
		{
			globs: []string{
				"*.js",
				"!t*.js",
				"thing.js",
			},
			positive: [][]string{
				{
					"random.js",
				},
				{
					"thing.js",
				},
				{
					"this.js",
					"other.js",
				},
			},
			negative: [][]string{
				{
					"this.js",
				},
			},
		},
	}

	for _, eg := range examples {
		gs := strings.Join(eg.globs, ", ")
		globs, err := CompileV2Globs(eg.globs)
		require.NoError(t, err)
		for _, input := range eg.positive {
			set := strings.Join(input, ", ")
			ok, err := runGlobSequenceVsMany(globs, input, true)
			require.NoError(t, err)
			assert.True(t, ok, fmt.Sprintf("%q should have matched %q", gs, set))
		}
		for _, input := range eg.negative {
			set := strings.Join(input, ", ")
			ok, err := runGlobSequenceVsMany(globs, input, true)
			require.NoError(t, err)
			assert.False(t, ok, fmt.Sprintf("%q should not have matched %q", gs, set))
		}
	}
}

func TestTimeoutOperation(t *testing.T) {
	timeoutErr := errors.New("timeout")

	r := runOperationWithTimeout(func() opResult {
		time.Sleep(time.Second)
		return opResult{err: errors.New("fail")}
	}, time.Millisecond*20, timeoutErr)

	require.EqualError(t, r.err, "timeout")

	r = runOperationWithTimeout(func() opResult {
		time.Sleep(time.Millisecond * 5)
		return opResult{result: true}
	}, time.Millisecond*500, timeoutErr)

	require.NoError(t, r.err)
	require.True(t, r.result)
}
