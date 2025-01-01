package attestation

import (
	"testing"

	"github.com/github/trust-metadata-api/testing/data"
	"github.com/sigstore/sigstore-go/pkg/root"
	"github.com/stretchr/testify/require"
)

func LocalDataVerifier(t *testing.T) *TMAVerifier {
	pgiTrustedRoot, err := root.NewTrustedRootFromJSON(data.TUFRepoCDNTrustedRootRaw)
	require.NoError(t, err)

	ghTrustedRoot, err := root.NewTrustedRootFromJSON(data.GitHubTUFRepoTrustedRootRaw)
	require.NoError(t, err)

	npmTrustedMaterial := NewNpmTrustedMaterial(pgiTrustedRoot, data.TrustedKeys())
	return NewTMAVerifier(pgiTrustedRoot, npmTrustedMaterial, ghTrustedRoot)
}
