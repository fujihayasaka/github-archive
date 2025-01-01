package attestation

import (
	"crypto/x509"
	"errors"
	"regexp"

	in_toto "github.com/in-toto/attestation/go/v1"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"github.com/sigstore/sigstore-go/pkg/fulcio/certificate"
)

// Identifiers represents the identifiers for an attestation from GitHub
type IdentifiersGitHub struct {
	ID                        uint64
	DomainID                  uint32
	OwnerID                   *uint64
	RepositoryID              *uint64
	PredicateType             string
	SubjectDigest             string
	TenantID                  uint64
	VerifyProvenanceStatement bool
}

// NewGitHubAttestationRecord creates a new Record from a bundle and a set of identifiers
func NewGitHubAttestationRecord(bundle *protobundle.Bundle, identifiers IdentifiersGitHub, subjects []Subject, statement *in_toto.Statement) (*Record, error) {
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
		OwnerID:       identifiers.OwnerID,
		RepositoryID:  identifiers.RepositoryID,
		TenantID:      identifiers.TenantID,
		Certificate:   cert,
		MediaType:     bundle.MediaType,
		PredicateType: statement.PredicateType,
		StatementType: statement.Type,
		Statement:     statement,
		Subjects:      subjects,
	}, nil
}

// ValidateCertificateIssuerIsFromGitHub validates that the certificate issuer is from GitHub
func ValidateCertificateIssuerIsFromGitHub(certSummary *certificate.Summary) error {
	// Define the regex pattern for the GitHub issuer (w/ optional enterprise slug)
	githubIssuerPattern := `^https://token\.actions\.githubusercontent\.com(/[a-zA-Z0-9-]+)?$`
	githubIssuerRegex := regexp.MustCompile(githubIssuerPattern)

	// Define the regex pattern for the Proxima issuer
	proximaIssuerPattern := `^https://token\.actions\.[a-zA-Z0-9-]+\.ghe\.com(/[a-zA-Z0-9-]+)?$`
	proximaIssuerRegex := regexp.MustCompile(proximaIssuerPattern)

	// Check if the issuer matches GitHubIssuer or the Proxima issuer pattern
	if !githubIssuerRegex.MatchString(certSummary.Extensions.Issuer) && !proximaIssuerRegex.MatchString(certSummary.Extensions.Issuer) {
		return errors.New("issuer is not GitHub")
	}
	return nil
}
