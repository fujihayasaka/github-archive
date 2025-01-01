package utils

import (
	"encoding/json"
	"os"
	"strconv"
	"strings"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/fix"
	"github.com/pkg/errors"
)

// LoadFix loads a fix from disk in the specified format.
func LoadFix(path string, format FixFormat) (*fix.Fix, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	switch format {
	case FixFormatFix:
		var fix fix.Fix
		if err := json.NewDecoder(file).Decode(&fix); err != nil {
			return nil, err
		}
		return &fix, nil
	case FixFormatAutoFixResponse:
		var autofixResponse fixdata.AutofixResponse
		if err := json.NewDecoder(file).Decode(&autofixResponse); err != nil {
			return nil, err
		}
		return fix.FromAutofixResponse(&autofixResponse)
	default:
		return nil, errors.Errorf("unsupported fix format: %s", format)
	}
}

// PrependLineNumbersWithStartLine prefixes each line with an incrementing line
// number starting at startLine.
func PrependLineNumbersWithStartLine(code string, startLine int) string {
	lines := strings.Split(code, "\n")
	for i, line := range lines {
		lines[i] = strconv.Itoa(startLine+i) + ":" + line
	}
	return strings.Join(lines, "\n")
}
