package attestation

import (
	"crypto/x509"
	"errors"
	"fmt"
	"slices"
	"time"

	in_toto "github.com/in-toto/attestation/go/v1"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
)

const (
	// SubjectLimit is the maximum number of subjects allowed for an attestation
	SubjectLimit = 1024
	// MaxSubjectNameLength matches the attestations_subjects.subject_name db column size
	MaxSubjectNameLength = 256
	// MaxSubjectDigestLength matches the attestations_subjects.subject_digest db column size
	MaxSubjectDigestLength = 256
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
	// Releases
	Tag string `json:"tag"`
}

var ErrInvalidStatement = errors.New("invalid statement")
var ErrDuplicateDigest = errors.New("duplicate subject in statement")
var ErrNoSubject = fmt.Errorf("%w: no statement subjects", ErrInvalidStatement)
var ErrTooManySubjects = fmt.Errorf("%w: %d subject limit exceeded", ErrInvalidStatement, SubjectLimit)
var ErrMustHaveOneDigest = fmt.Errorf("%w: must have exactly one digest", ErrInvalidStatement)

// ErrSubjectNameLengthExceeded is returned when the subject name length exceeds 256 characters.
var ErrSubjectNameLengthExceeded = func(name string) error {
	return fmt.Errorf("subject name length exceeded 256 characters: %s", name)
}

// ErrSubjectDigestLengthExceeded is returned when the subject digest length exceeds 256 characters.
var ErrSubjectDigestLengthExceeded = func(name string) error {
	return fmt.Errorf("subject digest length exceeded 256 characters: %s", name)
}

// ValidateStatement validates the in-toto statement and returns the subject digest.
func ValidateStatement(statement *in_toto.Statement) ([]Subject, error) {
	subjects := []Subject{}

	if len(statement.Subject) == 0 {
		return subjects, ErrNoSubject
	}

	if len(statement.Subject) > SubjectLimit {
		return subjects, ErrTooManySubjects
	}

	// Iterate over the subjects in the statement.
	// Detect duplicates and return error if present.
	for _, subject := range statement.Subject {
		// return error if name length exceeds database column size
		if len(subject.Name) > MaxSubjectNameLength {
			return []Subject{}, ErrSubjectNameLengthExceeded(subject.Name)
		}

		// get the digest of this subject
		subjectDigest, err := getDigest(subject.Digest)
		if err != nil {
			return []Subject{}, err
		}

		// return error if digest length exceeds database column size
		if len(subjectDigest.Digest) > MaxSubjectDigestLength {
			return []Subject{}, ErrSubjectDigestLengthExceeded(subjectDigest.Digest)
		}

		// If this subject has a URI, use that as the name. Otherwise, use the name.
		subjectName := subject.Name
		if subject.Uri != "" {
			subjectName = subject.Uri
		}

		stmt := Subject{
			Name:          subjectName,
			SubjectDigest: subjectDigest,
		}

		if slices.Contains(subjects, stmt) {
			return []Subject{}, ErrDuplicateDigest
		}
		subjects = append(subjects, stmt)
	}

	return subjects, nil
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

// newAttestationRecord creates a new Record from a bundle
func newAttestationRecord(bundle *protobundle.Bundle, subjects []Subject, statement *in_toto.Statement) (*Record, error) {
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
		Certificate:   cert,
		MediaType:     bundle.MediaType,
		PredicateType: statement.PredicateType,
		StatementType: statement.Type,
		Statement:     statement,
		Subjects:      subjects,
	}, nil
}
