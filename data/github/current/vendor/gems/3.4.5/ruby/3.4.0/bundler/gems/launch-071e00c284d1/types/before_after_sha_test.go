package types

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestBeforeAfterIsZeroValue(t *testing.T) {
	tests := []struct {
		desc   string
		before string
		after  string
		want   bool
	}{
		{
			desc:   "returns true if before and after are missing",
			before: "",
			after:  "",
			want:   true,
		},
		{
			desc:   "returns false if before is missing",
			before: "",
			after:  "aabb",
			want:   false,
		},
		{
			desc:   "returns false if after is missing",
			before: "aabb",
			after:  "",
			want:   false,
		},
		{
			desc:   "returns false if both are present",
			before: "aabb",
			after:  "ccdd",
			want:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			assert.Equal(t, tt.want, BeforeAfterSHAFromStrings(tt.before, tt.after).IsZeroValue())
		})
	}
}
