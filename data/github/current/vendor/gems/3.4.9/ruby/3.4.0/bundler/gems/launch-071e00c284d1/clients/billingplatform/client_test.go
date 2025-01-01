package billingplatform

import (
	"context"
	"errors"
	"fmt"
	"testing"

	billingplatform "github.com/github/actions-proto/gen/go/billing-platform/api/v1"
	billingplatformbase "github.com/github/actions-proto/gen/go/billing-platform/base/v1"
	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	v1 "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/graphqlid"
	"github.com/github/launch/utils/testutils"

	_ "github.com/github/actions-proto/gen/go/billing-platform/api/v1" // Generate mocks
)

type canProceedWithUsageTestInput struct {
	sku                  string
	customerID           int64
	ownerID              types.GlobalID
	repoID               types.GlobalID
	actorID              types.GlobalID
	repositoryVisibility billingplatformbase.RepositoryVisibility
}

func generateReqFromInput(input canProceedWithUsageTestInput, sku string) *billingplatform.CanProceedWithUsageRequest {
	_, ownerID, _ := graphqlid.DecodeTypeIntID(input.ownerID.String())
	_, repoID, _ := graphqlid.DecodeTypeIntID(input.repoID.String())
	_, actorID, _ := graphqlid.DecodeTypeIntID(input.actorID.String())
	return &billingplatform.CanProceedWithUsageRequest{
		UsageKey: &billingplatform.UsageKey{
			Product: "actions",
			Sku:     fmt.Sprintf("actions_%s", sku),
			EntityDetail: &billingplatformbase.EntityDetail{
				CustomerId: fmt.Sprintf("%d", input.customerID),
				OwnerId:    ownerID,
				RepoId:     repoID,
				ActorId:    actorID,
			},
			RepositoryVisibility: input.repositoryVisibility,
		},
	}
}

