package googlegithub

import (
	"testing"

	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRepository_ToV1Issue(t *testing.T) {
	tests := map[string]struct {
		has   *Repository
		wants *v1.Repository
	}{
		"should properly convert a private repository": {
			has: &Repository{github.Repository{
				HTMLURL: pointer.Of("http://localhost.dev/acme/foo"),
				Private: pointer.Of(true),
			}},
			wants: &v1.Repository{
				ResourceId: "http://localhost.dev/acme/foo",
				IsPrivate:  true,
			},
		},
		"should properly convert a non-private repository": {
			has: &Repository{github.Repository{
				HTMLURL: pointer.Of("http://localhost.dev/acme/foo"),
				Private: pointer.Of(false),
			}},
			wants: &v1.Repository{
				ResourceId: "http://localhost.dev/acme/foo",
				IsPrivate:  false,
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			conv, err := test.has.ToV1Repository()
			require.NoError(t, err)

			assert.Equal(t, test.wants.GetResourceId(), conv.GetResourceId())
			assert.Equal(t, test.wants.IsPrivate, conv.GetIsPrivate())
		})
	}
}
