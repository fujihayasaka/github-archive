package attestation

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestValidateFreeFormPredicateType_GlobMatch(t *testing.T) {
	customPredicateType := "https://mystuff.dev/Template/*"
	_, err := validateFreeFormPredicateType(customPredicateType)
	assert.NoError(t, err)
}

func TestValidateFreeFormPredicateType_CompleteTypeString(t *testing.T) {
	customPredicateType := "https://mydev.org/someDocument/v1"
	_, err := validateFreeFormPredicateType(customPredicateType)
	assert.NoError(t, err)
}

func TestValidateFreeFormPredicateType_InvalidCharacters(t *testing.T) {
	customPredicateType := "https://@@@mydev.org/someDocument/v1"
	_, err := validateFreeFormPredicateType(customPredicateType)
	assert.Error(t, err)
}