func TestCanProceedWithUsage(t *testing.T) {
	tests := []struct {
		desc        string
		input       canProceedWithUsageTestInput
		output      *CanProceedWithUsageResp
		expectedErr bool
		setupMockFn func(*mockCustomerApi, *ghtwirp.MockClient, canProceedWithUsageTestInput, *CanProceedWithUsageResp)
	}{
		{
			desc: "can proceed with usage - org owner, user actor",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("Organization", 456)),
				repoID:               types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:              types.GlobalID(testutils.EncodeGlobalID("User", 101)),
				repositoryVisibility: billingplatformbase.RepositoryVisibility_PUBLIC,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: false,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsStorageAllowed}, nil)
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsUsageAllowed}, nil)
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC, nil)
			},
		},
		{
			desc: "can proceed with usage - user owner, bot actor",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("User", 456)),
				repoID:               types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:              types.GlobalID(testutils.EncodeGlobalID("Bot", 101)),
				repositoryVisibility: billingplatformbase.RepositoryVisibility_PUBLIC,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: false,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsStorageAllowed}, nil)
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsUsageAllowed}, nil)
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC, nil)
			},
		},
		{
			desc: "can proceed with usage - no repo details",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("Enterprise", 456)),
				repoID:               types.NilGlobalID,
				actorID:              types.NilGlobalID,
				repositoryVisibility: billingplatformbase.RepositoryVisibility_VISIBILITY_UNKNOWN,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: false,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsStorageAllowed}, nil)
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsUsageAllowed}, nil)
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_INVALID, nil)
			},
		},
		{
			desc: "cannot proceed with usage",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("Organization", 456)),
				repoID:               types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:              types.GlobalID(testutils.EncodeGlobalID("User", 101)),
				repositoryVisibility: billingplatformbase.RepositoryVisibility_PUBLIC,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: false,
				IsActionsUsageAllowed:   false,
				IsOwnerSpammy:           false,
			},
			expectedErr: false,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsStorageAllowed}, nil)
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsUsageAllowed}, nil)
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC, nil)
			},
		},
		{
			desc: "billing platform error for single call",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("Organization", 456)),
				repoID:               types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:              types.GlobalID(testutils.EncodeGlobalID("User", 101)),
				repositoryVisibility: billingplatformbase.RepositoryVisibility_PUBLIC,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: true,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(nil, errors.New("billing platform error"))
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsUsageAllowed}, nil)
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC, nil)
			},
		},
		{
			desc: "billing platform error for multiple calls",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("Organization", 456)),
				repoID:               types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:              types.GlobalID(testutils.EncodeGlobalID("User", 101)),
				repositoryVisibility: billingplatformbase.RepositoryVisibility_PUBLIC,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: true,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(nil, errors.New("billing platform error"))
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(nil, errors.New("billing platform error"))
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC, nil)
			},
		},
		{
			desc: "invalid id type",
			input: canProceedWithUsageTestInput{
				sku:        "ubuntu-18.04",
				customerID: 123,
				ownerID:    types.GlobalID(testutils.EncodeGlobalID("Bot", 456)),
				repoID:     types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:    types.GlobalID(testutils.EncodeGlobalID("User", 101)),
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: true,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
			},
		},
		{
			desc: "spammy user",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("Organization", 456)),
				repoID:               types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:              types.GlobalID(testutils.EncodeGlobalID("User", 101)),
				repositoryVisibility: billingplatformbase.RepositoryVisibility_PUBLIC,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           true,
			},
			expectedErr: false,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsStorageAllowed}, nil)
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsUsageAllowed}, nil)
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC, nil)
			},
		},
		{
			desc: "spammy user fails",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("Organization", 456)),
				repoID:               types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:              types.GlobalID(testutils.EncodeGlobalID("User", 101)),
				repositoryVisibility: billingplatformbase.RepositoryVisibility_PUBLIC,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: true,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsStorageAllowed}, nil)
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsUsageAllowed}, nil)
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(false, errors.New("spammy user error"))
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC, nil)
			},
		},
		{
			desc: "cannot proceed with usage - no customer id",
			input: canProceedWithUsageTestInput{
				sku:        "ubuntu-18.04",
				customerID: 0,
				ownerID:    types.GlobalID(testutils.EncodeGlobalID("User", 456)),
				repoID:     types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:    types.GlobalID(testutils.EncodeGlobalID("Bot", 101)),
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: false,
				IsActionsUsageAllowed:   false,
				IsOwnerSpammy:           false,
			},
			expectedErr: false,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
			},
		},
		{
			desc: "can proceed with usage - no customer id, self-hosted sku",
			input: canProceedWithUsageTestInput{
				sku:        "self_hosted_unknown",
				customerID: 0,
				ownerID:    types.GlobalID(testutils.EncodeGlobalID("User", 456)),
				repoID:     types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:    types.GlobalID(testutils.EncodeGlobalID("Bot", 101)),
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: false,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: false,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
			},
		},
		{
			desc: "can proceed with usage public repo visibility",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("Organization", 456)),
				repoID:               types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:              types.GlobalID(testutils.EncodeGlobalID("User", 101)),
				repositoryVisibility: billingplatformbase.RepositoryVisibility_PUBLIC,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: false,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsStorageAllowed}, nil)
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsUsageAllowed}, nil)
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC, nil)
			},
		},
		{
			desc: "can proceed with usage private repo visibility",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("Organization", 456)),
				repoID:               types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:              types.GlobalID(testutils.EncodeGlobalID("User", 101)),
				repositoryVisibility: billingplatformbase.RepositoryVisibility_PRIVATE,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: false,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsStorageAllowed}, nil)
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsUsageAllowed}, nil)
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE, nil)
			},
		},
		{
			desc: "can proceed with usage internal repo visibility",
			input: canProceedWithUsageTestInput{
				sku:                  "ubuntu-18.04",
				customerID:           123,
				ownerID:              types.GlobalID(testutils.EncodeGlobalID("Organization", 456)),
				repoID:               types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:              types.GlobalID(testutils.EncodeGlobalID("User", 101)),
				repositoryVisibility: billingplatformbase.RepositoryVisibility_INTERNAL,
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			expectedErr: false,
			setupMockFn: func(
				mockCustomerAPI *mockCustomerApi,
				mockTwirpClient *ghtwirp.MockClient,
				input canProceedWithUsageTestInput,
				output *CanProceedWithUsageResp,
			) {
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, "storage")).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsStorageAllowed}, nil)
				mockCustomerAPI.EXPECT().CanProceedWithUsage(mock.Anything, generateReqFromInput(input, input.sku)).Return(&billingplatform.CanProceedWithUsageResponse{CanProceed: output.IsActionsUsageAllowed}, nil)
				mockTwirpClient.EXPECT().IsUserSpammy(mock.Anything, input.ownerID).Return(output.IsOwnerSpammy, nil)
				mockTwirpClient.EXPECT().GetRepositoryVisibility(mock.Anything, mock.Anything).Return(v1.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL, nil)
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.desc, func(t *testing.T) {
			mockTwirpClient := ghtwirp.NewMockClient(t)
			mockCustomerAPI := newMockCustomerApi(t)

			tc.setupMockFn(mockCustomerAPI, mockTwirpClient, tc.input, tc.output)

			customerID := &tc.input.customerID
			if tc.input.customerID == 0 {
				customerID = nil
			}

			client := NewClient(mockCustomerAPI, mockTwirpClient, observability.NewNullObservability())
			resp, err := client.CanProceedWithUsage(context.Background(), tc.input.sku, customerID, tc.input.ownerID, tc.input.repoID, tc.input.actorID, statter.Tags{})

			if tc.expectedErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}

			require.Equal(t, tc.output.IsActionsStorageAllowed, resp.IsActionsStorageAllowed)
			require.Equal(t, tc.output.IsActionsUsageAllowed, resp.IsActionsUsageAllowed)
			require.Equal(t, tc.output.IsOwnerSpammy, resp.IsOwnerSpammy)
		})
	}
}

