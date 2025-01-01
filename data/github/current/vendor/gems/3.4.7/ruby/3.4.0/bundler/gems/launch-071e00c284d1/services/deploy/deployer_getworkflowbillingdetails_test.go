package deploy

import (
	"context"
	"errors"
	"fmt"
	"testing"

	circuit "github.com/rubyist/circuitbreaker"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/clients/billingplatform"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"

	billingplatformProto "github.com/github/actions-proto/gen/go/billing-platform/api/v1"
)

func TestDeployer_GetWorkflowBillingDetails(t *testing.T) {
	suite.Run(t, new(GetWorkflowBillingDetailsSuite))
}

type GetWorkflowBillingDetailsSuite struct {
	suite.Suite

	mockClient                *github.MockClient
	mockWorkflowBuilds        *deployer.MockWorkflowBuildsRepository
	mockTwirpClient           *ghtwirp.MockClient
	mockBillingPlatformClient *billingplatform.MockClient
	jobRepo                   *deployer.MockJobsRepository

	svc *service
}

const (
	getWorkflowBillingDetailsSuiteRepositoryID = types.GlobalID("my-rad-repo")
)

func (s *GetWorkflowBillingDetailsSuite) SetupTest() {
	s.mockClient = &github.MockClient{}
	s.mockTwirpClient = &ghtwirp.MockClient{}
	s.mockWorkflowBuilds = &deployer.MockWorkflowBuildsRepository{}
	s.mockBillingPlatformClient = &billingplatform.MockClient{}
	s.jobRepo = &deployer.MockJobsRepository{}

	s.svc = newTestService()
	s.svc.cfg.WorkflowBuilds = s.mockWorkflowBuilds
	s.svc.cfg.GithubTwirpBillingClient = s.mockTwirpClient
	s.svc.cfg.GithubTwirpClient = s.mockTwirpClient
	s.svc.cfg.BillingPlatformTwirpClient = s.mockBillingPlatformClient
	s.svc.cfg.JobsRepo = s.jobRepo
}

func (s *GetWorkflowBillingDetailsSuite) assertTwirpError(err error, expectedCode twirp.ErrorCode) bool {
	if !s.Assert().Error(err) {
		return false
	}

	var twirpErr twirp.Error
	if errors.As(err, &twirpErr) {
		if twirpErr.Code() == expectedCode {
			return true
		}
	}

	return false
}

func (s *GetWorkflowBillingDetailsSuite) TestEmptyRequest() {
	ctx := context.Background()

	req := &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID: "",
		JobID:      "",
	}

	_, err := s.svc.GetWorkflowBillingDetails(ctx, req)
	s.assertTwirpError(err, twirp.InvalidArgument)
}

func (s *GetWorkflowBillingDetailsSuite) TestInternalServiceError() {
	ctx := context.Background()
	workflowID := "abc123"
	jobID := "1234abcde"

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, workflowID).Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().GetBillingDetails(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID).Return(nil, twirp.InternalError("Internal Service Error"))
	s.jobRepo.EXPECT().UpdateBillingChecked(mock.Anything, workflowID, jobID, false).Return(nil).Once()
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, mock.Anything, mock.Anything).Return(false)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID: workflowID,
		JobID:      jobID,
	})

	s.Require().Nil(err)
	s.Require().Equal(res.GetIsOwnerSpammy(), false)
	s.Require().Equal(res.GetIsUsageAllowed(), true)
	s.Require().Equal(res.GetIsStorageAllowed(), true)
	s.Require().Equal(res.GetIsBillingChecked(), false)
}

func (s *GetWorkflowBillingDetailsSuite) TestCircuitBreakError() {
	ctx := context.Background()
	workflowID := "abc123"
	jobID := "1234abcde"

	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)

	wrappedError := twirp.InternalError("test").WithMeta("cause", circuit.ErrBreakerOpen.Error())
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().GetBillingDetails(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID).Return(nil, wrappedError)

	s.jobRepo.EXPECT().UpdateBillingChecked(mock.Anything, workflowID, jobID, false).Return(nil).Once()

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID: workflowID,
		JobID:      jobID,
	})

	s.Require().Nil(err)
	s.Require().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
	s.Require().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
	s.Require().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
	s.Require().Equal(res.GetIsBillingChecked(), false)
}

