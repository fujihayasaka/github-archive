package release

import (
	"context"
	"testing"

	proto "github.com/github/attester/gen/go/attester/v0"
	v1 "github.com/in-toto/attestation/go/v1"
	"github.com/stretchr/testify/assert"
)

// Tests CreateReleaseAttestation with an invalid statement type
func TestInvalidStatementType(t *testing.T) {
	service := newReleaseService()

	request := &proto.CreateReleaseAttestationRequest{
		Statement: &v1.Statement{Type: "invalid-type"},
	}

	_, err := service.CreateReleaseAttestation(context.Background(), request)

	// Assert
	assert.Error(t, err)
	assert.EqualError(t, err, "statement type must be 'https://in-toto.io/Statement/v1'")
}

// Tests CreateReleaseAttestation with an invalid predicate type
func TestInvalidPredicateType(t *testing.T) {
	service := newReleaseService()

	request := &proto.CreateReleaseAttestationRequest{
		Statement: &v1.Statement{
			Type:          StatementType,
			PredicateType: "invalid-type",
		},
	}

	_, err := service.CreateReleaseAttestation(context.Background(), request)

	// Assert
	assert.Error(t, err)
	assert.EqualError(t, err, "predicate type must be 'https://in-toto.io/attestation/release/v0.1'")
}

func newReleaseService() *Release {
	return &Release{}
}
