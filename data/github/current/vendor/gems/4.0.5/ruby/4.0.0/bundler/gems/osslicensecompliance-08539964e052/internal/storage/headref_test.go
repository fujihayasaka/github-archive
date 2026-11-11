package storage

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNormalizeHeadRef(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{name: "empty string", in: "", want: ""},
		{name: "bare branch name", in: "main", want: "refs/heads/main"},
		{name: "already fully qualified", in: "refs/heads/main", want: "refs/heads/main"},
		{name: "fully qualified with slashes", in: "refs/heads/feature/with-slashes", want: "refs/heads/feature/with-slashes"},
		{name: "tag ref preserved", in: "refs/tags/v1", want: "refs/tags/v1"},
		{name: "non-ASCII utf8", in: "feature/ünïcødé", want: "refs/heads/feature/ünïcødé"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := NormalizeHeadRef(tt.in)
			assert.Equal(t, tt.want, got)
			// Verify byte-for-byte equality for non-ASCII case
			assert.Equal(t, []byte(tt.want), []byte(got))
		})
	}
}
