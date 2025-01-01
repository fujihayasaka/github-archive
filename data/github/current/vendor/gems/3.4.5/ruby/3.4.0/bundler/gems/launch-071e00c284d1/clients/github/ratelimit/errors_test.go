package ratelimit

import (
	"testing"

	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/assert"

	terrs "github.com/github/launch/types/errors"
)

func Test_IsRateLimitedError(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected bool
	}{
		{
			name:     "Basic rate limit error",
			err:      NewMockRateLimitError("rate limit error", 429),
			expected: true,
		},
		{
			name:     "Non- rate limit error",
			err:      errs.New("some error"),
			expected: false,
		},
		{
			name: "Nested errors",
			err: errs.Wrap(
				errs.Wrap(
					NewMockRateLimitError("rate limit error", 429),
					"inner error 2",
				),
				"inner error 1",
			),
			expected: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			assert.Equal(t, tc.expected, terrs.IsRateLimitError(tc.err), tc.name)
		})
	}
}
