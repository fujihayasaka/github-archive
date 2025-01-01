package attestation

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
	"unicode/utf8"

	"time"

	in_toto "github.com/in-toto/attestation/go/v1"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"github.com/sigstore/sigstore-go/pkg/fulcio/certificate"
)

var (
	ErrInvalidCreatedPrefix = errors.New("created does not have a valid prefix: >, <, =")
	ErrInvalidDateFormat    = errors.New("created does not have a valid date format: YYYY-MM-DD")
	SubjectNameMaxLen       = 256
)

type CreatedFilter struct {
	Operator string
	Date     time.Time
}

// IdentifiersGitHub represents the identifiers for an attestation from GitHub
type IdentifiersGitHub struct {
	ID                       uint64
	Created                  CreatedFilter
	DomainID                 uint32
	OwnerID                  *uint64
	RepositoryID             *uint64
	PredicateType            string
	SubjectDigest            string
	SubjectDigests           []string
	SubjectName              string
	TenantID                 uint64
	ExpectReleaseAttestation bool
}

// ParseSubjectName validates the subject name filter and returns the
// filter with MySQL wildcard characters added.
// It uses the same restrictions in place on the subject_name
// column in the attestations_subjects table defined in db/schema/attestations_subjects.sql
func ParseSubjectName(raw string) (string, error) {
	if raw == "" {
		return "", nil
	}

	if !utf8.ValidString(raw) {
		return "", fmt.Errorf("string is not valid UTF-8")
	}
	if len(raw) > SubjectNameMaxLen {
		return "", fmt.Errorf("string exceeds maximum length of %d characters", SubjectNameMaxLen)
	}

	// escape literal % and _ characters since those are MySQL wildcard characters
	escaped := strings.ReplaceAll(raw, "%", "\\%")
	escaped = strings.ReplaceAll(escaped, "_", "\\_")

	// Add the MySQL wildcard character %,  which will be used in the
	// SQL query to match any substring of the subject name
	withMySQLWildcards := "%" + escaped + "%"
	return withMySQLWildcards, nil
}

// ValidateCreateArg validates the user has provided a creation date
// argument in the following format <operator>YYYY-MM-DD
// where <operator> is one of the following: >, <, =
// Once validated, it converts the date into a time.Time object
// with UTC timezone
func ValidateCreateArg(created string) (CreatedFilter, error) {
	if created == "" {
		return CreatedFilter{}, nil
	}
	operator := string(created[0])
	date := string(created[1:])
	// argument must have one of the following prefixes: >, <, =
	if operator != ">" && operator != "<" && operator != "=" {
		return CreatedFilter{}, ErrInvalidCreatedPrefix
	}
	// argument date must be in format YYYY-MM-DD
	parsed, err := time.ParseInLocation("2006-01-02", date, time.UTC)
	if err != nil {
		return CreatedFilter{}, ErrInvalidDateFormat
	}
	return CreatedFilter{
		Operator: operator,
		Date:     parsed,
	}, nil
}

func EnforceLength[T string | uint64](batch []T, name string) ([]T, error) {
	if len(batch) > SubjectLimit {
		return nil, fmt.Errorf("too many %s provided, limit is %d", name, SubjectLimit)
	}
	return deduplicateSlice(batch), nil
}

func deduplicateSlice[T string | uint64](batch []T) []T {
	seen := make(map[T]struct{})
	var deduped []T
	for _, b := range batch {
		if _, ok := seen[b]; !ok {
			seen[b] = struct{}{}
			deduped = append(deduped, b)
		}
	}
	return deduped
}

// NewGitHubAttestationRecord creates a new Record from a bundle and a set of identifiers
func NewGitHubAttestationRecord(bundle *protobundle.Bundle, identifiers IdentifiersGitHub, subjects []Subject, statement *in_toto.Statement) (*Record, error) {
	r, err := newAttestationRecord(bundle, subjects, statement)
	if err != nil {
		return nil, err
	}

	r.DomainID = identifiers.DomainID
	r.OwnerID = identifiers.OwnerID
	r.RepositoryID = identifiers.RepositoryID
	r.TenantID = identifiers.TenantID

	return r, nil
}

func NewGitHubReleaseAttestationRecord(bundle *protobundle.Bundle, identifiers IdentifiersGitHub, subjects []Subject, statement *in_toto.Statement, tag string) (*Record, error) {
	r, err := NewGitHubAttestationRecord(bundle, identifiers, subjects, statement)
	if err != nil {
		return nil, err
	}
	r.Tag = tag
	return r, nil
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
