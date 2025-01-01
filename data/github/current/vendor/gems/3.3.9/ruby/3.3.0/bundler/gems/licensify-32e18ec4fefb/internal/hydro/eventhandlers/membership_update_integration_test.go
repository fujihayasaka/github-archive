//go:build integration
// +build integration

package eventhandlers_test

import (
	"context"
	"testing"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/models"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/github/licensify/testing/integration"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
)

type membershipUpdateIntegrationSuite struct {
	suite.Suite
	client                *integration.Client
	customerLicenseClient proto.CustomerLicenseService
	customerClient        proto.CustomerService
	handler               *eventhandlers.EventHandler
}

func (s *membershipUpdateIntegrationSuite) SetupSuite() {
	client := integration.NewTestClient(s.T())
	customerLicenseClient, _, customerClient, _ := client.StartTwirpServer()

	s.client = client
	s.handler = client.EventHandler
	s.customerLicenseClient = customerLicenseClient
	s.customerClient = customerClient
}

func (s *membershipUpdateIntegrationSuite) upsertCustomerLicense(enablements []*proto.CustomerLicenseEnablement) *proto.CustomerLicense {
	s.T().Helper()
	customerLicenseProto := stubs.NewCustomerLicenseProto()
	customerLicenseProto.Enablements = enablements

	upsertReq := &proto.UpsertCustomerLicenseRequest{CustomerLicense: customerLicenseProto}
	_, err := s.customerLicenseClient.UpsertCustomerLicense(context.Background(), upsertReq)

	s.Require().NoError(err)

	return customerLicenseProto
}

func (s *membershipUpdateIntegrationSuite) TestMembershipUpdateCreatesNewLicenseWhenItDoesNotExist() {
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_ADD.Enum())
	customerID := msg.GetCustomerId()

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.client.Logger, msg)
	s.Require().NoError(herr.Err)

	// Get the customer license
	getReq := &proto.GetCustomerLicensesRequest{CustomerId: uint64(customerID), Product: proto.Product_PRODUCT_SDLC}
	resp, err := s.customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	s.Require().NoError(err)
	assert.Len(s.T(), resp.CustomerLicenses, 1)

	cl := resp.CustomerLicenses[0]
	assert.Equal(s.T(), uint64(customerID), cl.GetCustomerId())
	assert.Equal(s.T(), uint64(msg.GetUser().GetId()), cl.GetLicensee().GetIdDeprecated())
	assert.Equal(s.T(), proto.Product_PRODUCT_SDLC, cl.GetProduct())
	assert.Len(s.T(), cl.Enablements, 1)
	assert.Equal(s.T(), proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP, cl.Enablements[0].Reason)
	assert.Equal(s.T(), proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_ORG, cl.Enablements[0].Type)
	assert.ElementsMatch(s.T(), []uint64{msg.GetGroupId()}, cl.Enablements[0].EnablementIds)
	assert.Equal(s.T(), proto.LicenseStatus_LICENSE_STATUS_ACTIVE, cl.LicenseStatus)
	assert.Equal(s.T(), models.MaxExpiresAt, cl.ExpiresAt.AsTime().Unix())
}

func (s *membershipUpdateIntegrationSuite) TestMembershipUpdateDoesNotAddRepositoryCollaborator() {
	customerLicenseProto := stubs.NewCustomerLicenseProto()
	customerID := customerLicenseProto.CustomerId
	licenseeID := customerLicenseProto.Licensee.IdDeprecated

	// Process the membership update hydro message
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_REPOSITORY.Enum(), *githubv1.MembershipUpdate_ADD.Enum())
	msg.CustomerId = int64(customerID)
	msg.User.Id = uint32(licenseeID)

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.client.Logger, msg)
	s.Require().NoError(herr.Err)

	// Get the customer license
	getReq := &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC}
	resp, err := s.customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	s.Require().NoError(err)
	assert.Len(s.T(), resp.CustomerLicenses, 0)
}

