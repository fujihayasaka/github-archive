package boo

import (
	"context"

	proto "github.com/github/attester/gen/go/attester/v0"

	"github.com/github/attester/pkg/service"
	exceptions "github.com/github/go-exceptions"
)

var _ Service = (*Boo)(nil)
var _ service.Service = (*Boo)(nil)

// An interface is defined here so we can create
// structs for testing that fulfill the interface
type Service interface {
	// Attester API
	HelloName(context.Context, *proto.HelloNameRequest) (*proto.HelloNameResponse, error)
	Error(context.Context, *proto.HelloNameRequest) (*proto.HelloNameResponse, error)
}

type Boo struct {
	reporter *exceptions.Reporter
}

// TODO: remove this when attester is production ready
// NewBoo creates a new dummy service.
func NewBoo(reporter *exceptions.Reporter) (*Boo, error) {
	return &Boo{
		reporter: reporter,
	}, nil
}

func (boo *Boo) GetName() string {
	return "boo"
}