func (s *GetWorkflowBillingDetailsSuite) TestNotFoundError() {
	ctx := context.Background()

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().GetBillingDetails(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID).Return(nil, twirp.NotFoundError("Repository not found"))

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID: "abc123",
	})

	s.Assert().Nil(res)
	s.assertTwirpError(err, twirp.NotFound)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetails() {
	ctx := context.Background()

	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().GetBillingDetails(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID).Return(billingResponse, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID: "abc123",
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatform() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformSelfHosted() {
	ctx := context.Background()
	workflowID := "abc123"
	jobID := "1234abcde"

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		"self_hosted_unknown",
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     "",
		IsHostedRunner: false,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformSelfHostedNoCustomerID() {
	ctx := context.Background()
	workflowID := "abc123"
	jobID := "1234abcde"

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		"self_hosted_unknown",
		dftr.WorkflowMetadata.CustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     "",
		IsHostedRunner: false,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformUsageNotAllowed() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   false,
		IsOwnerSpammy:           false,
	}

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformError() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}
	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, errors.New("some error"))
	s.jobRepo.EXPECT().UpdateBillingChecked(mock.Anything, workflowID, jobID, false).Return(nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)
	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
	s.Require().Equal(res.GetIsBillingChecked(), false)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformValidationError() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID:      nil,
			RepositoryOwner: nil,
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().Nil(res)
	s.Assert().Error(err)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformNilCustomerID() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   false,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		dftr.WorkflowMetadata.CustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsForEntity() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().GetBillingDetailsForEntity(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID, testProductSku).Return(billingResponse, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     "abc123",
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.AssertCalled(s.T(), "GetBillingDetailsForEntity", mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID, testProductSku)
	s.Assert().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsForEntitLargerRunners() {
	ctx := context.Background()
	testProductSku := "test_larger_product_sku"
	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().GetBillingDetailsForEntity(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID, testProductSku).Return(billingResponse, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)

	// Larger Hosted runners come across as none Hosted Runners today
	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     "abc123",
		ProductSku:     testProductSku,
		IsHostedRunner: false,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.AssertCalled(s.T(), "GetBillingDetailsForEntity", mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID, testProductSku)
	s.Assert().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsSelfHosted() {
	ctx := context.Background()
	// Self Hosted runners have no sku today and are blank strings
	testProductSku := ""
	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
	s.mockTwirpClient.EXPECT().GetBillingDetails(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID).Return(billingResponse, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     "abc123",
		ProductSku:     testProductSku,
		IsHostedRunner: false,
	})

	s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetailsForEntity", mock.Anything, mock.Anything)
	// self-hosted calls old endpoint
	s.mockTwirpClient.AssertCalled(s.T(), "GetBillingDetails", mock.Anything, mock.Anything)

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsMultitenant() {

	validGitHubTenantID := int64(4)
	invalidGitHubTenantID := int64(-1)

	cases := []struct {
		description   string
		isMultiTenant bool
		ghTenantID    *int64
		expectError   bool
	}{
		{
			description: "non-multi-tenant",
		},
		{
			description:   "multi-tenant/valid-id",
			isMultiTenant: true,
			ghTenantID:    &validGitHubTenantID,
		},
		{
			description:   "multi-tenant/invalid-id",
			isMultiTenant: true,
			ghTenantID:    &invalidGitHubTenantID,
			expectError:   true,
		},
		{
			description:   "multi-tenant/nil-id",
			isMultiTenant: true,
			ghTenantID:    nil,
			expectError:   true,
		},
	}

	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	for _, c := range cases {
		s.Run(c.description, func() {
			s.SetupTest()

			ctx := context.Background()
			s.svc.IsMultiTenant = c.isMultiTenant

			dftr := &deployer.DataForTokenRequest{
				RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
			}

			if c.isMultiTenant {
				dftr.GitHubTenantID = c.ghTenantID
			}

			s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
			s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
			s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
			s.mockTwirpClient.On("GetBillingDetails", mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID).Return(billingResponse, nil).Run(func(args mock.Arguments) {
				ctx, ok := args.Get(0).(context.Context)
				s.Require().True(ok)
				tenantID, err := ghtenant.TenantIDFromContext(ctx, c.isMultiTenant)
				s.Require().NoError(err)

				if c.isMultiTenant {
					s.Assert().Equal(*c.ghTenantID, tenantID)
				}
			})

			res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
				WorkflowID: "abc123",
			})

			if c.expectError {
				s.Assert().Error(err)
				s.Assert().Nil(res)
				return
			}

			s.Assert().NotNil(res)
			s.Assert().NoError(err)
			s.Assert().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
			s.Assert().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
			s.Assert().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
		})
	}
}

func (s *GetWorkflowBillingDetailsSuite) Test_DynamicWorkflow() {
	ctx := context.Background()
	workflowID := "abc123"
	jobID := "1234abcde"

	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			Repository: &metadata.WorkflowRepositoryMetadata{
				ID:            3,
				GlobalRelayID: "R_kgAD",
			},
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
		},
	}

	s.Run("dynamic workflow for pages", func() {
		dftr.WorkflowFilePath = "dynamic/pages/pages-build-deployment"

		s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)

		s.mockTwirpClient.EXPECT().IsUserFromDatabaseIDSpammy(mock.Anything, mock.Anything).Return(false, nil)

		res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
			WorkflowID: workflowID,
			JobID:      jobID,
		})

		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetailsForEntity", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetails", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "UpdateBillingChecked", mock.Anything, mock.Anything)

		s.Require().Nil(err)
		s.Require().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
		s.Require().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
		s.Require().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
		s.Require().Equal(res.GetIsBillingChecked(), true)
	})

	s.Run("dynamic workflow for dependabot", func() {
		dftr.WorkflowFilePath = "dynamic/dependabot/dependabot-updates"

		s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)

		s.mockTwirpClient.EXPECT().IsUserFromDatabaseIDSpammy(mock.Anything, mock.Anything).Return(false, nil)

		res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
			WorkflowID: workflowID,
			JobID:      jobID,
		})

		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetailsForEntity", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetails", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "UpdateBillingChecked", mock.Anything, mock.Anything)

		s.Require().Nil(err)
		s.Require().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
		s.Require().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
		s.Require().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
		s.Require().Equal(res.GetIsBillingChecked(), true)
	})

	s.Run("dynamic workflow with a path to app which should not be exempted", func() {
		dftr.WorkflowFilePath = "dynamic/codeql/queries"

		s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
		s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
		s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
		s.mockTwirpClient.EXPECT().GetBillingDetails(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID).Return(billingResponse, nil)

		res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
			WorkflowID: workflowID,
			JobID:      jobID,
		})

		s.Require().Nil(err)
		s.mockTwirpClient.AssertCalled(s.T(), "GetBillingDetails", mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID)
		s.Require().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
		s.Require().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
		s.Require().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
	})

	s.Run("non dynamic workflow", func() {
		dftr.WorkflowFilePath = ".github/workflows/tg-fmt.yaml"

		s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
		s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
		s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ActionsUseBillingPlatform, getWorkflowBillingDetailsSuiteRepositoryID).Return(false)
		s.mockTwirpClient.EXPECT().GetBillingDetails(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID).Return(billingResponse, nil)

		res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
			WorkflowID: workflowID,
			JobID:      jobID,
		})

		s.Require().Nil(err)
		s.mockTwirpClient.AssertCalled(s.T(), "GetBillingDetails", mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID)
		s.Require().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
		s.Require().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
		s.Require().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
	})

	s.mockTwirpClient.AssertNumberOfCalls(s.T(), "IsUserFromDatabaseIDSpammy", 2)
	_, _, stat := observability.NewMockedObservability()
	stat.EXPECT().Counter(mock.Anything, "github.billing-skip-dynamic-workflow", mock.Anything, int64(2)).Return()
}

