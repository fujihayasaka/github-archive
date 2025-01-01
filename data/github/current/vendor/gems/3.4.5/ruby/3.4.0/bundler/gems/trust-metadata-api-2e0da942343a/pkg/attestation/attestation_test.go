package attestation

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/github/trust-metadata-api/test/data"
	in_toto "github.com/in-toto/attestation/go/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var testStatement = `{
	"_type": "https://in-toto.io/Statement/v0.1",
	"predicateType": "https://slsa.dev/provenance/v0.2",
	"subject": [
	  {
        "name": "foo-linux-amd64",
        "digest": {
          "sha256": "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c"
        }
      },
	  {
		"uri": "https://foo.com/bar",
		"digest": {
		  "sha256": "ab92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c"
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

func getStatementandSubject(t *testing.T, bundle *sgbundle.Bundle) (*in_toto.Statement, []Subject) {
	envelope, err := bundle.Envelope()
	require.NoError(t, err)
	statement, err := envelope.Statement()
	require.NoError(t, err)
	subject, err := ValidateStatement(statement)
	require.NoError(t, err)

	return statement, subject
}

func TestValidateStatementWithName(t *testing.T) {
	var stmt in_toto.Statement
	err := json.Unmarshal([]byte(testStatement), &stmt)
	require.NoError(t, err)

	t.Run("no subject", func(t *testing.T) {
		subs, err := ValidateStatement(&in_toto.Statement{})
		assert.Empty(t, len(subs), "unexpected subject")
		assert.ErrorIs(t, err, ErrNoSubject)
	})

	t.Run("too many subjects", func(t *testing.T) {
		// Create 1025 subjects
		subjects := make([]*in_toto.ResourceDescriptor, 0, 1025)
		for i := 0; i < 1025; i++ {
			subjects = append(subjects, &in_toto.ResourceDescriptor{
				Name: "foo",
				Digest: map[string]string{
					"sha256": "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c",
				},
			})
		}

		subs, err := ValidateStatement(&in_toto.Statement{
			Subject: subjects,
		})
		assert.Empty(t, len(subs), "unexpected subject")
		assert.Equal(t, ErrTooManySubjects, err, "unexpected error")
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
		assert.ErrorIs(t, err, ErrMustHaveOneDigest, "unexpected error")
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
		assert.Equal(t, "sha256", subs[0].Alg, "unexpected algorithm")
		assert.Equal(t, "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c", subs[0].Digest, "unexpected subject")
		assert.Zero(t, subs[0].Name, "unexpected digest")
		assert.NoError(t, err)
	})

	t.Run("duplicate subject digests", func(t *testing.T) {
		subs, err := ValidateStatement(&in_toto.Statement{
			Subject: []*in_toto.ResourceDescriptor{
				{
					Digest: map[string]string{
						"sha256": "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c",
					},
				},
				{
					Digest: map[string]string{
						"sha256": "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c",
					},
				},
			},
		})

		assert.Equal(t, len(subs), 0, "unexpected digest")
		assert.ErrorIs(t, err, ErrDuplicateDigest, "unexpected error")
	})

	t.Run("duplicate subject digests different name", func(t *testing.T) {
		subs, err := ValidateStatement(&in_toto.Statement{
			Subject: []*in_toto.ResourceDescriptor{
				{
					Name: "name1",
					Digest: map[string]string{
						"sha256": "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c",
					},
				},
				{
					Name: "name2",
					Digest: map[string]string{
						"sha256": "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c",
					},
				},
			},
		})

		assert.Equal(t, len(subs), 2, "unexpected digest")
		assert.NoError(t, err)
	})

	t.Run("subject name exceeds 256 characters", func(t *testing.T) {
		longName := strings.Repeat("a", 257)
		result, err := ValidateStatement(&in_toto.Statement{
			Subject: []*in_toto.ResourceDescriptor{
				{
					Name: longName,
					Digest: map[string]string{
						"sha256": "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c",
					},
				},
			},
		})
		assert.Empty(t, result, "expected no subjects")
		assert.EqualError(t, err, ErrSubjectNameLengthExceeded(longName).Error(), "unexpected error")
	})

	t.Run("subject digest exceeds 256 characters", func(t *testing.T) {
		longDigest := strings.Repeat("a", 257)
		result, err := ValidateStatement(&in_toto.Statement{
			Subject: []*in_toto.ResourceDescriptor{
				{
					Name: "pkg:foo/bar@v1.0.0",
					Digest: map[string]string{
						"sha256": longDigest,
					},
				},
			},
		})
		assert.Empty(t, result, "expected no subjects")
		assert.EqualError(t, err, ErrSubjectDigestLengthExceeded(longDigest).Error(), "unexpected error")
	})

	t.Run("valid statement", func(t *testing.T) {
		subs, err := ValidateStatement(&stmt)
		assert.Len(t, subs, 2, "unexpected number of subjects")
		assert.Nil(t, err, "unexpected error")

		// Subject 0
		sub := subs[0]
		assert.Equal(t, "sha256", sub.Alg, "unexpected algorithm")
		assert.Equal(t, "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c", sub.Digest, "unexpected digest")
		assert.Equal(t, "foo-linux-amd64", sub.Name, "unexpected name")

		// Subject 1
		sub = subs[1]
		assert.Equal(t, "sha256", sub.Alg, "unexpected algorithm")
		assert.Equal(t, "ab92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c", sub.Digest, "unexpected digest")
		assert.Equal(t, "https://foo.com/bar", sub.Name, "unexpected name")
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
	require.NoError(t, err)

	t.Run("valid statement", func(t *testing.T) {
		subs, err := ValidateStatement(&stmt)
		assert.Equal(t, "sha256", subs[0].Alg, "unexpected algorithm")
		assert.Equal(t, "fd92c12d7947cc04a13948248ccf305682f395af3e109ed044081dbb40182e6c", subs[0].Digest, "unexpected digest")
		assert.Equal(t, "https://foo.com/bar", subs[0].Name, "unexpected name")
		assert.NoError(t, err)
	})
}

func TestNewAttestationRecordWithCertChain(t *testing.T) {
	pbundle := data.SigstoreBundle(t)
	bundle, err := sgbundle.NewBundle(pbundle)
	require.NoError(t, err)
	statement, subject := getStatementandSubject(t, bundle)

	t.Run("valid certificate chain", func(t *testing.T) {
		record, err := newAttestationRecord(pbundle, subject, statement)
		assert.NoError(t, err)
		assert.Equal(t, "36965687079782928586435860974023896448601983968", record.Certificate.SerialNumber.String())
	})

	t.Run("Invalid VerificationMaterial", func(t *testing.T) {
		bundle.VerificationMaterial.Content = nil
		record, err := newAttestationRecord(pbundle, subject, statement)
		assert.NoError(t, err)
		assert.Nil(t, record.Certificate)
	})
}

func TestNewAttestationRecordWithSingleCert(t *testing.T) {
	pbundle := data.SigstoreJs300ProtoBundle(t)
	bundle, err := sgbundle.NewBundle(pbundle)
	require.NoError(t, err)
	statement, subs := getStatementandSubject(t, bundle)

	t.Run("valid certificate", func(t *testing.T) {
		record, err := newAttestationRecord(pbundle, subs, statement)
		assert.NoError(t, err)
		assert.Equal(t, "662640022264592389906077087555937040960009710002", record.Certificate.SerialNumber.String())
		assert.Len(t, subs, 1, "unexpected number of subjects")
		assert.Nil(t, err, "unexpected error")
		assert.Equal(t, "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main", record.Signer)
	})
}
