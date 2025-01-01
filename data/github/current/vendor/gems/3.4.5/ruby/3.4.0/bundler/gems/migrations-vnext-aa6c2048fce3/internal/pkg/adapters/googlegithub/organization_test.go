package googlegithub

import (
	"testing"

	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestOrganization_ToV1Issue(t *testing.T) {
	tests := map[string]struct {
		has   *Organization
		wants *v1.Organization
	}{
		"should properly convert the organization": {
			has: &Organization{github.Organization{
				HTMLURL: pointer.Of("http://localhost.test/contoso"),
				Login:   pointer.Of("contoso"),
				Name:    pointer.Of("Contoso"),
			}},
			wants: &v1.Organization{
				ResourceId: "http://localhost.test/contoso",
				Name:       "Contoso",
				Login:      "contoso",
			},
		},
		"should use the Login field for name when Name is not set": {
			has: &Organization{github.Organization{
				HTMLURL: pointer.Of("http://localhost.test/contoso"),
				Login:   pointer.Of("contoso"),
			}},
			wants: &v1.Organization{
				ResourceId: "http://localhost.test/contoso",
				Name:       "contoso",
				Login:      "contoso",
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			conv, err := test.has.ToV1Organization()
			require.NoError(t, err)

			expectedName := test.has.GetName()
			if expectedName == "" {
				expectedName = test.has.GetLogin()
			}

			assert.Equal(t, test.wants.GetLogin(), conv.GetLogin())
			assert.Equal(t, expectedName, conv.GetName())
			assert.Equal(t, test.wants.GetResourceId(), conv.GetResourceId())
		})
	}
}
