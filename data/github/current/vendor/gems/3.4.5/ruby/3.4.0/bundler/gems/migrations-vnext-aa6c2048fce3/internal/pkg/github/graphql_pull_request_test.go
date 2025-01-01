package github

import (
	"errors"
	"math"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_safeCastToInt32(t *testing.T) {
	tests := map[string]struct {
		input    int
		expected int32
		err      error
	}{
		"within int32 range": {
			input:    123,
			expected: 123,
			err:      nil,
		},
		"at int32 max boundary": {
			input:    math.MaxInt32,
			expected: math.MaxInt32,
			err:      nil,
		},
		"at int32 min boundary": {
			input:    math.MinInt32,
			expected: math.MinInt32,
			err:      nil,
		},
		"above int32 max boundary": {
			input:    math.MaxInt32 + 1,
			expected: 0,
			err:      errors.New("value out of range for int32"),
		},
		"below int32 min boundary": {
			input:    math.MinInt32 - 1,
			expected: 0,
			err:      errors.New("value out of range for int32"),
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			result, err := safeCastToInt32(test.input)
			if test.err != nil {
				require.EqualError(t, err, test.err.Error())
			} else {
				require.NoError(t, err)
			}
			assert.Equal(t, test.expected, result)
		})
	}
}
