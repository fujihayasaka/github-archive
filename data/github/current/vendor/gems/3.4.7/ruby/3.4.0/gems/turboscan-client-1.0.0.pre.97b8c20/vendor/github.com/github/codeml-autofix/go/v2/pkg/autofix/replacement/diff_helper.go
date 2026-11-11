package replacement

import (
	"bufio"
	"regexp"
	"strconv"
	"strings"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/hexops/gotextdiff"
)

var hunkHdrRe = regexp.MustCompile(`^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@`)

// ParseUnifiedString parses a single-file unified diff string into a gotextdiff.Unified.
// It supports ---/+++ file headers, @@ hunk headers, and lines starting with ' ', '+', '-'.
// Lines like "\ No newline at end of file" are ignored.
// Note: For multi-file patches, split and call this per file.
func ParseUnifiedString(diffText string) (gotextdiff.Unified, error) {
	var ud gotextdiff.Unified
	var hunks []*gotextdiff.Hunk
	var cur *gotextdiff.Hunk

	sc := bufio.NewScanner(strings.NewReader(diffText))
	for sc.Scan() {
		line := sc.Text()

		switch {
		case strings.HasPrefix(line, "--- "):
			ud.From = strings.TrimSpace(strings.TrimPrefix(line, "--- "))
		case strings.HasPrefix(line, "+++ "):
			ud.To = strings.TrimSpace(strings.TrimPrefix(line, "+++ "))
		case hunkHdrRe.MatchString(line):
			if cur != nil {
				hunks = append(hunks, cur)
			}
			m := hunkHdrRe.FindStringSubmatch(line)

			fromStart, err := strconv.Atoi(m[1])
			if err != nil {
				return ud, autofix.NewParsingError("parse fromStart", err)
			}
			toStart, err := strconv.Atoi(m[3])
			if err != nil {
				return ud, autofix.NewParsingError("parse toStart", err)
			}

			cur = &gotextdiff.Hunk{
				FromLine: fromStart,
				ToLine:   toStart,
				Lines:    []gotextdiff.Line{},
			}
		case strings.HasPrefix(line, `\ `):
			// e.g. "\ No newline at end of file" - ignore
		default:
			if cur == nil {
				continue // ignore noise outside hunks
			}
			if line == "" {
				// empty context line
				cur.Lines = append(cur.Lines, gotextdiff.Line{Kind: gotextdiff.Equal, Content: "\n"})
				continue
			}
			switch line[0] {
			case ' ':
				cur.Lines = append(cur.Lines, gotextdiff.Line{Kind: gotextdiff.Equal, Content: line[1:] + "\n"})
			case '+':
				cur.Lines = append(cur.Lines, gotextdiff.Line{Kind: gotextdiff.Insert, Content: line[1:] + "\n"})
			case '-':
				cur.Lines = append(cur.Lines, gotextdiff.Line{Kind: gotextdiff.Delete, Content: line[1:] + "\n"})
			default:
				// ignore unknown lines
			}
		}
	}
	if err := sc.Err(); err != nil {
		return ud, autofix.NewParsingError("scan unified diff", err)
	}
	if cur != nil {
		hunks = append(hunks, cur)
	}
	ud.Hunks = hunks
	return ud, nil
}
