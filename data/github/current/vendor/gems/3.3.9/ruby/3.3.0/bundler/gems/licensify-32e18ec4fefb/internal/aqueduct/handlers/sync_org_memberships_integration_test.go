//go:build integration
// +build integration

package handlers_test

import (
	"context"
	"encoding/json"
	"sync"
	"testing"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/licensify/internal/models"
	customersV1 "github.com/github/licensify/lib/monolith-twirp/customers/v1"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/github/licensify/testing/integration"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestSyncingCustomerWithoutExistingLicenses(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewSyncOrgMembershipsHandler(monolithClient)

	customerID := stubs.NewRandomID()

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err := customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	require.NoError(t, err)

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: 100, OrganizationMemberships: []uint64{10, 11}},
			{Id: 200, OrganizationMemberships: []uint64{10}, CollaboratingRepositories: []uint64{100}},
			{Id: 300, CollaboratingRepositories: []uint64{200}},
		},
	}
	mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	jobPayload := &models.SyncOrganizationMembershipsJob{
		EntityType: models.SyncEntityTypeCustomer,
		EntityID:   customerID,
	}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)
	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 3)

	wantLicenses := []*proto.CustomerLicense{
		models.NewCustomerLicenseForUserWithMemberships(customerID, 100, []uint64{10, 11}, nil).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 200, []uint64{10}, []uint64{100}).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 300, nil, []uint64{200}).ToProto(),
	}

	assert.ElementsMatch(t, resp.CustomerLicenses, wantLicenses)
}

func TestSyncingCustomerWithExistingLicenses(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewSyncOrgMembershipsHandler(monolithClient)

	customerID := stubs.NewRandomID()
	// create existing licenses
	license1 := models.NewCustomerLicenseForUserWithMemberships(customerID, 100, []uint64{10, 11}, nil)
	license2 := models.NewCustomerLicenseForUserWithMemberships(customerID, 200, []uint64{10}, nil)
	license3 := models.NewCustomerLicenseForUserWithMemberships(customerID, 300, nil, []uint64{100})
	license4 := models.NewCustomerLicenseForUserWithMemberships(customerID, 400, nil, []uint64{100})
	license5 := models.NewCustomerLicenseForUserWithMemberships(customerID, 500, []uint64{10}, nil)
	license6 := models.NewCustomerLicenseForUserWithMemberships(customerID, 600, nil, []uint64{100})

	licenses := []*models.CustomerLicense{license1, license2, license3, license4, license5, license6}
	for _, license := range licenses {
		_, err := customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license.ToProto()})
		require.NoError(t, err)
	}

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err := customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	require.NoError(t, err)

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: 100, OrganizationMemberships: []uint64{11}},
			{Id: 300, OrganizationMemberships: []uint64{11}},
			{Id: 500, CollaboratingRepositories: []uint64{200, 300}},
			{Id: 600, CollaboratingRepositories: []uint64{100}},
			{Id: 700, OrganizationMemberships: []uint64{12}, CollaboratingRepositories: []uint64{100}},
			{Id: 800, CollaboratingRepositories: []uint64{100}},
		},
	}
	mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	jobPayload := &models.SyncOrganizationMembershipsJob{
		EntityType: models.SyncEntityTypeCustomer,
		EntityID:   customerID,
	}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 6)

	// userID 100 is updated from orgs {10, 11} -> {11}
	// userID 200 has been removed from all orgs -> deleted
	// userID 300 is updated from orgs {} -> {11} + repos {100} -> {}
	// userID 400 has been removed from all repos -> deleted
	// userID 500 is updated from repos {100} -> {200, 300}
	// userID 600 has been removed from all orgs, added to repo {100} -> updated
	// userID 700 is created with orgs {12} + repos {300}
	// userID 800 is created with repos {100}
	wantLicenses := []*proto.CustomerLicense{
		models.NewCustomerLicenseForUserWithMemberships(customerID, 100, []uint64{11}, nil).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 300, []uint64{11}, nil).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 500, nil, []uint64{200, 300}).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 600, nil, []uint64{100}).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 700, []uint64{12}, []uint64{100}).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 800, nil, []uint64{100}).ToProto(),
	}

	assert.ElementsMatch(t, resp.CustomerLicenses, wantLicenses)
}

