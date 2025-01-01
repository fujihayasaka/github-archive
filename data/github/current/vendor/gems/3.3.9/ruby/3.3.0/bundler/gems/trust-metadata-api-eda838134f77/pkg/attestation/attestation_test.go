package attestation

import (
	"encoding/json"
	"errors"
	"testing"

	in_toto "github.com/in-toto/attestation/go/v1"
	"github.com/stretchr/testify/assert"
)

var testStatementWithName = `{
  "_type": "https://in-toto.io/Statement/v0.1",
  "predicateType": "https://slsa.dev/provenance/v0.2",
  "subject": [
    {
      "name": "foo-linux-amd64",
      "digest": {
        "sha256": "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c"
      }
    }
  ],
  "predicate": {
    "builder": {
      "id": "https://github.com/slsa-framework/slsa-github-generator-go/.github/workflows/slsa3_builder.yml@refs/heads/main"
    },
    "buildType": "https://github.com/slsa-framework/slsa-github-generator-go@v1",
    "invocation": {
      "configSource": {
        "uri": "git+https://github.com/kommendorkapten/spt@refs/tags/0.0.3",
        "digest": {
          "sha1": "a2beb590ae85674bb3afe9ef5493f718cdff8ee7"
        }
      }
    }
  }
}`

func TestValidateStatementWithName(t *testing.T) {
	var stmt in_toto.Statement
	err := json.Unmarshal([]byte(testStatementWithName), &stmt)
	if err != nil {
		t.Error(err)
		return
	}

	t.Run("no subject", func(t *testing.T) {
		subs, err := ValidateStatement(&in_toto.Statement{})
		assert.Empty(t, len(subs), "unexpected subject")
		assert.Equal(t, ErrMustHaveOneSubject, err, "unexpected error")
	})

	t.Run("no digest", func(t *testing.T) {
		subs, err := ValidateStatement(&in_toto.Statement{
			Subject: []*in_toto.ResourceDescriptor{
				{
					Name: "foo",
				},
			},
		})

		assert.Equal(t, len(subs), 0, "unexpected digest")
		assert.True(t, errors.Is(err, ErrMustHaveOneDigest), "unexpected error")
	})

	t.Run("no subject name", func(t *testing.T) {
		subs, err := ValidateStatement(&in_toto.Statement{
			Subject: []*in_toto.ResourceDescriptor{
				{
					Digest: map[string]string{
						"sha256": "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c",
					},
				},
			},
		})
		assert.Equal(t, "sha256", subs[0].SubjectDigest.Alg, "unexpected algorithm")
		assert.Equal(t, "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c", subs[0].SubjectDigest.Digest, "unexpected subject")
		assert.Equal(t, "", subs[0].Name, "unexpected digest")
		assert.Nil(t, err, "unexpected error")
	})

	t.Run("valid statement", func(t *testing.T) {
		subs, err := ValidateStatement(&stmt)
		assert.Equal(t, "sha256", subs[0].SubjectDigest.Alg, "unexpected algorithm")
		assert.Equal(t, "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c", subs[0].SubjectDigest.Digest, "unexpected digest")
		assert.Equal(t, "foo-linux-amd64", subs[0].Name, "unexpected name")
		assert.Nil(t, err, "unexpected error")
	})
}

var testStatementWithURI = `{
	"_type": "https://in-toto.io/Statement/v0.1",
	"predicateType": "https://slsa.dev/provenance/v0.2",
	"subject": [
	  {
		"uri": "https://foo.com/bar",
		"digest": {
		  "sha256": "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c"
		}
	  }
	],
	"predicate": {
	  "builder": {
		"id": "https://github.com/slsa-framework/slsa-github-generator-go/.github/workflows/slsa3_builder.yml@refs/heads/main"
	  },
	  "buildType": "https://github.com/slsa-framework/slsa-github-generator-go@v1",
	  "invocation": {
		"configSource": {
		  "uri": "git+https://github.com/kommendorkapten/spt@refs/tags/0.0.3",
		  "digest": {
			"sha1": "a2beb590ae85674bb3afe9ef5493f718cdff8ee7"
		  }
		}
	  }
	}
  }`

func TestValidateStatementWithURI(t *testing.T) {
	var stmt in_toto.Statement
	err := json.Unmarshal([]byte(testStatementWithURI), &stmt)
	if err != nil {
		t.Error(err)
		return
	}

	t.Run("valid statement", func(t *testing.T) {
		subs, err := ValidateStatement(&stmt)
		assert.Equal(t, "sha256", subs[0].SubjectDigest.Alg, "unexpected algorithm")
		assert.Equal(t, "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c", subs[0].SubjectDigest.Digest, "unexpected digest")
		assert.Equal(t, "https://foo.com/bar", subs[0].Name, "unexpected name")
		assert.Nil(t, err, "unexpected error")
	})
}
