package cli

import (
	"testing"
)

func Test_fixDeployedTo(t *testing.T) {
	tests := []struct {
		in   string
		want string
	}{
		{"lab", "lab"},
		{"canary", "canary"},
		{"production/canary", "production-canary"},
		{"production/canary/foo", "production-canary-foo"},
		{"", ""},
		{"production", "production"},
		{"backfills", "backfills"},
	}
	for _, tc := range tests {
		t.Run(tc.in, func(t *testing.T) {
			got := fixDeployedTo(tc.in)
			if got != tc.want {
				t.Errorf("fixDeployedTo(%q) = %q; want %q\n", tc.in, got, tc.want)
			}
		})
	}
}
