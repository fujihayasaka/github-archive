package auth

import (
	"context"
	"sort"

	"github.com/stretchr/testify/mock"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/github/notifyd/internal/pkg/tenancy"
)

// AuthzdAuthorizerStub is a stub for the authzd authorizer.
type AuthzdAuthorizerStub struct {
	mock.Mock
}

// AuthorizeRecipients authorizes recipients.
func (m *AuthzdAuthorizerStub) AuthorizeRecipients(ctx context.Context, tenant tenancy.Tenant, initiatorID int64, recipients []int64, commonAttributes []*anypb.Any) (PolicyCheckLookup, error) {
	// make sure user ids are sorted so we can make assertions easier
	sort.Slice(recipients, func(i, j int) bool { return recipients[i] < recipients[j] })
	args := m.Called(ctx, tenant, initiatorID, recipients, commonAttributes)
	return args.Get(0).(PolicyCheckLookup), args.Error(1) //nolint:forcetypeassert,revive // type known, and is a stub
}
