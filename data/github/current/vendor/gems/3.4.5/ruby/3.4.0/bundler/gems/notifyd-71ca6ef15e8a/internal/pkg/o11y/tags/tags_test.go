package tags

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_CleanTag(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name     string
		tag      string
		expected string
	}{
		{
			name:     "cleans unsupported characters",
			tag:      "2sending\"-email 1",
			expected: "tag_2sending_email_1",
		},
		{
			name:     "cleans trailing colons",
			tag:      "2sending\"-email 1:",
			expected: "tag_2sending_email_1",
		},
		{
			name:     "cleans trailing puntuations",
			tag:      "2sending\"-email 1$:",
			expected: "tag_2sending_email_1",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			r.Equal(test.expected, CleanTag(test.tag))
		})
	}
}
