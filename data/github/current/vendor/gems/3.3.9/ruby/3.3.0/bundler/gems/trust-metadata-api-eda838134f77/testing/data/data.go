package data

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/x509"
	_ "embed"
	"encoding/pem"
	"testing"
	"time"

	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"github.com/sigstore/sigstore-go/pkg/root"
	"github.com/sigstore/sigstore/pkg/signature"
	"google.golang.org/protobuf/encoding/protojson"
)

//go:embed twirpRequest.json
var TwirpRequestRaw []byte

//go:embed sigstoreBundle.json
var SigstoreBundleRaw []byte

//go:embed sigstoreBundle-link.json
var SigstoreBundleLinkRaw []byte

//go:embed sigstoreBundle-publicKey.json
var SigstoreBundlePublicKeyRaw []byte

//go:embed sigstoreBundle-invalid-signature.json
var SigstoreBundleInvalidSignatureRaw []byte

//go:embed sigstoreBundle-invalid-no-logid.json
var SigstoreBundleInvalidNoLogIDRaw []byte

//go:embed sigstoreBundle-invalid-no-signature.json
var SigstoreBundleInvalidNoSignatureRaw []byte

//go:embed sigstoreBundle-invalid-set.json
var SigstoreBundleInvalidSETRaw []byte

//go:embed sigstoreBundle-invalid-mismatched-signatures.json
var SigstoreBundleInvalidMismatchedSignaturesRaw []byte

//go:embed sigstore.js-1.0.0.bundle.json
var SigstoreJs100BundleRaw []byte

//go:embed sigstore.js-1.4.0.bundle.json
var SigstoreJs140BundleRaw []byte

//go:embed sigstore.js-2.2.0.bundle.json
var SigstoreJs220BundleRaw []byte

//go:embed sigstore.js-3.0.0.bundle.json
var SigstoreJs300BundleRaw []byte

//go:embed sigstore.js-0.3.0.bundle.json
var SigstoreJs030BundleRaw []byte

//go:embed gitlab-alpha-01.bundle.json
var GitLabAlpha01BundleRaw []byte

//go:embed gitlab-alpha-01-updated-build-config-run-invocation.bundle.json
var GitLabUpdatedBuildConfigRunInvocationBundleRaw []byte

//go:embed sigstoreBundle-SLSA1Provenance.bundle.json
var SigstoreBundleSLSA1ProvenanceRaw []byte

//go:embed sigstoreBundle-from-generate-build-provenance.json
var SigstoreBundleFromGenerateBuildProvenanceRaw []byte

//go:embed sigstoreBundle-invalid-OIDs-from-generate-build-provenance.json
var SigstoreBundleInvalidOIDsFromGenerateBuildProvenanceRaw []byte

//go:embed sigstoreBundle-custom-issuer.json
var SigstoreBundleCustomIssuer []byte

//go:embed tuf.repo-cdn.sigstore.dev.json
var TUFRepoCDNTrustedRootRaw []byte

func TestBundle(t *testing.T, raw []byte) *protobundle.Bundle {
	var b protobundle.Bundle
	err := protojson.Unmarshal(raw, &b)
	if err != nil {
		t.Fatal(err)
	}
	return &b
}

// SigstoreBundle returns a test *sigstore.Bundle
func SigstoreBundle(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleRaw)
}

// SigstoreBundleLink returns a test *sigstore.Bundle with link predicate type
func SigstoreBundleLink(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleLinkRaw)
}

// SigstoreBundlePublicKey returns a test *sigstore.Bundle signed with a public key
func SigstoreBundlePublicKey(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundlePublicKeyRaw)
}

// SigstoreBundleInvalidSignature returns a test *sigstore.Bundle with an invalid signature
func SigstoreBundleInvalidSignature(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleInvalidSignatureRaw)
}

// SigstoreBundleInvalidNoLogID returns a test *sigstore.Bundle with no log ID
func SigstoreBundleInvalidNoLogID(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleInvalidNoLogIDRaw)
}

// SigstoreBundleInvalidNoSignature returns a test *sigstore.Bundle with no signature
func SigstoreBundleInvalidNoSignature(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleInvalidNoSignatureRaw)
}

// SigstoreBundleInvalidSET returns a test *sigstore.Bundle with an invalid SET
func SigstoreBundleInvalidSET(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleInvalidSETRaw)
}

func SigstoreJs100ProtoBundle(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreJs100BundleRaw)
}

func SigstoreJs140ProtoBundle(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreJs140BundleRaw)
}

func SigstoreJs220ProtoBundle(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreJs220BundleRaw)
}

func SigstoreJs300ProtoBundle(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreJs300BundleRaw)
}

func SigstoreJs030ProtoBundle(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreJs030BundleRaw)
}

func GitLabAlpha01ProtoBundle(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, GitLabAlpha01BundleRaw)
}

func GitLabUpdatedBuildConfigRunInvocationProtoBundle(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, GitLabUpdatedBuildConfigRunInvocationBundleRaw)
}

func SigstoreBundleSLSA1Provenance(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleSLSA1ProvenanceRaw)
}

func SigstoreBundleFromGenerateBuildProvenance(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleFromGenerateBuildProvenanceRaw)
}

func SigstoreBundleFromGenerateBuildProvenanceInvalidOIDs(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleInvalidOIDsFromGenerateBuildProvenanceRaw)
}

func SigstoreBundleWithCustomIssuer(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleCustomIssuer)
}

const SigstoreBundlePublicKeyB64 = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE1Olb3zMAFFxXKHiIkQO5cJ3Yhl5i6UPp+IhuteBJbuHcA5UogKo0EWtlWwW6KSaKoTNEYL7JlCQiVnkhBktUgg=="

// SigstoreBundleInvalidMismatchedSignatures returns a test *sigstore.Bundle with mismatched signatures
func SigstoreBundleInvalidMismatchedSignatures(t *testing.T) *protobundle.Bundle {
	return TestBundle(t, SigstoreBundleInvalidMismatchedSignaturesRaw)
}

func TUFRepoCDNTrustedRootRawTest() []byte {
	return TUFRepoCDNTrustedRootRaw
}

const SigstoreBundlePublicKeyPEM = `-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE1Olb3zMAFFxXKHiIkQO5cJ3Yhl5i6UPp+IhuteBJbuHcA5UogKo0EWtlWwW6KSaKoTNEYL7JlCQiVnkhBktUgg==
-----END PUBLIC KEY-----`

//nolint:gosec
const SigstoreBundlePublicKeyHint = "SHA256:jl3bwswu80PjjokCgh0o2w5c2U4LhQAE57gj9cz1kzA"

func TrustedKeys() map[string]*root.ExpiringKey {
	trustedKeys := make(map[string]*root.ExpiringKey)
	der, _ := pem.Decode([]byte(SigstoreBundlePublicKeyPEM))
	key, err := x509.ParsePKIXPublicKey(der.Bytes)
	if err != nil {
		panic(err)
	}
	verifier, err := signature.LoadECDSAVerifier(key.(*ecdsa.PublicKey), crypto.SHA256)
	if err != nil {
		panic(err)
	}
	trustedKeys[SigstoreBundlePublicKeyHint] = root.NewExpiringKey(verifier, time.Time{}, time.Time{})
	return trustedKeys
}
