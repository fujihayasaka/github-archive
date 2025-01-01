package attestation

import (
	"errors"
	"fmt"

	release "github.com/in-toto/attestation/go/predicates/release/v0"
	"github.com/package-url/packageurl-go"
	"google.golang.org/protobuf/encoding/protojson"

	"github.com/sigstore/sigstore-go/pkg/verify"
)

// VerifyReleaseStatement verifies the release statement and returns the release tag
func VerifyReleaseStatement(res *verify.VerificationResult, releasesSAN string) (string, error) {
	if res.Statement.PredicateType != PredicateRelease {
		return "", fmt.Errorf("this endpoint only supports release attestations with predicate type \"%s\"", PredicateRelease)
	}

	// validate and extract the purl from the predicate
	b, err := protojson.Marshal(res.Statement.Predicate)
	if err != nil {
		return "", fmt.Errorf("error marshalling predicate: %w", err)
	}
	var releasePredicate release.Release
	err = protojson.UnmarshalOptions{DiscardUnknown: true}.Unmarshal(b, &releasePredicate)
	if err != nil {
		return "", fmt.Errorf("error unmarshalling predicate: %w", err)
	}
	p, err := packageurl.FromString(releasePredicate.Purl)
	if err != nil {
		return "", fmt.Errorf("error parsing release purl: %w", err)
	}

	if res.Signature.Certificate.SubjectAlternativeName != releasesSAN {
		return "", errors.New("invalid certificate subject alternative name")
	}

	return p.Version, nil
}
