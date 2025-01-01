//go:build integration
// +build integration

package handlers_test

import (
	"context"
	"encoding/json"
	"strconv"
	"sync"
	"testing"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/licensify/internal/models"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/github/licensify/testing/integration"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDeleteEnablementsHandlerUpdatesExistingLicenses(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()
	handler := client.NewDeleteEnablementsHandler()
	// Create a customer license with an organization enablement.
	customerID := stubs.NewRandomID()
	orgID1 := stubs.NewRandomID()
	orgID2 := stubs.NewRandomID()

	userID1 := stubs.NewRandomID()
	userID2 := stubs.NewRandomID()

	licenses := []*models.CustomerLicense{
		models.NewCustomerLicenseForUserWithOrgMemberships(
			customerID, userID1, orgID1,
		),
		models.NewCustomerLicenseForUserWithOrgMemberships(
			customerID, userID2, orgID1, orgID2,
		),
	}
	for _, license := range licenses {
		_, err := customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license.ToProto()})
		require.NoError(t, err)
	}

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err := customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	require.NoError(t, err)

	jobPayload, err := json.Marshal(&models.DeleteEnablementsJob{
		CustomerID:       customerID,
		EnablementReason: models.EnablementReasonOrgMembership,
		EnablementID:     orgID1,
	})
	require.NoError(t, err)

	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job}
	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	// Verify that the organization enablement was removed.
	resp, err := customerLicenseClient.GetCustomerLicenses(
		context.Background(),
		&proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC},
	)
	require.NoError(t, err)
	assert.Len(t, resp.CustomerLicenses, 1)

	cl := models.NewCustomerLicenseFromProto(resp.CustomerLicenses[0])
	assert.Equal(t, strconv.FormatUint(userID2, 10), cl.Licensee.ID)

	enablement := cl.GetEnablementFor(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership)
	assert.ElementsMatch(t, []uint64{orgID2}, enablement.EnablementIDs)
}

func TestDeleteEnablementsHandlerAllowsConcurrentUpdates(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()
	handler := client.NewDeleteEnablementsHandler()

	// Create a customer license with an organization enablement.
	customerID := stubs.NewRandomID()
	orgID1 := stubs.NewRandomID()
	orgID2 := stubs.NewRandomID()

	userID1 := stubs.NewRandomID()
	userID2 := stubs.NewRandomID()

	licenses := []*models.CustomerLicense{
		models.NewCustomerLicenseForUserWithOrgMemberships(
			customerID, userID1, orgID1,
		),
		models.NewCustomerLicenseForUserWithOrgMemberships(
			customerID, userID2, orgID1, orgID2,
		),
	}
	for _, license := range licenses {
		_, err := customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license.ToProto()})
		require.NoError(t, err)
	}

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err := customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	require.NoError(t, err)

	// send two delete org memberships jobs concurrently
	jobPayload1, err := json.Marshal(&models.DeleteEnablementsJob{
		CustomerID:       customerID,
		EnablementReason: models.EnablementReasonOrgMembership,
		EnablementID:     orgID1,
	})
	require.NoError(t, err)
	job1 := &aqueduct.Job{Payload: jobPayload1}
	rr1 := &aqueduct.ReceiveResult{Job: *job1}

	jobPayload2, err := json.Marshal(&models.DeleteEnablementsJob{
		CustomerID:       customerID,
		EnablementReason: models.EnablementReasonOrgMembership,
		EnablementID:     orgID2,
	})
	require.NoError(t, err)
	job2 := &aqueduct.Job{Payload: jobPayload2}
	rr2 := &aqueduct.ReceiveResult{Job: *job2}

	wg := new(sync.WaitGroup)
	wg.Add(2)
	go func() {
		defer wg.Done()
		require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr1))
	}()
	go func() {
		defer wg.Done()
		require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr2))
	}()
	wg.Wait()

	// Verify both organization enablements were removed, resulting in both licenses being deleted.
	resp, err := customerLicenseClient.GetCustomerLicenses(
		context.Background(),
		&proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC},
	)
	require.NoError(t, err)
	assert.Len(t, resp.CustomerLicenses, 0)
}