func TestSyncingCustomerWhenNoUsersAreReturned(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewSyncOrgMembershipsHandler(monolithClient)

	customerID := stubs.NewRandomID()
	// create existing licenses
	license1 := models.NewCustomerLicenseForUserWithMemberships(customerID, 100, []uint64{10, 11}, nil)
	license2 := models.NewCustomerLicenseForUserWithMemberships(customerID, 200, []uint64{10}, []uint64{100})

	customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license1.ToProto()})
	customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license2.ToProto()})

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err := customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	require.NoError(t, err)

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users:      []*customersV1.User{},
	}
	mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	jobPayload := &models.SyncOrganizationMembershipsJob{
		EntityType: models.SyncEntityTypeCustomer,
		EntityID:   customerID,
	}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 0)
}

func TestSyncSingleOrgCreatesNewLicenses(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewSyncOrgMembershipsHandler(monolithClient)

	customerID := stubs.NewRandomID()

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err := customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	require.NoError(t, err)

	orgID := stubs.NewRandomID()
	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_ORGANIZATION,
		EntityId:   orgID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: 100, OrganizationMemberships: []uint64{orgID}},
			{Id: 200, OrganizationMemberships: []uint64{orgID}},
		},
	}
	mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	jobPayload := &models.SyncOrganizationMembershipsJob{
		EntityType: models.SyncEntityTypeOrganization,
		EntityID:   orgID,
	}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)
	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 2)

	wantLicenses := []*proto.CustomerLicense{
		models.NewCustomerLicenseForUserWithMemberships(customerID, 100, []uint64{orgID}, nil).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 200, []uint64{orgID}, nil).ToProto(),
	}

	assert.ElementsMatch(t, resp.CustomerLicenses, wantLicenses)
}

func TestSyncSingleOrgUpdatesExistingLicenses(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewSyncOrgMembershipsHandler(monolithClient)

	customerID := stubs.NewRandomID()
	org1 := stubs.NewRandomID()
	org2 := stubs.NewRandomID()
	org3 := stubs.NewRandomID()
	repo1 := stubs.NewRandomID()

	// create existing licenses
	license1 := models.NewCustomerLicenseForUserWithMemberships(customerID, 100, []uint64{org1, org2}, nil)
	license2 := models.NewCustomerLicenseForUserWithMemberships(customerID, 200, []uint64{org1}, nil)
	license3 := models.NewCustomerLicenseForUserWithMemberships(customerID, 300, []uint64{org1, org3}, nil)
	license4 := models.NewCustomerLicenseForUserWithMemberships(customerID, 500, nil, []uint64{repo1})

	licenses := []*models.CustomerLicense{license1, license2, license3, license4}
	for _, license := range licenses {
		_, err := customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license.ToProto()})
		require.NoError(t, err)
	}

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err := customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	require.NoError(t, err)

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_ORGANIZATION,
		EntityId:   org1,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: 100, OrganizationMemberships: []uint64{org1}},
			{Id: 400, OrganizationMemberships: []uint64{org1}},
		},
	}
	mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	jobPayload := &models.SyncOrganizationMembershipsJob{
		EntityType: models.SyncEntityTypeOrganization,
		EntityID:   org1,
	}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 4)

	// userID 100 not changed
	// userID 200 has been removed from org1 and no orgs left -> deleted
	// userID 300 has been removed from org1 and 1 org left -> updated
	// userID 400 is new -> created
	// userID 500 has been added to repo2 but repo memberships are not synced for single orgs -> no change
	wantLicenses := []*proto.CustomerLicense{
		models.NewCustomerLicenseForUserWithMemberships(customerID, 100, []uint64{org1, org2}, nil).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 300, []uint64{org3}, nil).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 400, []uint64{org1}, nil).ToProto(),
		models.NewCustomerLicenseForUserWithMemberships(customerID, 500, nil, []uint64{repo1}).ToProto(),
	}

	assert.ElementsMatch(t, resp.CustomerLicenses, wantLicenses)
}