func (s *GetWorkflowBillingDetailsSuite) Test_SpammyUser_DynamicWorkflow() {
	ctx := context.Background()
	workflowID := "test123"
	jobID := "1234Test"

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			Repository: &metadata.WorkflowRepositoryMetadata{
				ID:            3,
				GlobalRelayID: "R_kgAD",
			},
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
		},
	}

	spammyBillingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           true,
	}

	s.Run("pages dynamic workflow for a spammy user", func() {
		dftr.WorkflowFilePath = "dynamic/pages/pages-build-deployment"

		s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, workflowID).Return(dftr, true, nil)

		s.mockTwirpClient.EXPECT().IsUserFromDatabaseIDSpammy(mock.Anything, mock.Anything).Return(true, nil)

		res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
			WorkflowID: workflowID,
			JobID:      jobID,
		})

		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetailsForEntity", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetails", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "UpdateBillingChecked", mock.Anything, mock.Anything)

		s.Require().Nil(err)
		s.Require().Equal(res.GetIsOwnerSpammy(), spammyBillingResponse.IsOwnerSpammy)
		s.Require().Equal(res.GetIsUsageAllowed(), spammyBillingResponse.IsActionsUsageAllowed)
		s.Require().Equal(res.GetIsStorageAllowed(), spammyBillingResponse.IsActionsStorageAllowed)
		s.Require().Equal(res.GetIsBillingChecked(), true)
	})

	s.Run("dependabot dynamic workflow for a spammy user", func() {
		dftr.WorkflowFilePath = "dynamic/dependabot/dependabot-updates"

		s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, workflowID).Return(dftr, true, nil)

		s.mockTwirpClient.EXPECT().IsUserFromDatabaseIDSpammy(mock.Anything, mock.Anything).Return(true, nil)

		res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
			WorkflowID: workflowID,
			JobID:      jobID,
		})

		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetailsForEntity", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetails", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "UpdateBillingChecked", mock.Anything, mock.Anything)

		s.Require().Nil(err)
		s.Require().Equal(res.GetIsOwnerSpammy(), spammyBillingResponse.IsOwnerSpammy)
		s.Require().Equal(res.GetIsUsageAllowed(), spammyBillingResponse.IsActionsUsageAllowed)
		s.Require().Equal(res.GetIsStorageAllowed(), spammyBillingResponse.IsActionsStorageAllowed)
		s.Require().Equal(res.GetIsBillingChecked(), true)
	})

	s.mockTwirpClient.AssertNumberOfCalls(s.T(), "IsUserFromDatabaseIDSpammy", 2)
	_, _, stat := observability.NewMockedObservability()
	stat.EXPECT().Counter(mock.Anything, "github.billing-skip-dynamic-workflow", mock.Anything, int64(2)).Return()
}

