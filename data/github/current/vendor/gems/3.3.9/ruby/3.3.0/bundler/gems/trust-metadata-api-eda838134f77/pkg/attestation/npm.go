package attestation

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/base64"
	"fmt"
	"time"

	"github.com/go-jose/go-jose/v3/json"
	in_toto "github.com/in-toto/attestation/go/v1"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"github.com/sigstore/sigstore-go/pkg/root"
	"github.com/sigstore/sigstore/pkg/signature"
)

// Identifiers represents the identifiers for an attestation from NPM
type IdentifiersNPM struct {
	ID                        uint64
	Purl                      string
	DomainID                  uint32
	PredicateType             string
	SubjectDigest             string
	VerifyProvenanceStatement bool
}

type PublicKey struct {
	RawBytes   string         `json:"rawBytes"`
	KeyDetails string         `json:"keyDetails"`
	ValidFor   ValidityPeriod `json:"validFor"`
}

type ValidityPeriod struct {
	Start string `json:"start"`
	End   string `json:"end"`
}

type Key struct {
	KeyID     string    `json:"keyId"`
	KeyUsage  string    `json:"keyUsage"`
	PublicKey PublicKey `json:"publicKey"`
}

type Keys struct {
	Keys []Key `json:"keys"`
}

// FetchNpmKeys fetches the npm keys from the TUF delegate
func FetchNpmKeys(tufDir string) (map[string]*root.ExpiringKey, error) {
	client, err := publicGoodTUFClient(tufDir)
	if err != nil {
		return nil, err
	}

	targetBytes, err := client.GetTarget("registry.npmjs.org/keys.json")
	if err != nil {
		return nil, err
	}

	var keys Keys
	err = json.Unmarshal(targetBytes, &keys)
	if err != nil {
		return nil, err
	}

	ret := make(map[string]*root.ExpiringKey)
	for _, key := range keys.Keys {
		if key.KeyUsage != "npm:attestations" {
			continue
		}
		var verifier signature.Verifier
		switch key.PublicKey.KeyDetails {
		case "PKIX_ECDSA_P256_SHA_256":
			keyDER, err := base64.StdEncoding.DecodeString(key.PublicKey.RawBytes)
			if err != nil {
				return nil, err
			}
			pubKey, err := x509.ParsePKIXPublicKey(keyDER)
			if err != nil {
				return nil, err
			}
			ecdsaPubKey, ok := pubKey.(*ecdsa.PublicKey)
			if !ok {
				return nil, fmt.Errorf("unexpected public key type: %T", pubKey)
			}
			verifier, err = signature.LoadECDSAVerifier(ecdsaPubKey, crypto.SHA256)
			if err != nil {
				return nil, err
			}
		default:
			return nil, fmt.Errorf("unsupported key type: %s", key.PublicKey.KeyDetails)
		}
		var startDate, endDate time.Time
		if key.PublicKey.ValidFor.Start != "" {
			startDate, err = time.Parse(time.RFC3339, key.PublicKey.ValidFor.Start)
			if err != nil {
				return nil, err
			}
		}
		if key.PublicKey.ValidFor.End != "" {
			endDate, err = time.Parse(time.RFC3339, key.PublicKey.ValidFor.End)
			if err != nil {
				return nil, err
			}
		}
		ret[key.KeyID] = root.NewExpiringKey(verifier, startDate, endDate)
	}
	return ret, nil
}

// NpmTrustedMaterial is a TrustedMaterial for npm publish attestations
type NpmTrustedMaterial struct {
	root.BaseTrustedMaterial
	publicTrustedRoot  root.TrustedMaterial
	npmTrustedMaterial root.TrustedMaterial
}

var _ root.TrustedMaterial = &NpmTrustedMaterial{}

// NewNpmTrustedMaterial creates a new NpmTrustedMaterial
func NewNpmTrustedMaterial(publicTrustedRoot root.TrustedMaterial, keys map[string]*root.ExpiringKey) *NpmTrustedMaterial {
	return &NpmTrustedMaterial{
		publicTrustedRoot:  publicTrustedRoot,
		npmTrustedMaterial: root.NewTrustedPublicKeyMaterialFromMapping(keys),
	}
}

// PublicKeyVerifier returns a ValidityPeriodVerifier for the given hint
func (n *NpmTrustedMaterial) PublicKeyVerifier(hint string) (root.TimeConstrainedVerifier, error) {
	return n.npmTrustedMaterial.PublicKeyVerifier(hint)
}

// RekorLogs returns the Rekor transparency logs from the public trusted root
func (n *NpmTrustedMaterial) RekorLogs() map[string]*root.TransparencyLog {
	return n.publicTrustedRoot.RekorLogs()
}

// NewNPMAttestationRecord creates a new Record from a bundle and a set of identifiers for NPM attestations
func NewNPMAttestationRecord(bundle *protobundle.Bundle, identifiers IdentifiersNPM, subjects []Subject, statement *in_toto.Statement) (*Record, error) {
	var cert *x509.Certificate
	var err error

	if chain := bundle.VerificationMaterial.GetX509CertificateChain(); chain != nil {
		if len(chain.Certificates) > 0 {
			// Extract the leaf certificate
			pemBytes := chain.Certificates[0].RawBytes
			cert, err = x509.ParseCertificate(pemBytes)
			if err != nil {
				return nil, err
			}
		}
	} else if leaf := bundle.VerificationMaterial.GetCertificate(); leaf != nil {
		cert, err = x509.ParseCertificate(leaf.RawBytes)
		if err != nil {
			return nil, err
		}
	}

	return &Record{
		DomainID:      identifiers.DomainID,
		Purl:          identifiers.Purl,
		SubjectDigest: subjects[0].SubjectDigest.String(),
		SubjectName:   subjects[0].Name,
		Certificate:   cert,
		MediaType:     bundle.MediaType,
		PredicateType: statement.PredicateType,
		StatementType: statement.Type,
		Statement:     statement,
		Subjects:      subjects,
	}, nil
}
