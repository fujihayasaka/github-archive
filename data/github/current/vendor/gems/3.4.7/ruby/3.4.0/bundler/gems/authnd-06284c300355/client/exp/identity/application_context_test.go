package identity

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParseApplicationOwnerType(t *testing.T) {
	tests := []struct {
		input    string
		expected ApplicationOwnerType
		err      bool
	}{
		{"User", ApplicationOwnerTypeUser, false},
		{"Organization", ApplicationOwnerTypeOrganization, false},
		{"Business", ApplicationOwnerTypeBusiness, false},
		{"InvalidType", "", true}, // Should return an error
		{"", "", true},            // Should return an error for empty input
	}

	for _, test := range tests {
		result, err := ParseApplicationOwnerType(test.input)
		if test.err {
			assert.NotNil(t, err)
		} else {
			assert.Nil(t, err)
		}
		assert.Equal(t, test.expected, result)
	}
}