func (s *GetWorkflowBillingDetailsSuite) Test_ExperimentalSKU() {
	ctx := context.Background()
	workflowID := "abc123"
	jobID := "1234abcde"
	sku := ExperimentalProductSKU

	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			Repository: &metadata.WorkflowRepositoryMetadata{
				ID:            3,
				GlobalRelayID: "R_kgAD",
			},
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
		},
	}

	s.Run("experimental workflow", func() {
		s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ExperimentalBillingFeatureFlag, mock.Anything).Return(true)
		s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)

		s.mockTwirpClient.EXPECT().IsUserFromDatabaseIDSpammy(mock.Anything, mock.Anything).Return(false, nil)

		res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
			WorkflowID: workflowID,
			JobID:      jobID,
			ProductSku: sku,
		})

		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetailsForEntity", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetails", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "UpdateBillingChecked", mock.Anything, mock.Anything)

		s.Require().Nil(err)
		s.Require().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
		s.Require().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
		s.Require().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
		s.Require().Equal(res.GetIsBillingChecked(), true)
	})

	s.mockTwirpClient.AssertNumberOfCalls(s.T(), "IsUserFromDatabaseIDSpammy", 1)
	_, _, stat := observability.NewMockedObservability()
	stat.EXPECT().Counter(mock.Anything, "github.billing-skip-experimental", mock.Anything, int64(1)).Return()
}

