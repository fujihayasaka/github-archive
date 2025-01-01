package logs

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestObfuscateString(t *testing.T) {
	r := require.New(t)
	tests := []struct {
		input          string
		expectedOutput string
	}{
		{
			input:          "",
			expectedOutput: "",
		},
		{
			input:          "1234567",
			expectedOutput: "1234567",
		},
		{
			input:          "1234_something_in_the_middle_5678",
			expectedOutput: "1234...5678",
		},
	}

	for _, test := range tests {
		output := Obfuscate(test.input)

		r.Equal(test.expectedOutput, output)
	}
}
