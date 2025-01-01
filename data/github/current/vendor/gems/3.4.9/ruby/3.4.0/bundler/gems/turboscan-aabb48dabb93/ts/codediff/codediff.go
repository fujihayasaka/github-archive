// Package codediff provides functions for comparing and analyzing differences between code diffs.
package codediff

import (
	"path/filepath"
	"sort"

	"github.com/hexops/gotextdiff"
	"github.com/hexops/gotextdiff/myers"
	"github.com/hexops/gotextdiff/span"
)

type DiffHunk struct {
	AddedLines   []string
	RemovedLines []string

	AddedLinesRanges   [][2]int
	RemovedLinesRanges [][2]int
}

type Diff struct {
	Hunks []*DiffHunk
}

func (d Diff) AddedTokenizer() simple {
	var t simple
	for _, a := range d.Hunks {
		t.tokens = append(t.tokens, a.AddedLines...)
	}
	return t
}

func (d Diff) RemovedTokenizer() simple {
	var t simple
	for _, a := range d.Hunks {
		t.tokens = append(t.tokens, a.RemovedLines...)
	}
	return t
}

type FileContent string
type DiffContent string

type DiffStats struct {
	TotalAdded          int
	TotalAddedChanges   int
	TotalRemoved        int
	TotalRemovedChanges int
}

func (d DiffStats) PercentChanged() float32 {
	if d.TotalAdded+d.TotalRemoved == 0 {
		return 0
	}
	return float32(d.TotalAddedChanges+d.TotalRemovedChanges) / float32(d.TotalAdded+d.TotalRemoved)
}

func DiffFromContent(diff DiffContent) *Diff {
	lines := splitLines(string(diff))

	var hunks []*DiffHunk
	h := &DiffHunk{}

	// TODO: compute the AddedLinesRanges and RemovedLinesRanges
	for _, line := range lines {
		runes := []rune(line)
		if len(runes) == 0 {
			continue
		}
		switch runes[0] {
		case '+':
			if runes[1] == '+' && runes[2] == '+' {
				continue
			}
			h.AddedLines = append(h.AddedLines, line[1:])
		case '-':
			if runes[1] == '-' && runes[2] == '-' {
				continue
			}
			h.RemovedLines = append(h.RemovedLines, line[1:])
		default:
			if len(h.AddedLines) > 0 || len(h.RemovedLines) > 0 {
				hunks = append(hunks, h)
			}
			h = &DiffHunk{}
		}
	}
	if len(h.AddedLines) > 0 || len(h.RemovedLines) > 0 {
		hunks = append(hunks, h)
	}
	return &Diff{hunks}
}

func DiffFromFiles(fp string, before, after FileContent) *Diff {
	nullPath := "/dev/null"
	basePath := nullPath
	headPath := nullPath
	baseContents := ""
	headContents := ""

	if before != "" {
		basePath = filepath.Clean(filepath.Join("a", fp))
		baseContents = string(before)
	}

	if after != "" {
		headPath = filepath.Clean(filepath.Join("b", fp))
		headContents = string(after)
	}

	edits := myers.ComputeEdits(span.URIFromPath(basePath), baseContents, headContents)
	unified := gotextdiff.ToUnified(basePath, headPath, baseContents, edits)
	var hunks []*DiffHunk
	for _, hunk := range unified.Hunks {
		h := &DiffHunk{}
		hunks = append(hunks, h)

		removeLineC := hunk.FromLine - 1
		insertLineC := hunk.ToLine - 1
		var insertLines []int
		var removeLines []int
		for _, l := range hunk.Lines {
			switch l.Kind {
			case gotextdiff.Delete:
				removeLineC++
				h.RemovedLines = append(h.RemovedLines, l.Content)
				removeLines = append(removeLines, removeLineC)
			case gotextdiff.Insert:
				insertLineC++
				h.AddedLines = append(h.AddedLines, l.Content)
				insertLines = append(insertLines, insertLineC)
			case gotextdiff.Equal:
				insertLineC++
				removeLineC++
			}
		}

		h.AddedLinesRanges = SplitLineCountsIntoRanges(insertLines)
		h.RemovedLinesRanges = SplitLineCountsIntoRanges(removeLines)
	}

	return &Diff{hunks}
}

// SplitLineCountsIntoRanges returns an array of start and end ranges for consecutive lines.
func SplitLineCountsIntoRanges(lineNums []int) (result [][2]int) {
	if len(lineNums) == 0 {
		return
	}

	sortedLineNums := make([]int, len(lineNums))
	copy(sortedLineNums, lineNums)
	sort.Ints(sortedLineNums)

	start := 0
	for i := 1; i < len(sortedLineNums); i++ {
		if sortedLineNums[i] != sortedLineNums[i-1]+1 {
			result = append(result, [2]int{sortedLineNums[start], sortedLineNums[i-1]})
			start = i
		}
	}
	return append(result, [2]int{sortedLineNums[start], sortedLineNums[len(sortedLineNums)-1]})
}

func CompareDiffs(needle, haystack *Diff) *DiffStats {
	needleAdded := needle.AddedTokenizer().LexTokenizer()
	needleRemoved := needle.RemovedTokenizer().LexTokenizer()
	c1 := NeedlemanWunsch(needleAdded, haystack.AddedTokenizer().LexTokenizer())
	c2 := NeedlemanWunsch(needleRemoved, haystack.RemovedTokenizer().LexTokenizer())
	return &DiffStats{
		TotalAdded:          needleAdded.TokensLen(),
		TotalAddedChanges:   c1,
		TotalRemoved:        needleRemoved.TokensLen(),
		TotalRemovedChanges: c2,
	}
}
