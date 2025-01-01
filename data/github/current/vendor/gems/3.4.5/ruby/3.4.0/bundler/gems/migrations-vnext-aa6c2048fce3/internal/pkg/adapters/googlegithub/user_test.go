package googlegithub

import (
	"testing"

	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRepository_ToV1Mannequin(t *testing.T) {
	tests := map[string]struct {
		has   *User
		wants *v1.Mannequin
	}{
		"should properly convert the user": {
			has: &User{github.User{
				Email:   pointer.Of("root@localhost"),
				Name:    pointer.Of("Test"),
				HTMLURL: pointer.Of("https://localhost.dev/test"),
			}},
			wants: &v1.Mannequin{
				ResourceId:    "https://localhost.dev/test",
				OrgResourceId: "https://localhost.dev/acme",
				ProfileName:   "Test",
				Email:         "root@localhost",
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			testOrgID := "https://localhost.dev/acme"

			conv, err := test.has.ToV1Mannequin(testOrgID)
			require.NoError(t, err)

			assert.Equal(t, test.wants.GetEmail(), conv.GetEmail())
			assert.Equal(t, test.wants.GetOrgResourceId(), conv.GetOrgResourceId())
			assert.Equal(t, test.wants.GetProfileName(), conv.GetProfileName())
			assert.Equal(t, test.wants.GetResourceId(), conv.GetResourceId())
		})
	}
}
