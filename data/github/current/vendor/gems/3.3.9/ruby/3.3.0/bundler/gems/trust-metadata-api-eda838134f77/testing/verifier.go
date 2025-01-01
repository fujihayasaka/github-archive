package testing

import (
	"testing"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/testing/data"
	"github.com/sigstore/sigstore-go/pkg/root"
)

func TMAVerifier(t *testing.T) *attestation.TMAVerifier {
	trustedRoot, err := root.NewTrustedRootFromJSON(data.TUFRepoCDNTrustedRootRaw)
	if err != nil {
		t.Fatalf("failed to create trusted root: %v", err)
	}

	npmTrustedMaterial := attestation.NewNpmTrustedMaterial(trustedRoot, data.TrustedKeys())
	return attestation.NewTMAVerifier(trustedRoot, npmTrustedMaterial, nil)
}
