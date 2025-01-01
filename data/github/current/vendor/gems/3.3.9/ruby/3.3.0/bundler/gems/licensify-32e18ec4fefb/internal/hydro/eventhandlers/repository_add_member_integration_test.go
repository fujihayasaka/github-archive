//go:build integration
// +build integration

package eventhandlers_test

import (
	"context"
	"testing"

	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/github/licensify/testing/integration"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRepositoryCollaboratorAddsCollaborator(t *testing.T) {
	client := integration.NewTestClient(t)

	customerLicenseClient, _, _, _ := client.StartTwirpServer()
	handler := client.EventHandler

	// Process the repository add member hydro message
	msg := stubs.NewRepositoryCollaboratorAddHydroMsg()

	_, herr := handler.HandleRepositoryAddMember(context.Background(), client.Logger, msg)
	require.NoError(t, herr.Err)

	// Get the customer license
	getReq := &proto.GetCustomerLicensesRequest{CustomerId: uint64(msg.RepositoryOwnerCustomerId), Product: proto.Product_PRODUCT_SDLC}
	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	require.NoError(t, err)
	assert.Len(t, resp.CustomerLicenses, 1)

	cl := resp.CustomerLicenses[0]
	assert.Equal(t, uint64(msg.RepositoryOwnerCustomerId), cl.GetCustomerId())
	assert.Equal(t, uint64(msg.GetMember().GetId()), cl.GetLicensee().GetIdDeprecated())
	assert.Equal(t, proto.Product_PRODUCT_SDLC, cl.GetProduct())
	assert.Len(t, cl.Enablements, 1)
	assert.Equal(t, proto.EnablementReason_ENABLEMENT_REASON_REPOSITORY_COLLABORATOR, cl.Enablements[0].Reason)
	assert.Equal(t, proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_REPO, cl.Enablements[0].Type)
	assert.ElementsMatch(t, []uint64{uint64(msg.GetRepository().GetId())}, cl.Enablements[0].EnablementIds)
}