func TestSyncSingleOrgWhenNoUsersReturned(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewSyncOrgMembershipsHandler(monolithClient)

	customerID := stubs.NewRandomID()
	org1 := stubs.NewRandomID()
	org2 := stubs.NewRandomID()

	// create existing licenses
	license1 := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, 100, org1, org2)
	license2 := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, 200, org1)

	customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license1.ToProto()})
	customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license2.ToProto()})

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err := customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	require.NoError(t, err)

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_ORGANIZATION,
		EntityId:   org1,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users:      []*customersV1.User{},
	}
	mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	jobPayload := &models.SyncOrganizationMembershipsJob{
		EntityType: models.SyncEntityTypeOrganization,
		EntityID:   org1,
	}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 1)

	// org1 has no users so it should be removed from all licenses
	wantLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, 100, org2).ToProto()
	assert.Equal(t, wantLicense, resp.CustomerLicenses[0])
}

func TestSyncingCustomerCreatesLicenseeLicenses(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()
	licenseeLicenseEngine := client.NewLicenseeLicenseEngine()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewSyncOrgMembershipsHandler(monolithClient)

	customerID := stubs.NewRandomID()

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err := customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	require.NoError(t, err)

	user1 := stubs.NewRandomID()
	user2 := stubs.NewRandomID()
	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: user1, OrganizationMemberships: []uint64{10, 11}},
			{Id: user2, OrganizationMemberships: []uint64{10}},
		},
	}
	mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	jobPayload := &models.SyncOrganizationMembershipsJob{
		EntityType: models.SyncEntityTypeCustomer,
		EntityID:   customerID,
	}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)
	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 2)

	wantLicenseeLicenses := []*models.LicenseeLicense{
		models.NewLicenseeLicenseForCustomerLicense(
			models.NewCustomerLicenseFromProto(resp.CustomerLicenses[0]),
		),
		models.NewLicenseeLicenseForCustomerLicense(
			models.NewCustomerLicenseFromProto(resp.CustomerLicenses[1]),
		),
	}

	for _, wantLicenseeLicense := range wantLicenseeLicenses {
		key := models.NewLicenseeLicenseKey(wantLicenseeLicense.Licensee.ID, wantLicenseeLicense.Licensee.Type, wantLicenseeLicense.Product, customerID)
		licenseeLicense, err := licenseeLicenseEngine.Get(context.Background(), client.Logger, *key)
		require.NoError(t, err)
		wantLicenseeLicense.ETag = licenseeLicense.ETag
		wantLicenseeLicense.Timestamp = licenseeLicense.Timestamp
		assert.Equal(t, wantLicenseeLicense, licenseeLicense)
	}
}

func TestAllowsConcurrentUpdates(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewSyncOrgMembershipsHandler(monolithClient)

	customerID := stubs.NewRandomID()
	// create existing licenses
	license1 := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, 100, 10, 11)
	license2 := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, 200, 10)

	_, err := customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license1.ToProto()})
	require.NoError(t, err)
	_, err = customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license2.ToProto()})
	require.NoError(t, err)

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err = customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	require.NoError(t, err)

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: 100, OrganizationMemberships: []uint64{11}},
			{Id: 300, OrganizationMemberships: []uint64{12}},
		},
	}
	mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Twice()

	jobPayload := &models.SyncOrganizationMembershipsJob{
		EntityType: models.SyncEntityTypeCustomer,
		EntityID:   customerID,
	}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	wg := new(sync.WaitGroup)
	wg.Add(2)
	go func() {
		defer wg.Done()
		require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))
	}()
	go func() {
		defer wg.Done()
		require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))
	}()
	wg.Wait()

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 2)

	// userID 100 is updated from {10, 11} to {11}
	// userID 200 has been removed from all orgs -> deleted
	// userID 300 is created with {12}
	wantLicenses := []*proto.CustomerLicense{
		models.NewCustomerLicenseForUserWithOrgMemberships(customerID, 100, 11).ToProto(),
		models.NewCustomerLicenseForUserWithOrgMemberships(customerID, 300, 12).ToProto(),
	}

	assert.ElementsMatch(t, resp.CustomerLicenses, wantLicenses)
}
