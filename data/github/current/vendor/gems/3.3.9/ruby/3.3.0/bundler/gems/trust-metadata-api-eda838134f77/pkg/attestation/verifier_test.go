package attestation

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/trust-metadata-api/testing/data"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/sigstore/sigstore-go/pkg/root"
	"github.com/stretchr/testify/assert"
)

func TestNewNpmTrustedMaterial(t *testing.T) {
	trustedrootJSON := data.TUFRepoCDNTrustedRootRawTest()
	trustedRoot, err := root.NewTrustedRootFromJSON(trustedrootJSON)
	assert.NoError(t, err)

	keys := make(map[string]*root.ExpiringKey)

	npmTrustedMaterial := NewNpmTrustedMaterial(trustedRoot, keys)

	assert.NotNil(t, npmTrustedMaterial)
}

func TestVerifyBundle(t *testing.T) {
	// Create a mock bundle
	sigstoreBundle := data.SigstoreBundle(t)
	bundle, err := sgbundle.NewBundle(sigstoreBundle)
	assert.NoError(t, err)

	// Create a mock TMAVerifier
	trustedrootJSON := data.TUFRepoCDNTrustedRootRawTest()

	trustedRoot, err := root.NewTrustedRootFromJSON(trustedrootJSON)
	assert.NoError(t, err)

	keys := make(map[string]*root.ExpiringKey)

	TMAVerifier := NewTMAVerifier(trustedRoot, NewNpmTrustedMaterial(trustedRoot, keys), nil)

	// Call the VerifyBundle function
	_, err = TMAVerifier.VerifyBundle(bundle)

	// Assert that no error was returned
	assert.NoError(t, err)
}

func TestFetchGHTrustedRoot(t *testing.T) {
	var tests = []struct {
		Case     string
		Mirror   string
		Target   string
		FulcioCN string
		TsaCN    string
		Fail     bool
	}{
		{
			Case:     "Prod default",
			Mirror:   "https://tuf-repo.github.com",
			Target:   "",
			FulcioCN: "Fulcio Intermediate l2",
			TsaCN:    "TSA Timestamping",
			Fail:     false,
		},
		{
			Case:     "Prod trusted_root.json",
			Mirror:   "https://tuf-repo.github.com",
			Target:   "trusted_root.json",
			FulcioCN: "Fulcio Intermediate l2",
			TsaCN:    "TSA Timestamping",
			Fail:     false,
		},
		{
			Case:     "Prod not-found.json",
			Mirror:   "https://tuf-repo.github.com",
			Target:   "not-found.json",
			FulcioCN: "Umbrella Corporation",
			TsaCN:    "Umbrella Corporation",
			Fail:     true,
		},
		{
			Case:     "Staging default",
			Mirror:   "https://github.github.com/staging-tuf-root",
			Target:   "",
			FulcioCN: "Fulcio Intermediate l2 - staging",
			TsaCN:    "TSA Timestamping - staging",
			Fail:     false,
		},
		{
			Case:     "Staging trusted_root.json",
			Mirror:   "https://github.github.com/staging-tuf-root",
			Target:   "trusted_root.json",
			FulcioCN: "Fulcio Intermediate l2 - staging",
			TsaCN:    "TSA Timestamping - staging",
			Fail:     false,
		},
		{
			Case:     "Staging staff-wus2-01.trusted_root.json",
			Mirror:   "https://github.github.com/staging-tuf-root",
			Target:   "staff-wus2-01.trusted_root.json",
			FulcioCN: "Fulcio Intermediate l2 - staff-wus2-01",
			TsaCN:    "TSA Timestamping - staff-wus2-01",
			Fail:     false,
		},
		{
			Case:     "Invalid mirror",
			Mirror:   "https://foo.bar.com",
			Target:   "",
			FulcioCN: "Umbrella Corporation",
			TsaCN:    "Umbrella Corporation",
			Fail:     true,
		},
	}

	l, _ := log.NewFromEnv(log.WithLogLevel(log.FatalLevel))
	for _, tc := range tests {
		t.Run(tc.Case, func(t *testing.T) {
			var td = t.TempDir()

			tr, err := FetchGHTrustedRoot(td, tc.Mirror, tc.Target, l)

			if tc.Fail {
				assert.Nil(t, tr)
				assert.Error(t, err)
				return
			}

			assert.NotNil(t, tr)
			assert.Nil(t, err)

			// Verify that the returned trusted root is the
			// expected one

			for _, i := range tr.FulcioCertificateAuthorities() {
				assert.Equal(t, tc.FulcioCN,
					i.Intermediates[0].Subject.CommonName)
			}

			for _, i := range tr.TimestampingAuthorities() {
				assert.Equal(t, tc.TsaCN,
					i.Leaf.Subject.CommonName)
			}
		})
	}
}
