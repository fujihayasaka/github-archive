package codediff_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/github/turboscan/ts/codediff"
	"github.com/stretchr/testify/require"
)

func TestDiffFromFiles(t *testing.T) {
	cwd, err := os.Getwd()
	require.NoError(t, err)
	tdPath := filepath.Join(cwd, "testdata")

	bf, err := os.ReadFile(filepath.Join(tdPath, "main.js"))
	require.NoError(t, err)

	af, err := os.ReadFile(filepath.Join(tdPath, "main.fixed.js"))
	require.NoError(t, err)

	hunks := codediff.DiffFromFiles("main.js", codediff.FileContent(bf), codediff.FileContent(af)).Hunks
	require.Len(t, hunks, 2)
	require.Len(t, hunks[0].RemovedLines, 0)
	require.Equal(t, hunks[0].AddedLines, []string{
		"const escape = require('escape-html');\n",
	})

	require.Len(t, hunks[1].AddedLines, 1)
	require.Len(t, hunks[1].RemovedLines, 1)
}

func TestSplitLineCountsIntoRanges(t *testing.T) {
	insertLines := []int{2, 11, 12, 24, 25, 26, 28, 30, 31, 32, 33, 34}
	addedLinesRanges := codediff.SplitLineCountsIntoRanges(insertLines)
	require.Equal(t, [][2]int{{2, 2}, {11, 12}, {24, 26}, {28, 28}, {30, 34}}, addedLinesRanges)

	addedLinesRanges = codediff.SplitLineCountsIntoRanges([]int{1})
	require.Equal(t, [][2]int{{1, 1}}, addedLinesRanges)

	addedLinesRanges = codediff.SplitLineCountsIntoRanges([]int{1, 2, 3, 4})
	require.Equal(t, [][2]int{{1, 4}}, addedLinesRanges)

	addedLinesRanges = codediff.SplitLineCountsIntoRanges([]int{})
	require.Equal(t, [][2]int(nil), addedLinesRanges)

	// Out of order line numbers work too, however we expect the ranges to be sorted
	addedLinesRanges = codediff.SplitLineCountsIntoRanges([]int{1, 4, 3, 2})
	require.Equal(t, [][2]int{{1, 4}}, addedLinesRanges)
}
func TestDiffFromFiles_LineRanges(t *testing.T) {
	cwd, err := os.Getwd()
	require.NoError(t, err)
	tdPath := filepath.Join(cwd, "testdata")

	bf, err := os.ReadFile(filepath.Join(tdPath, "main.js"))
	require.NoError(t, err)

	af, err := os.ReadFile(filepath.Join(tdPath, "main.fixed.js"))
	require.NoError(t, err)

	hunks := codediff.DiffFromFiles("main.js", codediff.FileContent(bf), codediff.FileContent(af)).Hunks
	require.Len(t, hunks, 2)
	require.Len(t, hunks[0].AddedLinesRanges, 1)
	require.Equal(t, hunks[0].AddedLinesRanges, [][2]int{{3, 3}})
	require.Equal(t, hunks[1].AddedLinesRanges, [][2]int{{35, 35}})

	af, err = os.ReadFile(filepath.Join(tdPath, "main.fixed_clean.js"))
	require.NoError(t, err)

	hunks = codediff.DiffFromFiles("main.js", codediff.FileContent(bf), codediff.FileContent(af)).Hunks
	require.Len(t, hunks, 1)
	require.Len(t, hunks[0].AddedLinesRanges, 2)
	require.Equal(t, hunks[0].AddedLinesRanges[0], [2]int{2, 2})
	require.Equal(t, hunks[0].AddedLinesRanges[1], [2]int{11, 12})

	require.Equal(t, hunks[0].RemovedLinesRanges, [][2]int{{2, 2}, {6, 28}, {34, 34}})
}

func TestDiffFromContent(t *testing.T) {
	cwd, err := os.Getwd()
	require.NoError(t, err)
	tdPath := filepath.Join(cwd, "testdata")

	sf, err := os.ReadFile(filepath.Join(tdPath, "suggestion.patch"))
	require.NoError(t, err)

	hunks := codediff.DiffFromContent(codediff.DiffContent(sf)).Hunks
	require.Len(t, hunks, 2)
	require.Equal(t, hunks[0].AddedLines, []string{
		"const escape = require('escape-html');\n",
	})
	require.Len(t, hunks[0].RemovedLines, 0)
	require.Len(t, hunks[1].RemovedLines, 1)

	// empty
	hunks = codediff.DiffFromContent(codediff.DiffContent("")).Hunks
	require.Len(t, hunks, 0)
	hunks = codediff.DiffFromContent(codediff.DiffContent("foo")).Hunks
	require.Len(t, hunks, 0)
}