func TestNopClient(t *testing.T) {
	tests := []struct {
		desc   string
		input  canProceedWithUsageTestInput
		output *CanProceedWithUsageResp
	}{
		{
			desc: "customer ID provided, usage and storage allowed",
			input: canProceedWithUsageTestInput{
				sku:        "test_sku",
				customerID: 12,
				ownerID:    types.GlobalID(testutils.EncodeGlobalID("User", 456)),
				repoID:     types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID:    types.GlobalID(testutils.EncodeGlobalID("Bot", 101)),
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
		},
		{
			desc: "no customer ID provided - self-hosted sku, usage allowed",
			input: canProceedWithUsageTestInput{
				sku:     "self_hosted_unknown",
				ownerID: types.GlobalID(testutils.EncodeGlobalID("User", 456)),
				repoID:  types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID: types.GlobalID(testutils.EncodeGlobalID("Bot", 101)),
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: false,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
		},
		{
			desc: "no customer ID provided - not a self-hosted sku, no usage allowed",
			input: canProceedWithUsageTestInput{
				sku:     "test_sku",
				ownerID: types.GlobalID(testutils.EncodeGlobalID("User", 456)),
				repoID:  types.GlobalID(testutils.EncodeGlobalID("Repository", 789)),
				actorID: types.GlobalID(testutils.EncodeGlobalID("Bot", 101)),
			},
			output: &CanProceedWithUsageResp{
				IsActionsStorageAllowed: false,
				IsActionsUsageAllowed:   false,
				IsOwnerSpammy:           false,
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.desc, func(t *testing.T) {

			customerID := &tc.input.customerID
			if tc.input.customerID == 0 {
				customerID = nil
			}

			client := NewNopClient(observability.NewNullObservability())
			resp, err := client.CanProceedWithUsage(context.Background(), tc.input.sku, customerID, tc.input.ownerID, tc.input.repoID, tc.input.actorID, statter.Tags{})

			require.NoError(t, err)
			require.Equal(t, tc.output.IsActionsStorageAllowed, resp.IsActionsStorageAllowed)
			require.Equal(t, tc.output.IsActionsUsageAllowed, resp.IsActionsUsageAllowed)
			require.Equal(t, tc.output.IsOwnerSpammy, resp.IsOwnerSpammy)

		})
	}

}
