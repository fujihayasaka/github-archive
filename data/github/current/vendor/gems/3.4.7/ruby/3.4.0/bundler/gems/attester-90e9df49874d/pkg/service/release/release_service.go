package release

import (
	"context"

	proto "github.com/github/attester/gen/go/attester/v0"
	"github.com/github/attester/pkg/clients"
	"github.com/github/attester/pkg/service"
	exceptions "github.com/github/go-exceptions"
)

var _ Service = (*Release)(nil)
var _ service.Service = (*Release)(nil)

// An interface is defined here so we can create
// structs for testing that fulfill the interface
type Service interface {
	CreateReleaseAttestation(context.Context, *proto.CreateReleaseAttestationRequest) (*proto.CreateReleaseAttestationResponse, error)
}

type Release struct {
	reporter *exceptions.Reporter
	attester *clients.Attester
}

// NewRelease creates a new Release service.
func NewRelease(attester *clients.Attester, reporter *exceptions.Reporter) (*Release, error) {
	return &Release{
		reporter: reporter,
		attester: attester,
	}, nil
}

func (release *Release) GetName() string {
	return "release"
}
