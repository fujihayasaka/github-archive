package attestation

import (
	"errors"
	"regexp"
)

// matches sentinel predicate type input included in requests to a pattern used for
// filtering attestations by predicate type
var patterns = map[string]string{
	"provenance": `https://slsa.dev/provenance/`,
	"sbom":       `^(https://spdx.dev/Document|https://cyclonedx.org/bom)`,
}

var ErrInvalidPredicateTypePattern = errors.New("invalid predicate type pattern")

func BuildPredicateTypePattern(predicateType string) (string, error) {
	// if no predicate type is provided, exit with the empty string, indicating predicate type matching will not be done
	if predicateType == "" {
		return "", nil
	}
	found, ok := patterns[predicateType]
	if !ok {
		return validateFreeFormPredicateType(predicateType)
	}
	return found, nil
}

func validateFreeFormPredicateType(predicateType string) (string, error) {
	freeFormPredicateType := regexp.MustCompile(`^[*:/.?\-=a-zA-Z0-9]+$`).MatchString
	if !freeFormPredicateType(predicateType) {
		return "", ErrInvalidPredicateTypePattern
	}
	return predicateType, nil
}