func (s *membershipUpdateIntegrationSuite) TestMembershipUpdateAddsOrgMembership() {
	// Upsert an existing customer license
	customerLicenseProto := s.upsertCustomerLicense([]*proto.CustomerLicenseEnablement{
		{
			Type:          proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_ORG,
			Reason:        proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP,
			EnablementIds: []uint64{100},
		},
	})
	customerID := customerLicenseProto.CustomerId
	licenseeID := customerLicenseProto.Licensee.IdDeprecated

	// Process the membership update hydro message
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_ADD.Enum())
	msg.CustomerId = int64(customerID)
	msg.User.Id = uint32(licenseeID)

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.client.Logger, msg)
	s.Require().NoError(herr.Err)

	// Get the customer license
	getReq := &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC}
	resp, err := s.customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	s.Require().NoError(err)
	assert.Len(s.T(), resp.CustomerLicenses, 1)

	cl := resp.CustomerLicenses[0]
	assert.Equal(s.T(), customerID, cl.GetCustomerId())
	assert.Equal(s.T(), uint64(msg.GetUser().GetId()), cl.GetLicensee().GetIdDeprecated())
	assert.Equal(s.T(), proto.Product_PRODUCT_SDLC, cl.GetProduct())
	assert.Len(s.T(), cl.Enablements, 1)
	assert.Equal(s.T(), proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP, cl.Enablements[0].Reason)
	assert.Equal(s.T(), proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_ORG, cl.Enablements[0].Type)
	assert.ElementsMatch(s.T(), []uint64{100, msg.GetGroupId()}, cl.Enablements[0].EnablementIds)
	assert.Equal(s.T(), proto.LicenseStatus_LICENSE_STATUS_ACTIVE, cl.LicenseStatus)
	assert.Equal(s.T(), models.MaxExpiresAt, cl.ExpiresAt.AsTime().Unix())
}

func (s *membershipUpdateIntegrationSuite) TestMembershipUpdateRemovesOrgMembership() {
	// Upsert an existing customer license
	customerLicenseProto := s.upsertCustomerLicense([]*proto.CustomerLicenseEnablement{
		{
			Type:          proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_ORG,
			Reason:        proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP,
			EnablementIds: []uint64{100, 200},
		},
	})
	customerID := customerLicenseProto.CustomerId
	licenseeID := customerLicenseProto.Licensee.IdDeprecated

	// Process the membership update hydro message
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.CustomerId = int64(customerID)
	msg.User.Id = uint32(licenseeID)
	msg.GroupId = 100

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.client.Logger, msg)
	s.Require().NoError(herr.Err)

	// Get the customer license
	getReq := &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC}
	resp, err := s.customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	s.Require().NoError(err)
	require.Len(s.T(), resp.CustomerLicenses, 1)

	cl := resp.CustomerLicenses[0]
	assert.Equal(s.T(), customerID, cl.GetCustomerId())
	assert.Equal(s.T(), licenseeID, cl.GetLicensee().GetIdDeprecated())
	assert.Equal(s.T(), proto.Product_PRODUCT_SDLC, cl.GetProduct())
	assert.Len(s.T(), cl.Enablements, 1)
	assert.Equal(s.T(), proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP, cl.Enablements[0].Reason)
	assert.Equal(s.T(), proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_ORG, cl.Enablements[0].Type)
	assert.Equal(s.T(), []uint64{200}, cl.Enablements[0].EnablementIds)
	assert.Equal(s.T(), proto.LicenseStatus_LICENSE_STATUS_ACTIVE, cl.LicenseStatus)
	assert.Equal(s.T(), models.MaxExpiresAt, cl.ExpiresAt.AsTime().Unix())
}

func (s *membershipUpdateIntegrationSuite) TestMembershipUpdateRemovesRepositoryCollaborator() {
	// Upsert an existing customer license
	customerLicenseProto := s.upsertCustomerLicense([]*proto.CustomerLicenseEnablement{
		{
			Type:          proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_REPO,
			Reason:        proto.EnablementReason_ENABLEMENT_REASON_REPOSITORY_COLLABORATOR,
			EnablementIds: []uint64{100, 200},
		},
	})
	customerID := customerLicenseProto.CustomerId
	licenseeID := customerLicenseProto.Licensee.IdDeprecated

	// Process the membership update hydro message
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_REPOSITORY.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.CustomerId = int64(customerID)
	msg.User.Id = uint32(licenseeID)
	msg.GroupId = 100

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.client.Logger, msg)
	s.Require().NoError(herr.Err)

	// Get the customer license
	getReq := &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC}
	resp, err := s.customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	s.Require().NoError(err)
	require.Len(s.T(), resp.CustomerLicenses, 1)

	cl := resp.CustomerLicenses[0]
	assert.Equal(s.T(), customerID, cl.GetCustomerId())
	assert.Equal(s.T(), licenseeID, cl.GetLicensee().GetIdDeprecated())
	assert.Equal(s.T(), proto.Product_PRODUCT_SDLC, cl.GetProduct())
	assert.Len(s.T(), cl.Enablements, 1)
	assert.Equal(s.T(), proto.EnablementReason_ENABLEMENT_REASON_REPOSITORY_COLLABORATOR, cl.Enablements[0].Reason)
	assert.Equal(s.T(), proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_REPO, cl.Enablements[0].Type)
	assert.Equal(s.T(), []uint64{200}, cl.Enablements[0].EnablementIds)
	assert.Equal(s.T(), proto.LicenseStatus_LICENSE_STATUS_ACTIVE, cl.LicenseStatus)
}

