package attestation

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGetGitHubTUFClient(t *testing.T) {
	var tests = []struct {
		Case   string
		Mirror string
		Fail   bool
	}{
		{
			Case:   "Prod mirror",
			Mirror: "https://tuf-repo.github.com",
			Fail:   false,
		},
		{
			Case:   "Staging mirror",
			Mirror: "https://github.github.com/staging-tuf-root",
			Fail:   false,
		},
		{
			Case:   "Invalid mirror",
			Mirror: "https://foo.bar.com",
			Fail:   true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.Case, func(t *testing.T) {
			var td = t.TempDir()

			c, err := githubTUFClient(td, tc.Mirror)

			if tc.Fail {
				assert.Nil(t, c)
				assert.Error(t, err)
				assert.Equal(t, "unknown TUF mirror https://foo.bar.com",
					err.Error())
			} else {
				assert.NotNil(t, c)
				assert.Nil(t, err)
			}
		})
	}
}
