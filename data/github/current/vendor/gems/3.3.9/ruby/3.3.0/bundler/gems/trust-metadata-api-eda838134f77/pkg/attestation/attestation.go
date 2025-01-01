package attestation

import (
	"crypto/x509"
	"fmt"
	"time"

	in_toto "github.com/in-toto/attestation/go/v1"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
)

// Subject represents the subject(s) of an attestation
type Subject struct {
	Name string
	SubjectDigest
}

// SubjectDigest represents the digest of an attestation subject
type SubjectDigest struct {
	Alg    string
	Digest string
}

func (d SubjectDigest) String() string {
	return fmt.Sprintf("%s:%s", d.Alg, d.Digest)
}

// PageInfo represents the paging information for a collection of attestation records
type PageInfo struct {
	EndCursor       uint64
	StartCursor     uint64
	HasNextPage     bool
	HasPreviousPage bool
}

// Records represents a collection of attestation records with paging information
type Records struct {
	Attestations []Record
	PageInfo     *PageInfo
}

// Record represents an attestation table row
type Record struct {
	Bundle        *protobundle.Bundle `json:"bundle"`
	Certificate   *x509.Certificate   `json:"certificate"`
	CreatedAt     time.Time           `json:"createdAt"`
	DomainID      uint32              `json:"domainId"`
	ID            uint64              `json:"id"`
	MediaType     string              `json:"mediaType"`
	PredicateType string              `json:"predicateType"`
	SASUrl        string              `json:"sasUrl"`
	Statement     *in_toto.Statement  `json:"statement"`
	StatementType string              `json:"statementType"`
	SubjectDigest string              `json:"subjectDigest"`
	SubjectName   string              `json:"subjectName"`
	Subjects      []Subject           `json:"subjects"`
	SubjectCount  uint64              `json:"subjectCount"`
	// npm
	Purl string `json:"purl"`
	// GitHub
	OwnerID      *uint64 `json:"ownerId"`
	RepositoryID *uint64 `json:"repositoryId"`
	TenantID     uint64  `json:"tenantId"`
}

var ErrInvalidStatement = fmt.Errorf("invalid statement")
var ErrMustHaveOneSubject = fmt.Errorf("%w: must have exactly one subject", ErrInvalidStatement)
var ErrMustHaveOneDigest = fmt.Errorf("%w: must have exactly one digest", ErrInvalidStatement)

// ValidateStatement validates the in-toto statement and returns the subject digest.
func ValidateStatement(statement *in_toto.Statement) ([]Subject, error) {
	if len(statement.Subject) != 1 {
		return []Subject{}, ErrMustHaveOneSubject
	}

	subject := statement.Subject[0]
	subjectDigest, err := getDigest(subject.Digest)
	if err != nil {
		return []Subject{}, fmt.Errorf("parseEnvelope: %w", err)
	}

	// If the subject has a URI, use that as the name. Otherwise, use the name.
	subjectName := subject.Name
	if subject.Uri != "" {
		subjectName = subject.Uri
	}

	return []Subject{
		{
			Name:          subjectName,
			SubjectDigest: subjectDigest,
		},
	}, nil
}

// getDigest returns the digest in the statement subject.
func getDigest(ds map[string]string) (SubjectDigest, error) {
	if len(ds) != 1 {
		return SubjectDigest{}, ErrMustHaveOneDigest
	}

	// Iterate through the map to get the first (and only) key.
	var alg, digest string
	// nolint:revive
	for alg, digest = range ds {
	}
	return SubjectDigest{alg, digest}, nil
}
