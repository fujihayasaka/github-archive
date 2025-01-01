package auth

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/github/notifyd/internal/pkg/tenancy"
)

func TestDummyAuthorizerAuthorizeRecipients(t *testing.T) {
	authorizer := DummyAuthorizer{}
	initiatorID := int64(1)
	userIDs := []int64{1, 2, 3}
	authzdAttributes := []*anypb.Any{}
	checks, err := authorizer.AuthorizeRecipients(context.Background(), tenancy.NewSingleTenant(), initiatorID, userIDs, authzdAttributes)
	require.NoError(t, err)

	require.Empty(t, checks)
}
