package attestation

import (
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/sigstore/sigstore-go/pkg/root"
	"github.com/sigstore/sigstore-go/pkg/verify"
)

// TMAVerifier is a wrapper around sigstore-verifier to provide TMA-specific
// verification logic.
type TMAVerifier struct {
	publicTrustedMaterial root.TrustedMaterial
	npmTrustedMaterial    root.TrustedMaterial
	ghTrustedMaterial     root.TrustedMaterial
}

func (t *TMAVerifier) PublicGoodTrustedMaterial() root.TrustedMaterial {
	return t.publicTrustedMaterial
}

func (t *TMAVerifier) NpmTrustedMaterial() root.TrustedMaterial {
	return t.npmTrustedMaterial
}

func (t *TMAVerifier) GitHubTrustedMaterial() root.TrustedMaterial {
	return t.ghTrustedMaterial
}

// FetchGHTrustedRoot returns the trusted root to use for GitHub.
// The trusted root is loaded from the provided TUF directory.
// If no specific target is provided, dotcom's trusted root is returned.
func FetchGHTrustedRoot(tufDir, mirror, target string, log log.Logger) (*root.TrustedRoot, error) {
	if target == "" {
		target = "trusted_root.json"
	}

	log.Info("Loading GitHub trustroot",
		kvp.String("tuf-mirror", mirror),
		kvp.String("trusted-root", target),
	)

	client, err := githubTUFClient(tufDir, mirror)
	if err != nil {
		return nil, fmt.Errorf("failed to create GH TUF client with dir %s: %w", tufDir, err)
	}
	jsonBytes, err := client.GetTarget(target)
	if err != nil {
		return nil, fmt.Errorf("failed to get target %s: %w",
			target, err)
	}

	return root.NewTrustedRootFromJSON(jsonBytes)
}

func FetchPublicGoodTrustedRoot(tufDir string) (*root.TrustedRoot, error) {
	client, err := publicGoodTUFClient(tufDir)
	if err != nil {
		return nil, fmt.Errorf("failed to create Public Good TUF client with dir %s: %w", tufDir, err)
	}

	return root.GetTrustedRoot(client)
}

// NewTMAVerifier creates a new TMAVerifier.
func NewTMAVerifier(publicTrustedMaterial, npmTrustedMaterial, ghTrustedMaterial root.TrustedMaterial) *TMAVerifier {
	return &TMAVerifier{
		publicTrustedMaterial: publicTrustedMaterial,
		npmTrustedMaterial:    npmTrustedMaterial,
		ghTrustedMaterial:     ghTrustedMaterial,
	}
}

// VerifyBundle verifies a bundle.
func (t *TMAVerifier) VerifyBundle(bundle *sgbundle.Bundle) (*verify.VerificationResult, error) {
	verifierConfig := []verify.VerifierOption{}

	var trustedMaterial root.TrustedMaterial
	if isNPMPublishAttestation(bundle) { //nolint:gocritic
		verifierConfig = append(verifierConfig, verify.WithTransparencyLog(1))
		verifierConfig = append(verifierConfig, verify.WithObserverTimestamps(1))
		trustedMaterial = t.npmTrustedMaterial
	} else if isGHAttestation(bundle) {
		verifierConfig = append(verifierConfig, verify.WithSignedTimestamps(1))
		trustedMaterial = t.ghTrustedMaterial
	} else {
		verifierConfig = append(verifierConfig, verify.WithTransparencyLog(1))
		verifierConfig = append(verifierConfig, verify.WithSignedCertificateTimestamps(1))
		verifierConfig = append(verifierConfig, verify.WithObserverTimestamps(1))
		trustedMaterial = t.publicTrustedMaterial
	}

	sev, err := verify.NewSignedEntityVerifier(trustedMaterial, verifierConfig...)
	if err != nil {
		return nil, err
	}

	return sev.Verify(bundle, verify.NewPolicy(verify.WithoutArtifactUnsafe(), verify.WithoutIdentitiesUnsafe()))
}

func isNPMPublishAttestation(bundle *sgbundle.Bundle) bool {
	envelope, err := bundle.Envelope()
	if err != nil {
		return false
	}
	statement, err := envelope.Statement()
	if err != nil {
		return false
	}
	return strings.HasPrefix(statement.PredicateType, "https://github.com/npm/attestation/tree/main/specs/publish")
}

func isGHAttestation(bundle *sgbundle.Bundle) bool {
	verifyContent, err := bundle.VerificationContent()
	if err != nil {
		return false
	}
	leafCert := verifyContent.Certificate()
	if leafCert == nil {
		return false
	}
	return len(leafCert.Issuer.Organization) == 1 && leafCert.Issuer.Organization[0] == "GitHub, Inc."
}
