package featureswitches

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestDefaults(t *testing.T) {
	r := require.New(t)
	tests := map[string]struct {
		flags       map[string]bool
		flagToCheck string
		expected    bool
	}{
		"returns default true for notify_subscribers if key is missing": {
			flags:       map[string]bool{},
			flagToCheck: "notify_subscribers",
			expected:    true,
		},
		"returns default true for notify_subscribers map is nil": {
			flags:       nil,
			flagToCheck: "notify_subscribers",
			expected:    true,
		},
		"returns false for notify_subscribers if key is present as false": {
			flags:       map[string]bool{"notify_subscribers": false},
			flagToCheck: "notify_subscribers",
			expected:    false,
		},
		"returns default false for notify_actor if key is missing": {
			flags:       map[string]bool{},
			flagToCheck: "notify_actor",
			expected:    false,
		},
		"returns true for notify_actor if key is present as true": {
			flags:       map[string]bool{"notify_actor": true},
			flagToCheck: "notify_actor",
			expected:    true,
		},
		"returns false for a non-present flag with no defaults": {
			flags:       map[string]bool{},
			flagToCheck: "not_present",
			expected:    false,
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			val := IsEnabled(tc.flags, tc.flagToCheck)
			r.Equal(tc.expected, val)
		})
	}
}
