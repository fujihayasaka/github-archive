//go:build integration
// +build integration

package handlers_test

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/licensify/internal/models"
	repositoriesV1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/github/licensify/testing/integration"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestCreateRepositoryCollaboratorsHandlerCreatesNewLicense(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, _, _ := client.StartTwirpServer()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewCreateRepositoryCollaboratorsHandler(monolithClient)

	customerID := stubs.NewRandomID()
	repositoryID := stubs.NewRandomID()
	collaboratorID := stubs.NewRandomID()

	request := &repositoriesV1.GetRepositoryInformationRequest{
		Id:                   repositoryID,
		IncludeCollaborators: true,
	}
	repoResponse := stubs.NewRepositoryFromHydroEntity()
	repoResponse.Id = repositoryID
	repoResponse.OwnerCustomerId = int64(customerID)
	response := &repositoriesV1.GetRepositoryInformationResponse{
		Repository:      repoResponse,
		CollaboratorIds: []uint64{collaboratorID},
	}
	mockMonolithAPI.On("GetRepositoryInformation", mock.Anything, request).Return(response, nil).Once()

	jobPayload := &models.CreateRepositoryCollaboratorsJob{RepositoryID: repositoryID}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)
	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}

	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 1)

	wantLicenses := []*proto.CustomerLicense{
		models.NewCustomerLicenseForUserWithMemberships(customerID, collaboratorID, nil, []uint64{repositoryID}).ToProto(),
	}

	assert.ElementsMatch(t, resp.CustomerLicenses, wantLicenses)
}

func TestCreateRepositoryCollaboratorsHandlerUpdatesExistingCollaboratorLicense(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, _, _ := client.StartTwirpServer()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewCreateRepositoryCollaboratorsHandler(monolithClient)

	customerID := stubs.NewRandomID()
	repositoryID1 := stubs.NewRandomID()
	repositoryID2 := stubs.NewRandomID()
	collaboratorID := stubs.NewRandomID()

	license := models.NewCustomerLicenseForUserWithRepositoryCollaborator(
		customerID, collaboratorID, repositoryID1,
	)
	_, err := customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license.ToProto()})
	require.NoError(t, err)

	request := &repositoriesV1.GetRepositoryInformationRequest{
		Id:                   repositoryID2,
		IncludeCollaborators: true,
	}
	repoResponse := stubs.NewRepositoryFromHydroEntity()
	repoResponse.Id = repositoryID2
	repoResponse.OwnerCustomerId = int64(customerID)
	response := &repositoriesV1.GetRepositoryInformationResponse{
		Repository:      repoResponse,
		CollaboratorIds: []uint64{collaboratorID},
	}
	mockMonolithAPI.On("GetRepositoryInformation", mock.Anything, request).Return(response, nil).Once()

	jobPayload := &models.CreateRepositoryCollaboratorsJob{RepositoryID: repositoryID2}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)
	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}

	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 1)

	wantLicenses := []*proto.CustomerLicense{
		models.NewCustomerLicenseForUserWithMemberships(customerID, collaboratorID, nil, []uint64{repositoryID1, repositoryID2}).ToProto(),
	}

	assert.ElementsMatch(t, resp.CustomerLicenses, wantLicenses)
}

func TestCreateRepositoryCollaboratorsHandlerUpdatesExistingOrgMembershipLicense(t *testing.T) {
	client := integration.NewTestClient(t)
	customerLicenseClient, _, _, _ := client.StartTwirpServer()
	monolithClient, mockMonolithAPI := client.StartMonolithTwirpServer()
	handler := client.NewCreateRepositoryCollaboratorsHandler(monolithClient)

	customerID := stubs.NewRandomID()
	repositoryID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()
	collaboratorID := stubs.NewRandomID()

	license := models.NewCustomerLicenseForUserWithOrgMemberships(
		customerID, collaboratorID, orgID,
	)
	_, err := customerLicenseClient.UpsertCustomerLicense(context.Background(), &proto.UpsertCustomerLicenseRequest{CustomerLicense: license.ToProto()})
	require.NoError(t, err)

	request := &repositoriesV1.GetRepositoryInformationRequest{
		Id:                   repositoryID,
		IncludeCollaborators: true,
	}
	repoResponse := stubs.NewRepositoryFromHydroEntity()
	repoResponse.Id = repositoryID
	repoResponse.OwnerCustomerId = int64(customerID)
	response := &repositoriesV1.GetRepositoryInformationResponse{
		Repository:      repoResponse,
		CollaboratorIds: []uint64{collaboratorID},
	}
	mockMonolithAPI.On("GetRepositoryInformation", mock.Anything, request).Return(response, nil).Once()

	jobPayload := &models.CreateRepositoryCollaboratorsJob{RepositoryID: repositoryID}
	payload, err := json.Marshal(jobPayload)
	require.NoError(t, err)
	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}

	require.NoError(t, handler.ProcessMessage(context.Background(), client.Logger, *rr))

	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC})
	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 1)

	wantLicenses := []*proto.CustomerLicense{
		models.NewCustomerLicenseForUserWithMemberships(customerID, collaboratorID, []uint64{orgID}, []uint64{repositoryID}).ToProto(),
	}

	assert.ElementsMatch(t, resp.CustomerLicenses, wantLicenses)
}
