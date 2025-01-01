package release

import (
	"context"
	"fmt"

	proto "github.com/github/attester/gen/go/attester/v0"
	"github.com/github/attester/pkg/o11y"
	"github.com/github/attester/pkg/service"
	"github.com/sigstore/sigstore-go/pkg/sign"
	"google.golang.org/protobuf/encoding/protojson"
)

const (
	StatementType        = "https://in-toto.io/Statement/v1"
	ReleasePredicateType = "https://in-toto.io/attestation/release/v0.1"
)

var (
	ErrBadStatementType = fmt.Errorf("statement type must be '%s'", StatementType)
	ErrBadPredicateType = fmt.Errorf("predicate type must be '%s'", ReleasePredicateType)
)

func (release *Release) CreateReleaseAttestation(ctx context.Context, request *proto.CreateReleaseAttestationRequest) (*proto.CreateReleaseAttestationResponse, error) {
	_, span := o11y.NamedSpan(ctx, "CreateReleaseAttestation")
	defer span.End()
	statement := request.GetStatement()

	// Ensure statement type is correct
	if statement.Type != StatementType {
		return nil, service.NewBadRequestError(ErrBadStatementType)
	}

	// Ensure statement predicate type is correct
	if statement.PredicateType != ReleasePredicateType {
		return nil, service.NewBadRequestError(ErrBadPredicateType)
	}

	// unmarshal the statement to []byte
	byteStatement, err := protojson.Marshal(statement)
	if err != nil {
		return nil, err
	}

	content := &sign.DSSEData{
		Data:        []byte(byteStatement),
		PayloadType: "application/vnd.in-toto+json",
	}

	bundle, err := release.attester.Bundle(content)
	if err != nil {
		return nil, err
	}
	return &proto.CreateReleaseAttestationResponse{
		Bundle: bundle,
	}, nil
}
