package auth

import (
	"context"

	"google.golang.org/protobuf/types/known/anypb"

	"github.com/github/notifyd/internal/pkg/tenancy"
)

// DummyAuthorizer will authorize all recipients by default and may be useful for integration tests
// It should not be used in production code
type DummyAuthorizer struct {
}

// NewDummyAuthorizer creates a new DummyAuthorizer
func NewDummyAuthorizer() *DummyAuthorizer {
	return &DummyAuthorizer{}
}

// AuthorizeRecipients authorizes recipients.
func (authorizer *DummyAuthorizer) AuthorizeRecipients(ctx context.Context, tenant tenancy.Tenant, initiatorID int64, recipients []int64, attributes []*anypb.Any) (PolicyCheckLookup, error) {
	return make(PolicyCheckLookup, 0), nil
}