func (s *GetWorkflowBillingDetailsSuite) Test_SpammyUser_ExperimentalSKU() {
	ctx := context.Background()
	workflowID := "test123"
	jobID := "1234Test"
	sku := ExperimentalProductSKU

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			Repository: &metadata.WorkflowRepositoryMetadata{
				ID:            3,
				GlobalRelayID: "R_kgAD",
			},
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
		},
	}

	spammyBillingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           true,
	}

	s.Run("experimental sku spammy user", func() {
		s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.ExperimentalBillingFeatureFlag, mock.Anything).Return(true)
		s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, workflowID).Return(dftr, true, nil)

		s.mockTwirpClient.EXPECT().IsUserFromDatabaseIDSpammy(mock.Anything, mock.Anything).Return(true, nil)

		res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
			WorkflowID: workflowID,
			JobID:      jobID,
			ProductSku: sku,
		})

		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetailsForEntity", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "GetBillingDetails", mock.Anything, mock.Anything)
		s.mockTwirpClient.AssertNotCalled(s.T(), "UpdateBillingChecked", mock.Anything, mock.Anything)

		s.Require().Nil(err)
		s.Require().Equal(res.GetIsOwnerSpammy(), spammyBillingResponse.IsOwnerSpammy)
		s.Require().Equal(res.GetIsUsageAllowed(), spammyBillingResponse.IsActionsUsageAllowed)
		s.Require().Equal(res.GetIsStorageAllowed(), spammyBillingResponse.IsActionsStorageAllowed)
		s.Require().Equal(res.GetIsBillingChecked(), true)
	})

	s.mockTwirpClient.AssertNumberOfCalls(s.T(), "IsUserFromDatabaseIDSpammy", 1)
	_, _, stat := observability.NewMockedObservability()
	stat.EXPECT().Counter(mock.Anything, "github.billing-skip-experimental", mock.Anything, int64(1)).Return()
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatform_NewCheck() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformSelfHosted_NewCheck() {
	ctx := context.Background()
	workflowID := "abc123"
	jobID := "1234abcde"

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		"self_hosted_unknown",
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     "",
		IsHostedRunner: false,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformSelfHostedNoCustomerID_NewCheck() {
	ctx := context.Background()
	workflowID := "abc123"
	jobID := "1234abcde"

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		"self_hosted_unknown",
		dftr.WorkflowMetadata.CustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     "",
		IsHostedRunner: false,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformUsageNotAllowed_NewCheck() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   false,
		IsOwnerSpammy:           false,
	}

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformError_NewCheck() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}
	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, errors.New("some error"))
	s.jobRepo.EXPECT().UpdateBillingChecked(mock.Anything, workflowID, jobID, false).Return(nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)
	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
	s.Require().Equal(res.GetIsBillingChecked(), false)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatformNilCustomerID_NewCheck() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	canProceedWithUsage := &billingplatform.CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   false,
		IsOwnerSpammy:           false,
	}

	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		dftr.WorkflowMetadata.CustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(canProceedWithUsage, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), canProceedWithUsage.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), canProceedWithUsage.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), canProceedWithUsage.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatform_CustomerNotFound_NewCheck() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(
		nil,
		twirp.NotFoundError(fmt.Sprintf("Customer with id %d not found", testCustomerID)),
	)

	s.mockTwirpClient.EXPECT().GetBillingDetailsForEntity(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID, testProductSku).Return(billingResponse, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatform_CustomerNotFoundTwice_NewCheck() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	var errs error
	errs = errors.Join(errs, twirp.NotFoundError(fmt.Sprintf("Customer with id %d not found", testCustomerID)))
	errs = errors.Join(errs, twirp.NotFoundError(fmt.Sprintf("Customer with id %d not found", testCustomerID)))

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(
		nil,
		errs,
	)

	s.mockTwirpClient.EXPECT().GetBillingDetailsForEntity(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID, testProductSku).Return(billingResponse, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
}

func (s *GetWorkflowBillingDetailsSuite) TestWorkflowBillingDetailsWithBillingPlatform_ProductNotEnabled_NewCheck() {
	ctx := context.Background()
	testProductSku := "test_product_sku"
	workflowID := "abc123"
	jobID := "1234abcde"

	billingResponse := &ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}

	testCustomerID := int64(1234)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID: getWorkflowBillingDetailsSuiteRepositoryID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			CustomerID: &testCustomerID,
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            67336198,
				GlobalRelayID: "O_kgDOBAN4Bg",
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID:            16631042,
				GlobalRelayID: "U_kgDOAP3FAg",
			},
		},
	}

	s.mockWorkflowBuilds.EXPECT().GetDataForTokenRequest(mock.Anything, "abc123").Return(dftr, true, nil)
	s.mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.BillingCanProceedWithUsageProductEnabled, getWorkflowBillingDetailsSuiteRepositoryID).Return(true)
	s.mockBillingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		testProductSku,
		&testCustomerID,
		types.GlobalID(dftr.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
		dftr.RepositoryID,
		types.GlobalID(dftr.WorkflowMetadata.InvokingUser.GlobalRelayID),
		statter.Tags{"caller": "workflow_billing_details"},
	).Return(
		&billingplatform.CanProceedWithUsageResp{
			IsActionsStorageAllowed: true,
			IsActionsUsageAllowed:   true,
			IsOwnerSpammy:           true,
			Status:                  billingplatformProto.CanProceedWithUsageStatus_ProductNotEnabled,
		},
		nil,
	)
	s.mockTwirpClient.EXPECT().GetBillingDetailsForEntity(mock.Anything, getWorkflowBillingDetailsSuiteRepositoryID, testProductSku).Return(billingResponse, nil)

	res, err := s.svc.GetWorkflowBillingDetails(ctx, &pb.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		ProductSku:     testProductSku,
		IsHostedRunner: true,
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(res.GetIsOwnerSpammy(), billingResponse.IsOwnerSpammy)
	s.Assert().Equal(res.GetIsUsageAllowed(), billingResponse.IsActionsUsageAllowed)
	s.Assert().Equal(res.GetIsStorageAllowed(), billingResponse.IsActionsStorageAllowed)
}