func (s *membershipUpdateIntegrationSuite) TestMembershipUpdateDeletesLicenseWhenEmptyForVolumeCustomer() {
	// Upsert an existing customer license
	customerLicenseProto := s.upsertCustomerLicense([]*proto.CustomerLicenseEnablement{
		{
			Type:          proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_ORG,
			Reason:        proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP,
			EnablementIds: []uint64{100},
		},
	})
	customerID := customerLicenseProto.CustomerId
	licenseeID := customerLicenseProto.Licensee.IdDeprecated

	getReq := &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC}
	resp, err := s.customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	s.Require().NoError(err)
	assert.Len(s.T(), resp.CustomerLicenses, 1)

	volumeCustomer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	_, err = s.customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: volumeCustomer.ToProto()})
	s.Require().NoError(err)

	// Process the membership update hydro message
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.CustomerId = int64(customerID)
	msg.User.Id = uint32(licenseeID)
	msg.GroupId = 100

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.client.Logger, msg)
	s.Require().NoError(herr.Err)

	resp, err = s.customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	s.Require().NoError(err)
	require.Len(s.T(), resp.CustomerLicenses, 0)
}

func (s *membershipUpdateIntegrationSuite) TestMembershipUpdateDeactivatesLicenseWhenEmptyForMeteredCustomer() {
	// Upsert an existing customer license
	customerLicenseProto := s.upsertCustomerLicense([]*proto.CustomerLicenseEnablement{
		{
			Type:          proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_ORG,
			Reason:        proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP,
			EnablementIds: []uint64{100},
		},
	})
	customerID := customerLicenseProto.CustomerId
	licenseeID := customerLicenseProto.Licensee.IdDeprecated

	getReq := &proto.GetCustomerLicensesRequest{CustomerId: customerID, Product: proto.Product_PRODUCT_SDLC}
	resp, err := s.customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	s.Require().NoError(err)
	assert.Len(s.T(), resp.CustomerLicenses, 1)

	meteredCustomer := models.NewCustomer(customerID, models.LicensingModelMetered, false)
	_, err = s.customerClient.UpsertCustomer(context.Background(), &proto.UpsertCustomerRequest{Customer: meteredCustomer.ToProto()})
	s.Require().NoError(err)

	// Process the membership update hydro message
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.CustomerId = int64(customerID)
	msg.User.Id = uint32(licenseeID)
	msg.GroupId = 100

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.client.Logger, msg)
	s.Require().NoError(herr.Err)

	resp, err = s.customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	s.Require().NoError(err)
	require.Len(s.T(), resp.CustomerLicenses, 1)

	cl := resp.CustomerLicenses[0]
	assert.Equal(s.T(), customerID, cl.GetCustomerId())
	assert.Equal(s.T(), licenseeID, cl.GetLicensee().GetIdDeprecated())
	assert.Equal(s.T(), proto.Product_PRODUCT_SDLC, cl.GetProduct())
	assert.Len(s.T(), cl.Enablements, 0)
	assert.Equal(s.T(), proto.LicenseStatus_LICENSE_STATUS_DEACTIVATED, cl.LicenseStatus)
}

func (s *membershipUpdateIntegrationSuite) TestMembershipUpdateDoesNotAllowConcurrentUpdates() {
	// Upsert an existing customer license
	customerLicenseProto := s.upsertCustomerLicense([]*proto.CustomerLicenseEnablement{
		{
			Type:          proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_ORG,
			Reason:        proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP,
			EnablementIds: []uint64{100},
		},
	})
	customerID := customerLicenseProto.CustomerId
	licenseeID := customerLicenseProto.Licensee.IdDeprecated

	// Process the membership update hydro message
	msg1 := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_ADD.Enum())
	msg1.CustomerId = int64(customerID)
	msg1.User.Id = uint32(licenseeID)

	msg2 := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_ADD.Enum())
	msg2.CustomerId = int64(customerID)
	msg2.User.Id = uint32(licenseeID)

	// Run the handler concurrently
	start := make(chan struct{})
	errs := make(chan error, 2)
	go func() {
		<-start
		_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.client.Logger, msg1)
		errs <- herr.Err
	}()
	go func() {
		<-start
		_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.client.Logger, msg2)
		errs <- herr.Err
	}()
	close(start)

	// Ensure one of the handlers fails
	var errCount int
	for range 2 {
		err := <-errs
		if err != nil {
			errCount++
			assert.True(s.T(), cosmos.IsPreconditionFailedError(err))
			assert.ErrorContains(s.T(), err, "failed to upsert customerLicense")
		}
	}
	assert.Equal(s.T(), 1, errCount)
}

func TestMembershipUpdateHandlerIntegrationSuite(t *testing.T) {
	suite.Run(t, new(membershipUpdateIntegrationSuite))
}