func TestCompareDiffs(t *testing.T) {
	var needles []*codediff.DiffHunk
	needles = append(needles, &codediff.DiffHunk{
		AddedLines: []string{
			"foo", "bar", "baz",
		},
		RemovedLines: []string{
			"boom",
		},
	})
	var haystacks []*codediff.DiffHunk
	haystacks = append(haystacks, &codediff.DiffHunk{
		AddedLines: []string{"import"},
	})
	haystacks = append(haystacks, &codediff.DiffHunk{
		AddedLines:   []string{"fix"},
		RemovedLines: []string{"boom"},
	})

	stats := codediff.CompareDiffs(&codediff.Diff{needles}, &codediff.Diff{haystacks})
	// needle not found at all
	require.Equal(t, 3, stats.TotalAddedChanges)
	require.Equal(t, 3, stats.TotalAdded)

	haystacks = append(haystacks, &codediff.DiffHunk{
		AddedLines:   []string{"foo", "baz"},
		RemovedLines: []string{"boom"},
	})
	stats = codediff.CompareDiffs(&codediff.Diff{needles}, &codediff.Diff{haystacks})
	require.Equal(t, 1, stats.TotalAddedChanges)
	require.Equal(t, 3, stats.TotalAdded)
}

func TestCompareDiffs2(t *testing.T) {
	cwd, err := os.Getwd()
	require.NoError(t, err)
	tdPath := filepath.Join(cwd, "testdata")

	sf, err := os.ReadFile(filepath.Join(tdPath, "suggestion.patch"))
	require.NoError(t, err)
	needle := codediff.DiffFromContent(codediff.DiffContent(sf))

	bf, err := os.ReadFile(filepath.Join(tdPath, "main.js"))
	require.NoError(t, err)
	af, err := os.ReadFile(filepath.Join(tdPath, "main.fixed.js"))
	require.NoError(t, err)
	haystack := codediff.DiffFromFiles("main.js", codediff.FileContent(bf), codediff.FileContent(af))

	stats := codediff.CompareDiffs(needle, haystack)
	require.Equal(t, 0, stats.TotalAddedChanges)
	require.Equal(t, 10, stats.TotalAdded)
	require.Equal(t, 0, stats.TotalRemovedChanges)
	require.Equal(t, 6, stats.TotalRemoved)

	// use the same suggestion but the actual fix was different
	af, err = os.ReadFile(filepath.Join(tdPath, "main.removed.js"))
	require.NoError(t, err)
	haystack = codediff.DiffFromFiles("main.js", codediff.FileContent(bf), codediff.FileContent(af))
	stats = codediff.CompareDiffs(needle, haystack)
	require.Equal(t, 7, stats.TotalAddedChanges)
	require.Equal(t, 10, stats.TotalAdded)
	// The removed change is not counted because it's the same as the suggestion
	require.Equal(t, 0, stats.TotalRemovedChanges)
	require.Equal(t, 6, stats.TotalRemoved)

	// same suggestion but fixed version has more changes
	af, err = os.ReadFile(filepath.Join(tdPath, "main.fixed_clean.js"))
	require.NoError(t, err)
	haystack = codediff.DiffFromFiles("main.js", codediff.FileContent(bf), codediff.FileContent(af))
	stats = codediff.CompareDiffs(needle, haystack)
	require.Equal(t, 0, stats.TotalAddedChanges)
	require.Equal(t, 10, stats.TotalAdded)
	require.Equal(t, 0, stats.TotalRemovedChanges)
	require.Equal(t, 6, stats.TotalRemoved)

	// same suggestion but fixed version has small changes in lines
	af, err = os.ReadFile(filepath.Join(tdPath, "main.fixed_small.js"))
	require.NoError(t, err)
	haystack = codediff.DiffFromFiles("main.js", codediff.FileContent(bf), codediff.FileContent(af))
	stats = codediff.CompareDiffs(needle, haystack)
	require.Equal(t, 3, stats.TotalAddedChanges)
	require.Equal(t, 10, stats.TotalAdded)
	require.Equal(t, 0, stats.TotalRemovedChanges)
	require.Equal(t, 6, stats.TotalRemoved)
}

func TestCompareDiffsRawStrings(t *testing.T) {
	// Proposed suggestion
	suggestionDiff := `diff --git a/main.js b/main.js
index 3e3e3e3..4e4e4e4 100644
--- a/main.js
+++ b/main.js
@@ -1,3 +1,3 @@
-import { foo } from 'bar';
+import { foo, baz } from 'bar';`

	// The actual changes in the file
	f1 := `import { foo } from 'bar';
foo("hello world");
foo("again");
`
	f2 := `import { foo, baz, bar } from 'bar';
foo("hello");
`
	// When comparing the suggested diff with the actual change delta(f1, f2)
	// The lines added in the suggestion are almost found in the actual change
	// They only differ by two different tokens: "baz," and "bar", which are not in the suggestion
	needle := codediff.DiffFromContent(codediff.DiffContent(suggestionDiff))
	haystack := codediff.DiffFromFiles("main.js", codediff.FileContent(f1), codediff.FileContent(f2))
	stats := codediff.CompareDiffs(needle, haystack)
	require.Equal(t, 2, stats.TotalAddedChanges)
	require.Equal(t, 7, stats.TotalAdded)
	require.Equal(t, 0, stats.TotalRemovedChanges)
	require.Equal(t, 6, stats.TotalRemoved)

	// If we change the order of the imports to look a bit more like the suggestion
	// and move the "baz" import to the end of the line. We only get 1 token changed: "bar,"
	f2 = `import { foo, bar, baz } from 'bar';
foo("hello");`
	haystack = codediff.DiffFromFiles("main.js", codediff.FileContent(f1), codediff.FileContent(f2))
	stats = codediff.CompareDiffs(needle, haystack)
	require.Equal(t, 1, stats.TotalAddedChanges)
	require.Equal(t, 7, stats.TotalAdded)
}
