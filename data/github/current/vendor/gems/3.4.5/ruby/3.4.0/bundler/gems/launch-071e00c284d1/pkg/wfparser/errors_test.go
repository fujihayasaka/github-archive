package wfparser

import (
	"errors"
	"testing"

	"github.com/github/actions-workflow-parser/go/template"
)

func TestWorkflowParseError_Position(t *testing.T) {
	tests := []struct {
		name     string
		expected error
		line     int
		col      int
	}{
		{
			name:     "Parses valid error",
			expected: template.NewTemplateValidationErrorWithPosition(errors.New("Unrecognized function: 'toJson123'"), "", 16, 14),
			line:     16,
			col:      14,
		},
		{
			name:     "Partial position expression",
			expected: errors.New("(Line: 16, Col: )"),
			line:     -1,
			col:      -1,
		},
		{
			name:     "Empty string",
			expected: errors.New(""),
			line:     -1,
			col:      -1,
		},
		{
			name:     "Random string",
			expected: errors.New("random string"),
			line:     -1,
			col:      -1,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := &WorkflowParseError{
				Errors: []error{
					tt.expected,
				},
			}

			line, col := a.Position()
			if line != tt.line {
				t.Errorf("WorkflowParseError.Position() got = %v, want %v", line, tt.line)
			}
			if col != tt.col {
				t.Errorf("WorkflowParseError.Position() got1 = %v, want %v", col, tt.col)
			}
		})
	}
}
