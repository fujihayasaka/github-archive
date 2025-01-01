package utils

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/github/codeml-autofix/go/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/pkg/autovalidate/fix"
)

func LoadFix(path string, format FixFormat) (*fix.Fix, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	if format == FixFormatFix {
		var fix fix.Fix
		if err := json.NewDecoder(file).Decode(&fix); err != nil {
			return nil, err
		}
		return &fix, nil
	} else if format == FixFormatAutoFixResponse {
		var autofixResponse fixdata.AutofixResponse
		if err := json.NewDecoder(file).Decode(&autofixResponse); err != nil {
			return nil, err
		}
		return fix.FromAutofixResponse(&autofixResponse)
	} else {
		return nil, fmt.Errorf("unsupported fix format: %s", format)
	}
}

func PrependLineNumbersWithStartLine(code string, startLine int) string {
	lines := strings.Split(code, "\n")
	for i, line := range lines {
		lines[i] = strconv.Itoa(startLine+i) + ":" + line
	}
	return strings.Join(lines, "\n")
}
