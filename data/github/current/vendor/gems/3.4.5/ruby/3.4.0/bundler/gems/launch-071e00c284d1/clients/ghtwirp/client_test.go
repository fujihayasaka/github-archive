package ghtwirp

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"reflect"
	"strings"
	"testing"

	"golang.org/x/text/cases"
	"golang.org/x/text/language"

	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	twirpTrustTiers "github.com/github/monolith-twirp-trusttiers/proto/trusttier/v1"
	"github.com/stretchr/testify/assert"
	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	ghactions "github.com/github/launch/proto/monolith/core/v1"

	types "github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/testutils"
)

const testFeatureFlag = "some_feature_flag"

var titleCaseFormatter = cases.Title(language.Und)

var fixedCreatedAtDate = timestamppb.Now()

func TestCreateRerunExecution(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	actorID := types.GlobalID(testutils.EncodeGlobalID("User", 7654321))
	workflowRunID := int64(123)
	planID := types.NewRandomWorkflowExecutionID()
	attempt := int64(2)
	executionGraph := "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"a\"}]}]}]}"
	referencedWorkflows := "[\n\t{\n\t\t\"path\": \"actions/canary/.github/workflows-lab/called-outputs.yml@main\",\n\t\t\"sha\": \"d4bdd217dae382a8ee919f3caf937ae7a3fb4e90\",\n\t\t\"ref\": \"refs/heads/main\"\n\t},\n\t{\n\t\t\"path\": \"another/repository/.github/workflows/callme.yml@d4bdd217dae382a8ee919f3caf937ae7a3fb4e90\",\n\t\t\"sha\": \"d4bdd217dae382a8ee919f3caf937ae7a3fb4e90\"\n\t}\n]"

	tests := []struct {
		desc        string
		returnedErr error
	}{
		{
			desc:        "returns an error if one is returned from the checks API",
			returnedErr: twirp.NewError(twirp.Internal, "test error"),
		},
		{
			desc: "returns nil on success",
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockChecksAPI := NewMockChecksService(t)
			mockChecksAPI.EXPECT().CreateExecution(mock.Anything, &ghactions.CreateExecutionRequest{
				RepositoryId: &ghactions.Identity{
					GlobalId: testRepoID.String(),
				},
				WorkflowRunId: workflowRunID,
				ActorId: &ghactions.Identity{
					GlobalId: actorID.String(),
				},
				PlanId:              planID.String(),
				Attempt:             attempt,
				ExecutionGraph:      executionGraph,
				ReferencedWorkflows: referencedWorkflows,
			}).Return(&ghactions.CreateExecutionResponse{}, tt.returnedErr)

			c := NewMockTestClient(nil, nil, nil, nil, nil, nil, nil, nil, mockChecksAPI, nil, nil, nil, nil, nil, false)

			err := c.CreateRerunExecution(context.TODO(), &RerunExecutionInput{
				RepositoryID:        testRepoID,
				WorkflowRunID:       workflowRunID,
				ActorID:             actorID,
				PlanID:              planID,
				Attempt:             attempt,
				ExecutionGraph:      executionGraph,
				ReferencedWorkflows: referencedWorkflows,
			})
			if tt.returnedErr != nil {
				assert.EqualError(t, err, tt.returnedErr.Error())
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestIsFeatureEnabledForActors(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	testOwnerID := types.GlobalID(testutils.EncodeGlobalID("Owner", 1234567))

	tests := []struct {
		desc         string
		globalIDs    []types.GlobalID
		featureFlag  string
		featuresRes  *twirpFeatures.CheckActorsFeatureResponse
		returnedErr  error
		want         bool
		wantNumCalls int
	}{
		{
			desc:        "returns true when API returns true for one actor",
			globalIDs:   []types.GlobalID{testRepoID, testOwnerID},
			featureFlag: testFeatureFlag,
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: false,
					},
					{
						ActorId:   "Organization:1234567",
						IsEnabled: true,
					},
				},
			},
			wantNumCalls: 1,
			want:         true,
		},
		{
			desc:        "returns true when API returns true for both actors",
			globalIDs:   []types.GlobalID{testRepoID, testOwnerID},
			featureFlag: testFeatureFlag,
			want:        true,
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
					{
						ActorId:   "Organization:1234567",
						IsEnabled: true,
					},
				},
			},
			wantNumCalls: 1,
		},
		{
			desc:        "returns false when API returns false for both actors",
			globalIDs:   []types.GlobalID{testRepoID, testOwnerID},
			featureFlag: testFeatureFlag,
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: false,
					},
					{
						ActorId:   "Organization:1234567",
						IsEnabled: false,
					},
				},
			},
			wantNumCalls: 1,
			want:         false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockFeaturesService := NewMockMonolithFeaturesService(t)
			mockFeaturesService.EXPECT().CheckActorsFeature(mock.Anything, mock.Anything).Return(tt.featuresRes, tt.returnedErr)
			c := NewMockTestClient(nil, nil, nil, mockFeaturesService, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)

			got := c.IsFeatureEnabledForActors(context.TODO(), tt.featureFlag, tt.globalIDs)
			assert.Equal(t, tt.want, got)

			mockFeaturesService.AssertNumberOfCalls(t, "CheckActorsFeature", tt.wantNumCalls)
		})
	}
}

func TestIsFeatureEnabledForActor(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))

	tests := []struct {
		desc               string
		globalID           types.GlobalID
		featureFlag        string
		globalRes          *twirpFeatures.CheckGlobalFeatureResponse
		globalReturnedErr  error
		featuresRes        *twirpFeatures.CheckActorsFeatureResponse
		returnedErr        error
		want               bool
		wantNumGlobalCalls int
		wantNumCalls       int
		doExtraRequest     bool
	}{
		{
			desc:        "returns true when Actors api returns true",
			globalID:    testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			want:               true,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
		},
		{
			desc:        "returns the cached response",
			globalID:    testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			want:               true,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
			doExtraRequest:     true,
		},
		{
			desc:        "returns false when both apis return false",
			globalID:    testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: false,
					},
				},
			},
			want:               false,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
		},
		{
			desc:        "defaults to false when Actors api fails",
			globalID:    testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			returnedErr:        errors.New(":ohno:"),
			want:               false,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
		},
		{
			desc:        "returns true when global api returns true",
			globalID:    testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: true,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			want:               true,
			wantNumGlobalCalls: 1,
			wantNumCalls:       0,
		},
		{
			desc:        "returns the cached global result",
			globalID:    testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: true,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			want:               true,
			wantNumGlobalCalls: 1,
			wantNumCalls:       0,
			doExtraRequest:     true,
		},
		{
			desc:              "calls Actors API when the global API fails",
			globalID:          testRepoID,
			featureFlag:       testFeatureFlag,
			globalReturnedErr: errors.New(":ohno:"),
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			want:               true,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
		},
		{
			desc:               "defaults to false when both apis fail",
			globalID:           testRepoID,
			featureFlag:        testFeatureFlag,
			globalReturnedErr:  errors.New(":ohno:"),
			returnedErr:        errors.New(":ohno-again:"),
			want:               false,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockFeaturesService := NewMockMonolithFeaturesService(t)
			mockFeaturesService.EXPECT().CheckGlobalFeature(mock.Anything, mock.Anything).Return(tt.globalRes, tt.globalReturnedErr)
			if tt.globalRes == nil || !tt.globalRes.IsEnabled {
				mockFeaturesService.EXPECT().CheckActorsFeature(mock.Anything, mock.Anything).Return(tt.featuresRes, tt.returnedErr)
			}
			c := NewMockTestClient(nil, nil, nil, mockFeaturesService, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got := c.IsFeatureEnabledForActor(context.TODO(), tt.featureFlag, tt.globalID)
			assert.Equal(t, tt.want, got)

			if tt.doExtraRequest {
				got := c.IsFeatureEnabledForActor(context.TODO(), tt.featureFlag, tt.globalID)
				assert.Equal(t, tt.want, got)
			}

			mockFeaturesService.AssertNumberOfCalls(t, "CheckGlobalFeature", tt.wantNumGlobalCalls)
			mockFeaturesService.AssertNumberOfCalls(t, "CheckActorsFeature", tt.wantNumCalls)
		})
	}
}

func TestIsFeatureEnabledGlobally(t *testing.T) {
	tests := []struct {
		desc           string
		featureFlag    string
		featuresRes    *twirpFeatures.CheckGlobalFeatureResponse
		returnedErr    error
		want           bool
		wantNumCalls   int
		doExtraRequest bool
	}{
		{
			desc:        "returns true when api returns true",
			featureFlag: testFeatureFlag,
			featuresRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: true,
			},
			want:         true,
			wantNumCalls: 1,
		},
		{
			desc:        "returns the cached response",
			featureFlag: testFeatureFlag,
			featuresRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: true,
			},
			want:           true,
			wantNumCalls:   1,
			doExtraRequest: true,
		},
		{
			desc:        "returns false when api returns false",
			featureFlag: testFeatureFlag,
			featuresRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			want:         false,
			wantNumCalls: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockActionsFeaturesService := NewMockMonolithFeaturesService(t)
			mockActionsFeaturesService.EXPECT().CheckGlobalFeature(mock.Anything, mock.Anything).Return(tt.featuresRes, tt.returnedErr)
			c := NewMockTestClient(nil, nil, nil, mockActionsFeaturesService, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got := c.IsFeatureEnabledGlobally(context.TODO(), tt.featureFlag)
			assert.Equal(t, tt.want, got)

			if tt.doExtraRequest {
				got := c.IsFeatureEnabledGlobally(context.TODO(), tt.featureFlag)
				assert.Equal(t, tt.want, got)
			}

			mockActionsFeaturesService.AssertNumberOfCalls(t, "CheckGlobalFeature", tt.wantNumCalls)
		})
	}
}

func TestIsFeatureEnabledForRepository(t *testing.T) {
	testRepoID := int64(1234567)

	tests := []struct {
		desc               string
		id                 int64
		featureFlag        string
		globalRes          *twirpFeatures.CheckGlobalFeatureResponse
		globalReturnedErr  error
		featuresRes        *twirpFeatures.CheckActorsFeatureResponse
		returnedErr        error
		want               bool
		wantNumGlobalCalls int
		wantNumCalls       int
		doExtraRequest     bool
	}{
		{
			desc:        "returns true when Actors api returns true",
			id:          1234567,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			want:               true,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
		},
		{
			desc:        "returns the cached response",
			id:          testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			want:               true,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
			doExtraRequest:     true,
		},
		{
			desc:        "returns false when both apis return false",
			id:          testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: false,
					},
				},
			},
			want:               false,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
		},
		{
			desc:        "defaults to false when Actors api fails",
			id:          testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			returnedErr:        errors.New(":ohno:"),
			want:               false,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
		},
		{
			desc:        "returns true when global api returns true",
			id:          testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: true,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			want:               true,
			wantNumGlobalCalls: 1,
			wantNumCalls:       0,
		},
		{
			desc:        "returns the cached global result",
			id:          testRepoID,
			featureFlag: testFeatureFlag,
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: true,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			want:               true,
			wantNumGlobalCalls: 1,
			wantNumCalls:       0,
			doExtraRequest:     true,
		},
		{
			desc:              "calls Actors API when the global API fails",
			id:                testRepoID,
			featureFlag:       testFeatureFlag,
			globalReturnedErr: errors.New(":ohno:"),
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			want:               true,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
		},
		{
			desc:               "defaults to false when both apis fail",
			id:                 testRepoID,
			featureFlag:        testFeatureFlag,
			globalReturnedErr:  errors.New(":ohno:"),
			returnedErr:        errors.New(":ohno-again:"),
			want:               false,
			wantNumGlobalCalls: 1,
			wantNumCalls:       1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {

			ctx := context.Background()
			mockFeaturesService := NewMockMonolithFeaturesService(t)
			mockFeaturesService.EXPECT().CheckGlobalFeature(mock.Anything, mock.Anything).Return(tt.globalRes, tt.globalReturnedErr)
			if tt.globalRes == nil || !tt.globalRes.IsEnabled {
				mockFeaturesService.EXPECT().CheckActorsFeature(mock.Anything, mock.Anything).Return(tt.featuresRes, tt.returnedErr)
			}
			c := NewMockTestClient(nil, nil, nil, mockFeaturesService, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)

			got := c.IsFeatureEnabledForRepository(ctx, tt.featureFlag, tt.id)
			assert.Equal(t, tt.want, got)

			if tt.doExtraRequest {
				got := c.IsFeatureEnabledForRepository(ctx, tt.featureFlag, tt.id)
				assert.Equal(t, tt.want, got)
			}

			mockFeaturesService.AssertNumberOfCalls(t, "CheckGlobalFeature", tt.wantNumGlobalCalls)
			mockFeaturesService.AssertNumberOfCalls(t, "CheckActorsFeature", tt.wantNumCalls)
		})
	}
}

func TestActionsAllowedByPolicy(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))

	tests := []struct {
		desc                     string
		repoID                   types.GlobalID
		actions                  []string
		policyResponse           *ghactions.CheckActionsPolicyResponse
		includeLocalOnlyActions  bool
		shouldIgnoreRepoPolicies bool
		returnedErr              error
		want                     bool
		wantNumCalls             int
	}{
		{
			desc:   "returns true when api returns true",
			repoID: testRepoID,
			policyResponse: &ghactions.CheckActionsPolicyResponse{
				IsExecutionAllowed: true,
				ErrorMessage:       "",
			},
			actions:      []string{"mikescoolorg/test"},
			want:         true,
			wantNumCalls: 1,
		},
		{
			desc:   "returns false when api returns false",
			repoID: testRepoID,
			policyResponse: &ghactions.CheckActionsPolicyResponse{
				IsExecutionAllowed: false,
				ErrorMessage:       "A nice error message",
			},
			actions:      []string{"mikescoolorg/test"},
			want:         false,
			wantNumCalls: 1,
		},
		{
			desc:                    "returns local only actions",
			repoID:                  testRepoID,
			includeLocalOnlyActions: true,
			policyResponse: &ghactions.CheckActionsPolicyResponse{
				IsExecutionAllowed: true,
				ErrorMessage:       "",
				LocalOnlyActions:   []string{"mikescoolorg/test"},
			},
			actions:      []string{"mikescoolorg/test"},
			want:         true,
			wantNumCalls: 1,
		},
		{
			desc:   "returns true when interal actions are allowed",
			repoID: testRepoID,
			policyResponse: &ghactions.CheckActionsPolicyResponse{
				IsExecutionAllowed:        true,
				ErrorMessage:              "",
				AreInternalActionsAllowed: true,
			},
			actions:      []string{"mikescoolorg/test"},
			want:         true,
			wantNumCalls: 1,
		},
		{
			desc:   "returns false when interal actions are not allowed",
			repoID: testRepoID,
			policyResponse: &ghactions.CheckActionsPolicyResponse{
				IsExecutionAllowed:        true,
				ErrorMessage:              "",
				AreInternalActionsAllowed: false,
			},
			actions:      []string{"mikescoolorg/test"},
			want:         true,
			wantNumCalls: 1,
		},
		{
			desc:   "returns true when private actions are allowed",
			repoID: testRepoID,
			policyResponse: &ghactions.CheckActionsPolicyResponse{
				IsExecutionAllowed:       true,
				ErrorMessage:             "",
				ArePrivateActionsAllowed: true,
			},
			actions:      []string{"mikescoolorg/test"},
			want:         true,
			wantNumCalls: 1,
		},
		{
			desc:   "returns false when private actions are not allowed",
			repoID: testRepoID,
			policyResponse: &ghactions.CheckActionsPolicyResponse{
				IsExecutionAllowed:       true,
				ErrorMessage:             "",
				ArePrivateActionsAllowed: false,
			},
			actions:      []string{"mikescoolorg/test"},
			want:         true,
			wantNumCalls: 1,
		},
		{
			desc:   "returns true when api returns true and repo policies are ignored",
			repoID: testRepoID,
			policyResponse: &ghactions.CheckActionsPolicyResponse{
				IsExecutionAllowed:       true,
				ErrorMessage:             "",
				ArePrivateActionsAllowed: false,
			},
			actions:                  []string{"mikescoolorg/test"},
			want:                     true,
			wantNumCalls:             1,
			shouldIgnoreRepoPolicies: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockPoliciesService := NewMockActionsPoliciesService(t)
			mockPoliciesService.EXPECT().CheckActionsPolicy(mock.Anything, mock.Anything).Return(tt.policyResponse, tt.returnedErr)
			c := NewMockTestClient(nil, nil, nil, nil, mockPoliciesService, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			actionsPolicyInfo, _ := c.CheckActionsAllowedByPolicy(context.TODO(), tt.repoID, tt.actions, tt.includeLocalOnlyActions, tt.shouldIgnoreRepoPolicies)
			assert.Equal(t, tt.want, actionsPolicyInfo.IsExecutionAllowed)
			assert.Equal(t, tt.policyResponse.GetLocalOnlyActions(), actionsPolicyInfo.LocalOnlyActions)
			assert.Equal(t, tt.policyResponse.GetAreInternalActionsAllowed(), actionsPolicyInfo.AreInternalActionsAllowed)
			assert.Equal(t, tt.policyResponse.GetArePrivateActionsAllowed(), actionsPolicyInfo.ArePrivateActionsAllowed)

			mockPoliciesService.AssertNumberOfCalls(t, "CheckActionsPolicy", tt.wantNumCalls)
		})
	}
}

func TestWorkflowsAllowedByPolicy(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))

	tests := []struct {
		desc                     string
		repoID                   types.GlobalID
		workflows                []string
		shouldIgnoreRepoPolicies bool
		policyResponse           *ghactions.CheckWorkflowsPolicyResponse
		returnedErr              error
		want                     bool
		wantNumCalls             int
	}{
		{
			desc:   "returns true when api returns true",
			repoID: testRepoID,
			policyResponse: &ghactions.CheckWorkflowsPolicyResponse{
				IsExecutionAllowed: true,
				ErrorMessage:       "",
			},
			workflows:    []string{"owner/repo/.github/workflows/ci.yml@test"},
			want:         true,
			wantNumCalls: 1,
		},
		{
			desc:   "returns false when api returns false",
			repoID: testRepoID,
			policyResponse: &ghactions.CheckWorkflowsPolicyResponse{
				IsExecutionAllowed: false,
				ErrorMessage:       "A nice error message",
			},
			workflows:    []string{"owner/repo/.github/workflows/ci.yml@test"},
			want:         false,
			wantNumCalls: 1,
		},
		{
			desc:   "returns true when api returns true after ignoring repo policies",
			repoID: testRepoID,
			policyResponse: &ghactions.CheckWorkflowsPolicyResponse{
				IsExecutionAllowed: true,
				ErrorMessage:       "",
			},
			workflows:                []string{"owner/repo/.github/workflows/ci.yml@test"},
			want:                     true,
			wantNumCalls:             1,
			shouldIgnoreRepoPolicies: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockPoliciesService := NewMockActionsPoliciesService(t)
			mockPoliciesService.EXPECT().CheckWorkflowsPolicy(mock.Anything, mock.Anything).Return(tt.policyResponse, tt.returnedErr)
			c := NewMockTestClient(nil, nil, nil, nil, mockPoliciesService, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)

			workflowsPolicyInfo, _ := c.CheckWorkflowsAllowedByPolicy(context.TODO(), tt.repoID, tt.workflows, tt.shouldIgnoreRepoPolicies)

			assert.Equal(t, tt.want, workflowsPolicyInfo.IsExecutionAllowed)
			mockPoliciesService.AssertNumberOfCalls(t, "CheckWorkflowsPolicy", tt.wantNumCalls)
		})
	}
}

func TestIsRepositoryActionsDisabled(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))

	tests := []struct {
		desc             string
		id               types.GlobalID
		resCanUseActions bool
		usersErr         error
		returnedErr      error
		want             bool
	}{
		{
			desc:             "returns false when error is returned from repositories API",
			id:               testRepoID,
			resCanUseActions: false,
			returnedErr:      twirp.NewError(twirp.Internal, "test error"),
			want:             false,
		},
		{
			desc:             "returns true when CanUseActions returns false",
			id:               testRepoID,
			resCanUseActions: false,
			want:             true,
		},
		{
			desc:             "returns false when CanUseActions returns true",
			id:               testRepoID,
			resCanUseActions: true,
			want:             false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockReposAPI := NewMockReposService(t)
			mockReposAPI.EXPECT().CheckRepositoryActionsStatus(mock.Anything, mock.Anything).Return(&ghactions.CheckRepositoryActionsStatusResponse{
				CanUseActions: tt.resCanUseActions,
			}, tt.returnedErr)

			c := NewMockTestClient(nil, mockReposAPI, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got, err := c.IsRepositoryActionsDisabled(context.TODO(), tt.id)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestIsRepositoryActionsDisabledCachedResponses(t *testing.T) {
	t.Log("ensures cached responses are equivalent to the actual prior response (regression from commit b8407b053c11a824b9f0ee3f04642be3141840f8)")
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))

	wantIsDisabled := true
	wantCanUse := !wantIsDisabled
	mockReposAPI := NewMockReposService(t)
	mockReposAPI.EXPECT().CheckRepositoryActionsStatus(mock.Anything, mock.Anything).Return(&ghactions.CheckRepositoryActionsStatusResponse{
		CanUseActions: wantCanUse,
	}, nil)

	c := NewMockTestClient(nil, mockReposAPI, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
	gotIsDisabled, err := c.IsRepositoryActionsDisabled(context.TODO(), testRepoID)
	require.NoError(t, err)
	assert.Equal(t, wantIsDisabled, gotIsDisabled)

	gotIsDisabled, err = c.IsRepositoryActionsDisabled(context.TODO(), testRepoID)
	require.NoError(t, err)
	assert.Equal(t, wantIsDisabled, gotIsDisabled)
}

func TestTrustTier(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))

	expectedTier := int64(2)
	mockTrustTiersAPI := NewMockTrustTiersService(t)
	mockTrustTiersAPI.EXPECT().GetTrustTier(mock.Anything, mock.Anything).Return(&twirpTrustTiers.GetTrustTierResponse{
		TrustTier: expectedTier,
	}, nil)

	c := NewMockTestClient(nil, nil, nil, nil, nil, mockTrustTiersAPI, nil, nil, nil, nil, nil, nil, nil, nil, false)
	actualTier, err := c.GetTrustTier(context.TODO(), testRepoID)
	require.NoError(t, err)
	assert.Equal(t, types.RepositoryTier(expectedTier), actualTier)
}

func TestShouldPullRequestWorkflowsRunForUser(t *testing.T) {
	tests := []struct {
		desc   string
		actor  types.GlobalID
		author types.GlobalID
		repoID types.GlobalID

		apiErr  error
		apiResp *ghactions.ShouldPullRequestWorkflowsRunForUserResponse

		expectedReq  *ghactions.ShouldPullRequestWorkflowsRunForUserRequest
		expectedErr  error
		expectedResp bool
	}{
		{
			desc:   "returns API response when there is no error",
			actor:  types.GlobalID("U_kgDOAP3FAg"),
			repoID: types.GlobalID("R_kgDNA3g"),

			apiErr: nil,
			apiResp: &ghactions.ShouldPullRequestWorkflowsRunForUserResponse{
				RunWorkflows: true,
			},

			expectedReq: &ghactions.ShouldPullRequestWorkflowsRunForUserRequest{
				User: &ghactions.Identity{
					GlobalId: "U_kgDOAP3FAg",
				},
				Repository: &ghactions.Identity{
					GlobalId: "R_kgDNA3g",
				},
			},
			expectedErr:  nil,
			expectedResp: true,
		},
		{
			desc:   "returns error when the API returns an error",
			actor:  types.GlobalID("U_kgDOAP3FAg"),
			repoID: types.GlobalID("R_kgDNA3g"),

			apiErr: twirp.NewError(twirp.NotFound, "user not found"),
			apiResp: &ghactions.ShouldPullRequestWorkflowsRunForUserResponse{
				RunWorkflows: true,
			},

			expectedReq: &ghactions.ShouldPullRequestWorkflowsRunForUserRequest{
				User: &ghactions.Identity{
					GlobalId: "U_kgDOAP3FAg",
				},
				Repository: &ghactions.Identity{
					GlobalId: "R_kgDNA3g",
				},
			},
			expectedErr:  twirp.NewError(twirp.NotFound, "user not found"),
			expectedResp: false, // Response should be ignored when there is an error
		},
		{
			desc:   "sets the author when it is provided",
			actor:  types.GlobalID("U_kgDOAP3FAg"),
			repoID: types.GlobalID("R_kgDNA3g"),
			author: types.GlobalID("U_kgAC"),

			apiErr: nil,
			apiResp: &ghactions.ShouldPullRequestWorkflowsRunForUserResponse{
				RunWorkflows: true,
			},

			expectedReq: &ghactions.ShouldPullRequestWorkflowsRunForUserRequest{
				User: &ghactions.Identity{
					GlobalId: "U_kgDOAP3FAg",
				},
				Repository: &ghactions.Identity{
					GlobalId: "R_kgDNA3g",
				},
				Author: &ghactions.Identity{
					GlobalId: "U_kgAC",
				},
			},
			expectedErr:  nil,
			expectedResp: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			usersService := NewMockUsersService(t)

			usersService.EXPECT().
				ShouldPullRequestWorkflowsRunForUser(mock.Anything, tt.expectedReq).
				Return(tt.apiResp, tt.apiErr).
				Once()

			c := NewMockTestClient(usersService, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)

			ctx := context.Background()

			resp, err := c.ShouldPullRequestWorkflowsRunForUser(ctx, tt.repoID, PullRequestEventUsers{
				Actor:  tt.actor,
				Author: tt.author,
			})

			assert.Equal(t, tt.expectedResp, resp)
			assert.Equal(t, tt.expectedErr, err)
		})
	}
}

func TestGetUserByLogin(t *testing.T) {
	tests := []struct {
		desc             string
		isMultitenant    bool
		setTenantID      bool
		wantErrMessage   string
		resErr           error
		expectedAPICalls int
		doExtraRequest   bool
	}{
		{
			desc:             "returns user when login is found",
			isMultitenant:    false,
			expectedAPICalls: 1,
		},
		{
			desc:             "returns user when login is found in Proxima",
			isMultitenant:    true,
			setTenantID:      true,
			expectedAPICalls: 1,
		},
		{
			desc:             "errors when tenant ID is not set in Proxima",
			isMultitenant:    true,
			setTenantID:      false,
			wantErrMessage:   "github tenant id not found in context",
			expectedAPICalls: 0,
		},
		{
			desc:             "errors when user is not found",
			isMultitenant:    false,
			resErr:           twirp.NewError(twirp.NotFound, "user not found"),
			wantErrMessage:   "user not found",
			expectedAPICalls: 1,
		},
		{
			desc:             "returned cached response when user is found",
			isMultitenant:    false,
			expectedAPICalls: 1,
			doExtraRequest:   true,
		},
		{
			desc:             "returned cached response when user is found in Proxima",
			isMultitenant:    true,
			setTenantID:      true,
			expectedAPICalls: 1,
			doExtraRequest:   true,
		},
		{
			desc:             "does not cache error responses",
			isMultitenant:    false,
			resErr:           twirp.NewError(twirp.NotFound, "user not found"),
			wantErrMessage:   "user not found",
			expectedAPICalls: 2,
			doExtraRequest:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockUsersAPI := NewMockUsersService(t)

			req := &ghactions.GetUserByLoginRequest{
				Login: "monalisa",
			}
			res := &ghactions.GetUserByLoginResponse{
				Id: int64(16631042),
				GlobalId: &ghactions.Identity{
					GlobalId: "U_kgDOAP3FAg",
				},
			}

			if tt.expectedAPICalls > 0 {
				if tt.resErr != nil {
					mockUsersAPI.EXPECT().GetUserByLogin(mock.Anything, req).Return(nil, tt.resErr).Times(tt.expectedAPICalls)
				} else {
					mockUsersAPI.EXPECT().GetUserByLogin(mock.Anything, req).Return(res, nil).Times(tt.expectedAPICalls)
				}
			}
			c := NewMockTestClient(mockUsersAPI, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, tt.isMultitenant)

			ctx := context.Background()
			if tt.setTenantID {
				var err error
				ctx, err = ghtenant.ContextWithTenantID(ctx, 27, true)
				require.NoError(t, err)
			}

			calls := 1
			if tt.doExtraRequest {
				calls = 2
			}

			for i := 0; i < calls; i++ {
				id, globalID, err := c.GetUserByLogin(ctx, "monalisa")

				if tt.wantErrMessage == "" {
					require.NoError(t, err)
					require.Equal(t, int64(16631042), id)
					require.Equal(t, types.GlobalID("U_kgDOAP3FAg"), globalID)
				} else {
					require.Error(t, err)
					require.Contains(t, err.Error(), tt.wantErrMessage)
				}
			}
		})
	}
}

func TestGetUserByLogin_ResponsesCachedWithTenant(t *testing.T) {
	login := "monalisa"
	mockUsersAPI := NewMockUsersService(t)

	req := &ghactions.GetUserByLoginRequest{
		Login: login,
	}
	res := &ghactions.GetUserByLoginResponse{
		Id: int64(16631042),
		GlobalId: &ghactions.Identity{
			GlobalId: "U_kgDOAP3FAg",
		},
	}

	// We expect the request to be made twice, once for each tenant.
	mockUsersAPI.EXPECT().GetUserByLogin(mock.Anything, req).Return(res, nil).Times(2)
	c := NewMockTestClient(mockUsersAPI, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, true)

	ctx, err := ghtenant.ContextWithTenantID(context.Background(), 27, true)
	require.NoError(t, err)

	_, _, err = c.GetUserByLogin(ctx, login)
	require.NoError(t, err)

	ctx, err = ghtenant.ContextWithTenantID(context.Background(), 72, true)
	require.NoError(t, err)

	_, _, err = c.GetUserByLogin(ctx, login)
	require.NoError(t, err)
}

func TestIsUserSpammy(t *testing.T) {
	testUserID := types.GlobalID(testutils.EncodeGlobalID("User", 1234567))
	testBotID := types.GlobalID(testutils.EncodeGlobalID("Bot", 41898282))
	testOrgID := types.GlobalID(testutils.EncodeGlobalID("Organization", 3))

	tests := []struct {
		desc             string
		id               types.GlobalID
		returnedErr      error
		numExpectedCalls int
		res              *ghactions.IsVisibleUserResponse
		want             bool
	}{
		{
			desc:             "returns true when user is not visible",
			id:               testUserID,
			numExpectedCalls: 1,
			res: &ghactions.IsVisibleUserResponse{
				IsVisible: false,
			},
			want: true,
		},
		{
			desc:             "returns false when user is visible",
			id:               testUserID,
			numExpectedCalls: 1,
			res: &ghactions.IsVisibleUserResponse{
				IsVisible: true,
			},
			want: false,
		},
		{
			desc:             "does not call the API for a non-user type",
			id:               types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567)),
			numExpectedCalls: 0,
			want:             false,
		},
		{
			desc:             "returns true when bot is not visible",
			id:               testBotID,
			numExpectedCalls: 1,
			res: &ghactions.IsVisibleUserResponse{
				IsVisible: false,
			},
			want: true,
		},
		{
			desc:             "returns false when bot is visible",
			id:               testBotID,
			numExpectedCalls: 1,
			res: &ghactions.IsVisibleUserResponse{
				IsVisible: true,
			},
			want: false,
		},
		{
			desc:             "returns true when org is not visible",
			id:               testOrgID,
			numExpectedCalls: 1,
			res: &ghactions.IsVisibleUserResponse{
				IsVisible: false,
			},
			want: true,
		},
		{
			desc:             "returns false when org is visible",
			id:               testOrgID,
			numExpectedCalls: 1,
			res: &ghactions.IsVisibleUserResponse{
				IsVisible: true,
			},
			want: false,
		},
		{
			desc:             "returns false when the api returns an error",
			id:               types.GlobalID(testutils.EncodeGlobalID("User", 1234567)),
			numExpectedCalls: 1,
			res:              nil,
			returnedErr:      twirp.NewError(twirp.Internal, "test error"),
			want:             false,
		},
		{
			desc:             "returns true for a missing user",
			id:               types.GlobalID(testutils.EncodeGlobalID("User", 1234567)),
			numExpectedCalls: 1,
			res:              nil,
			returnedErr:      twirp.NotFoundError("missing user"),
			want:             true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockUsersAPI := NewMockUsersService(t)
			if tt.numExpectedCalls > 0 {
				mockUsersAPI.EXPECT().IsVisibleUser(mock.Anything, mock.Anything).Return(tt.res, tt.returnedErr)
			}

			c := NewMockTestClient(mockUsersAPI, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got, err := c.IsUserSpammy(context.TODO(), tt.id)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
			mockUsersAPI.AssertNumberOfCalls(t, "IsVisibleUser", tt.numExpectedCalls)
		})
	}
}

func TestResolveEnvironment(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	testEnvID := types.GlobalID(testutils.EncodeGlobalID("Environment", 1234567))
	testEnv := &Environment{
		GlobalID: testEnvID,
	}

	tests := []struct {
		desc             string
		env              string
		repoID           types.GlobalID
		returnedErr      error
		numExpectedCalls int
		res              *ghactions.ResolveActionsEnvironmentResponse
		want             *Environment
		wantNumCalls     int
	}{
		{
			desc:             "returns the environment with the correct global ID",
			env:              "staging",
			repoID:           testRepoID,
			numExpectedCalls: 1,
			res: &ghactions.ResolveActionsEnvironmentResponse{
				Environment: &ghactions.Environment{
					EnvironmentId: &ghactions.Identity{
						GlobalId: testEnvID.String(),
					},
				},
			},
			want:         testEnv,
			wantNumCalls: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockActionsService := NewMockActionsEnvironmentsService(t)
			mockActionsService.EXPECT().ResolveActionsEnvironment(mock.Anything, mock.Anything).Return(tt.res, tt.returnedErr)

			c := NewMockTestClient(nil, nil, mockActionsService, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got, err := c.ResolveEnvironment(context.TODO(), tt.env, tt.repoID)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
			mockActionsService.AssertNumberOfCalls(t, "ResolveActionsEnvironment", tt.wantNumCalls)
		})
	}
}

func TestGetEnvironmentRepository(t *testing.T) {
	testRepoID := 1234
	testEnvID := types.GlobalID(testutils.EncodeGlobalID("Environment", 1234567))

	tests := []struct {
		desc             string
		envID            types.GlobalID
		returnedErr      error
		numExpectedCalls int
		res              *ghactions.GetEnvironmentRepositoryResponse
		want             int64
		wantNumCalls     int
	}{
		{
			desc:             "returns the repository id for a given environment",
			envID:            testEnvID,
			numExpectedCalls: 1,
			res: &ghactions.GetEnvironmentRepositoryResponse{
				RepositoryDatabaseId: int64(testRepoID),
			},
			want:         int64(testRepoID),
			wantNumCalls: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockActionsService := NewMockActionsEnvironmentsService(t)
			mockActionsService.EXPECT().GetEnvironmentRepository(mock.Anything, mock.Anything).Return(tt.res, tt.returnedErr)

			c := NewMockTestClient(nil, nil, mockActionsService, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got, err := c.GetEnvironmentRepository(context.TODO(), tt.envID)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
			mockActionsService.AssertNumberOfCalls(t, "GetEnvironmentRepository", tt.wantNumCalls)
		})
	}
}

func TestGetBillingDetails(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))

	tests := []struct {
		desc             string
		env              string
		repoID           types.GlobalID
		returnedErr      error
		numExpectedCalls int
		res              *ghactions.GetBillingDetailsResponse
		want             *WorkflowBillingDetails
		wantNumCalls     int
	}{
		{
			desc:             "returns the expected billing details",
			env:              "staging",
			repoID:           testRepoID,
			numExpectedCalls: 1,
			res: &ghactions.GetBillingDetailsResponse{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			want: &WorkflowBillingDetails{
				IsActionsStorageAllowed: true,
				IsActionsUsageAllowed:   true,
				IsOwnerSpammy:           false,
			},
			wantNumCalls: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockWorkflowDetailsService := NewMockWorkflowDetailsService(t)
			mockWorkflowDetailsService.EXPECT().GetBillingDetails(mock.Anything, mock.Anything).Return(tt.res, tt.returnedErr)

			c := NewMockTestClient(nil, nil, nil, nil, nil, nil, mockWorkflowDetailsService, nil, nil, nil, nil, nil, nil, nil, false)
			got, err := c.GetBillingDetails(context.TODO(), tt.repoID)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
			mockWorkflowDetailsService.AssertNumberOfCalls(t, "GetBillingDetails", tt.wantNumCalls)
		})
	}
}

func TestGetAccountDetails(t *testing.T) {
	testEntityID := types.GlobalID(testutils.EncodeGlobalID("Organization", 1234567))

	tests := []struct {
		desc         string
		env          string
		entityID     types.GlobalID
		returnedErr  error
		res          *ghactions.GetAccountDetailsResponse
		want         *AccountDetails
		wantNumCalls int
	}{
		{
			desc:     "returns the expected billing details",
			env:      "staging",
			entityID: testEntityID,
			res: &ghactions.GetAccountDetailsResponse{
				AccountType:    "Organization",
				IsBillingOwner: true,
			},
			want: &AccountDetails{
				AccountType:    "Organization",
				IsBillingOwner: true,
			},
			wantNumCalls: 1,
		},
		{
			desc:         "returns the error if something goes wrong",
			env:          "staging",
			entityID:     testEntityID,
			res:          nil,
			want:         nil,
			returnedErr:  errors.New("error fetching account details"),
			wantNumCalls: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockAccountDetailsService := NewMockAccountDetailsService(t)
			mockAccountDetailsService.EXPECT().GetAccountDetails(mock.Anything, mock.Anything).Return(tt.res, tt.returnedErr)

			c := NewMockTestClient(nil, nil, nil, nil, nil, nil, nil, mockAccountDetailsService, nil, nil, nil, nil, nil, nil, false)
			got, err := c.GetAccountDetails(context.TODO(), tt.entityID)
			if tt.returnedErr != nil {
				assert.EqualError(t, err, tt.returnedErr.Error())
			} else {
				require.NoError(t, err)
			}
			assert.Equal(t, tt.want, got)
			mockAccountDetailsService.AssertNumberOfCalls(t, "GetAccountDetails", tt.wantNumCalls)
		})
	}
}

func TestGetCommitMessage(t *testing.T) {
	tests := []struct {
		name           string
		inputRepoID    int64
		inputCommitSHA types.CommitSha
		mockRes        *ghactions.GetCommitMessageResponse
		wantCommitMsg  types.CommitMessage
		wantErr        error
	}{
		{
			name:           "returns the expected commit message",
			inputRepoID:    42,
			inputCommitSHA: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
			mockRes: &ghactions.GetCommitMessageResponse{
				CommitMessage: "hello deer",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockRepoSvc := NewMockReposService(t)
			mockRepoSvc.EXPECT().GetCommitMessage(mock.Anything, &ghactions.GetCommitMessageRequest{
				RepositoryId: tt.inputRepoID,
				CommitSha:    tt.inputCommitSHA.String(),
			}).Return(&ghactions.GetCommitMessageResponse{}, tt.wantErr).Once()

			c := NewMockTestClient(nil, mockRepoSvc, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got, err := c.GetCommitMessage(context.TODO(), tt.inputRepoID, tt.inputCommitSHA)
			assert.Equal(t, tt.wantErr, err)
			assert.Equal(t, tt.wantCommitMsg, got)
		})
	}
}

func TestGetRepositoryOwnerId(t *testing.T) {
	tests := []struct {
		name        string
		repoID      int64
		mockRes     *ghactions.GetRepositoryOwnerIdResponse
		want        int64
		returnedErr error
	}{
		{
			name:   "returns the expected ownerID",
			repoID: 42,
			mockRes: &ghactions.GetRepositoryOwnerIdResponse{
				OwnerId: 1234567,
			},
			want:        1234567,
			returnedErr: nil,
		},
		{
			name:        "returns 0 if an the ownerID is not found",
			repoID:      101,
			mockRes:     &ghactions.GetRepositoryOwnerIdResponse{},
			want:        0,
			returnedErr: fmt.Errorf("error fetching repository owner id: %w", twirp.NewError(twirp.NotFound, "owner id not found")),
		},
		{
			name:        "returns 0 if there is an internal server error",
			repoID:      101,
			mockRes:     &ghactions.GetRepositoryOwnerIdResponse{},
			want:        0,
			returnedErr: fmt.Errorf("error fetching repository owner id: %w", twirp.NewError(twirp.Internal, "database not available")),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockRepoSvc := NewMockReposService(t)
			mockRepoSvc.EXPECT().GetRepositoryOwnerId(mock.Anything, &ghactions.GetRepositoryOwnerIdRequest{
				Id: tt.repoID,
			}).Return(tt.mockRes, tt.returnedErr).Once()

			c := NewMockTestClient(nil, mockRepoSvc, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got, err := c.GetRepositoryOwnerID(context.Background(), tt.repoID, true)
			assert.Equal(t, tt.returnedErr, err)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestGetRepositoryOwnerId_Caching(t *testing.T) {
	mockRepoSvc := NewMockReposService(t)

	req := ghactions.GetRepositoryOwnerIdRequest{Id: 42}
	resp := ghactions.GetRepositoryOwnerIdResponse{
		OwnerId: 1234567,
	}

	// Expect two calls to the Twirp API:
	// 1st call should cache the result
	// 2nd call from skipping the cache
	mockRepoSvc.EXPECT().GetRepositoryOwnerId(mock.Anything, &req).Return(&resp, nil).Twice()

	c := NewMockTestClient(nil, mockRepoSvc, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)

	got, err := c.GetRepositoryOwnerID(context.Background(), 42, true)
	require.NoError(t, err)
	assert.Equal(t, int64(1234567), got)

	// Use the cache, expect no calls to the Twirp API
	got, err = c.GetRepositoryOwnerID(context.Background(), 42, true)
	require.NoError(t, err)
	assert.Equal(t, int64(1234567), got)

	// Skip the cache, expect a second call to the Twirp API
	got, err = c.GetRepositoryOwnerID(context.Background(), 42, false)
	require.NoError(t, err)
	assert.Equal(t, int64(1234567), got)
}

func TestGetRepositoryOwners(t *testing.T) {

	repoA, _ := makeActor("R_kgDNA3g", "repoA", false)     // [0, 888]
	ownerA, _ := makeActor("U_kgDNA4U", "fakeuser", false) // [0, 901]
	repoB, _ := makeActor("R_kgDNA-c", "repoB", false)     // [0, 999]
	ownerB, _ := makeActor("O_kgDNA-o", "fakeorg", false)  // [0, 1002]

	tests := []struct {
		name              string
		repoID            int64
		getOwnersResponse *ghactions.GetRepositoryOwnersResponse
		getOwnersError    error
		expected          *RepositoryOwners
		expectedErr       error
	}{
		{
			name:   "happy path A",
			repoID: 888,
			getOwnersResponse: &ghactions.GetRepositoryOwnersResponse{
				Repository:    repoA,
				Owner:         ownerA,
				Business:      nil,
				OwnerPlanName: "fakePlan",
			},
			getOwnersError: nil,
			expected: &RepositoryOwners{
				Repository:    *toEntity(repoA),
				Owner:         *toEntity(ownerA),
				Business:      nil,
				OwnerPlanName: "fakePlan",
			},
			expectedErr: nil,
		},
		{
			name:   "happy path B",
			repoID: 999,
			getOwnersResponse: &ghactions.GetRepositoryOwnersResponse{
				Repository:    repoB,
				Owner:         ownerB,
				Business:      nil,
				OwnerPlanName: "fakePlan",
			},
			getOwnersError: nil,
			expected: &RepositoryOwners{
				Repository:    *toEntity(repoB),
				Owner:         *toEntity(ownerB),
				Business:      nil,
				OwnerPlanName: "fakePlan",
			},
			expectedErr: nil,
		},
		{
			name:              "no such repo",
			repoID:            999,
			getOwnersResponse: nil,
			getOwnersError:    twirp.InternalError("simulated twirp error"),
			expected:          nil,
			expectedErr:       twirp.InternalError("simulated twirp error"),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockRepoSvc := NewMockReposService(t)
			mockRepoSvc.EXPECT().GetRepositoryOwners(
				mock.Anything,
				&ghactions.GetRepositoryOwnersRequest{Id: tt.repoID},
			).Return(tt.getOwnersResponse, tt.getOwnersError).Once()

			c := NewMockTestClient(nil, mockRepoSvc, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got, err := c.GetRepositoryOwners(context.Background(), tt.repoID)
			assert.Equal(t, tt.expectedErr, err)
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestGetRepositoryOwnersByName(t *testing.T) {

	repoA, _ := makeActor("R_kgDNA3g", "repoA", false)     // [0, 888]
	ownerA, _ := makeActor("U_kgDNA4U", "fakeuser", false) // [0, 901]
	repoB, _ := makeActor("R_kgDNA-c", "repoB", false)     // [0, 999]
	ownerB, _ := makeActor("O_kgDNA-o", "fakeorg", false)  // [0, 1002]

	notFoundMsgRepoA := fmt.Sprintf("Repository not found: %s.", formatNWO(ownerA, repoA))

	tests := []struct {
		testDescription       string
		repoNameWithOwner     string
		repoID                int64
		nwoSearchResponse     *ghactions.FindRepositoriesByNameResponse
		nwoSearchErr          error
		getRepoOwnersResponse *ghactions.GetRepositoryOwnersResponse
		getRepoOwnersErr      error
		expected              *RepositoryOwners
		expectedErr           error
	}{
		{
			testDescription:   "happy path A",
			repoNameWithOwner: formatNWO(ownerA, repoA),
			repoID:            888,
			nwoSearchResponse: makeFindRepositoriesResponse(toRepository(ownerA, repoA, true), ""),
			nwoSearchErr:      nil,
			getRepoOwnersResponse: &ghactions.GetRepositoryOwnersResponse{
				Repository:    repoA,
				Owner:         ownerA,
				Business:      nil,
				OwnerPlanName: "fakePlan",
			},
			getRepoOwnersErr: nil,
			expected: &RepositoryOwners{
				Repository:    *toEntity(repoA),
				Owner:         *toEntity(ownerA),
				Business:      nil,
				OwnerPlanName: "fakePlan",
			},
			expectedErr: nil,
		},
		{
			testDescription:   "happy path B",
			repoNameWithOwner: formatNWO(ownerB, repoB),
			repoID:            999,
			nwoSearchResponse: makeFindRepositoriesResponse(toRepository(ownerB, repoB, true), ""),
			nwoSearchErr:      nil,
			getRepoOwnersResponse: &ghactions.GetRepositoryOwnersResponse{
				Repository:    repoB,
				Owner:         ownerB,
				Business:      nil,
				OwnerPlanName: "fakePlan",
			},
			getRepoOwnersErr: nil,
			expected: &RepositoryOwners{
				Repository:    *toEntity(repoB),
				Owner:         *toEntity(ownerB),
				Business:      nil,
				OwnerPlanName: "fakePlan",
			},
			expectedErr: nil,
		},
		{
			testDescription:       "simulate twirp error during nwo search",
			repoNameWithOwner:     formatNWO(ownerA, repoA),
			repoID:                888,
			nwoSearchResponse:     nil,
			nwoSearchErr:          twirp.InternalError("simulated twirp error"),
			getRepoOwnersResponse: nil, // we don't expect to get this far
			getRepoOwnersErr:      nil,
			expected:              nil,
			expectedErr:           twirp.InternalError("simulated twirp error"),
		},
		{
			testDescription:       "verify repo not found message is promoted to an error",
			repoNameWithOwner:     formatNWO(ownerA, repoA),
			repoID:                888,
			nwoSearchResponse:     makeFindRepositoriesResponse(nil, notFoundMsgRepoA),
			nwoSearchErr:          nil,
			getRepoOwnersResponse: nil, // we don't expect to get this far
			getRepoOwnersErr:      nil,
			expected:              nil,
			expectedErr:           terrors.NewNotFoundError(errors.New(notFoundMsgRepoA)),
		},
		{
			testDescription:       "verify empty result set is promoted to an error",
			repoNameWithOwner:     formatNWO(ownerA, repoA),
			repoID:                888,
			nwoSearchResponse:     makeFindRepositoriesResponse(nil, ""),
			nwoSearchErr:          nil,
			getRepoOwnersResponse: nil, // we don't expect to get this far
			getRepoOwnersErr:      nil,
			expected:              nil,
			expectedErr:           errors.New("twirp FindRepositoriesByName returned an empty array"),
		},
	}

	for _, tt := range tests {
		t.Run(tt.testDescription, func(t *testing.T) {
			mockRepoSvc := NewMockReposService(t)
			mockRepoSvc.EXPECT().FindRepositoriesByName(
				mock.Anything,
				&ghactions.FindRepositoriesByNameRequest{Nwos: []string{tt.repoNameWithOwner}},
			).Return(tt.nwoSearchResponse, tt.nwoSearchErr).Once()
			if tt.getRepoOwnersResponse != nil {
				mockRepoSvc.EXPECT().GetRepositoryOwners(
					mock.Anything,
					&ghactions.GetRepositoryOwnersRequest{Id: tt.repoID},
				).Return(tt.getRepoOwnersResponse, tt.getRepoOwnersErr).Once()
			}

			c := NewMockTestClient(nil, mockRepoSvc, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got, err := c.GetRepositoryOwnersByName(context.Background(), tt.repoNameWithOwner)
			if tt.expectedErr != nil {
				assert.Error(t, err)
				assert.ErrorContains(t, err, tt.expectedErr.Error())
			} else {
				// inconsistency note:  gocritic linter flagged the following line with "prefer require.NoError"
				require.NoError(t, err)
			}
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestFindRepositoriesByName(t *testing.T) {
	overLimitNwos := make([]string, 0, 110)
	for i := 0; i < 110; i++ {
		overLimitNwos = append(overLimitNwos, fmt.Sprintf("%s%d", "org1/repo", i))
	}

	tests := []struct {
		name        string
		nwos        []string
		mockRes     []*ghactions.FindRepositoriesByNameResponse
		want        *RepositoriesInfo
		returnedErr error
	}{
		{
			name: "returns the repository",
			nwos: []string{"org1/repo1"},
			mockRes: []*ghactions.FindRepositoriesByNameResponse{
				{
					Repositories: []*ghactions.Repository{
						{
							Id:            42,
							Name:          "repo1",
							GlobalRelayId: "MDQ6VXNlcjI=",
							OwnerLogin:    "org1",
							Visibility:    1,
						},
					},
					RepositoriesNotFoundErrorMessage: "",
				},
			},
			want: &RepositoriesInfo{
				Repositories: []*ghactions.Repository{
					{
						Id:            42,
						Name:          "repo1",
						GlobalRelayId: "MDQ6VXNlcjI=",
						OwnerLogin:    "org1",
						Visibility:    1,
					},
				},
				RepositoriesNotFoundErrorMessage: "",
			},
		},
		{
			name: "returns the expected repositories",
			nwos: []string{"org1/repo1", "org2/repo2", "org3/repo3"},
			mockRes: []*ghactions.FindRepositoriesByNameResponse{
				{
					Repositories: []*ghactions.Repository{
						{
							Id:            42,
							Name:          "repo1",
							GlobalRelayId: "MDQ6VXNlcjI=",
							OwnerLogin:    "org1",
							Visibility:    1,
						},
						{
							Id:            43,
							Name:          "repo2",
							GlobalRelayId: "MDQ6VXNkcjI=",
							OwnerLogin:    "org2",
							Visibility:    2,
						},
						{
							Id:            44,
							Name:          "repo3",
							GlobalRelayId: "MDQ6VXNkcjI=",
							OwnerLogin:    "org3",
							Visibility:    3,
						},
					},
					RepositoriesNotFoundErrorMessage: "",
				},
			},
			want: &RepositoriesInfo{
				Repositories: []*ghactions.Repository{
					{
						Id:            42,
						Name:          "repo1",
						GlobalRelayId: "MDQ6VXNlcjI=",
						OwnerLogin:    "org1",
						Visibility:    1,
					},
					{
						Id:            43,
						Name:          "repo2",
						GlobalRelayId: "MDQ6VXNkcjI=",
						OwnerLogin:    "org2",
						Visibility:    2,
					},
					{
						Id:            44,
						Name:          "repo3",
						GlobalRelayId: "MDQ6VXNkcjI=",
						OwnerLogin:    "org3",
						Visibility:    3,
					},
				},
				RepositoriesNotFoundErrorMessage: "",
			},
		},
		{
			name: "returns one repo when duplicate nwo's are sent",
			nwos: []string{"org1/repo1", "org1/repo1"},
			mockRes: []*ghactions.FindRepositoriesByNameResponse{
				{
					Repositories: []*ghactions.Repository{
						{
							Id:            42,
							Name:          "repo1",
							GlobalRelayId: "MDQ6VXNlcjI=",
							OwnerLogin:    "org1",
							Visibility:    1,
						},
					},
					RepositoriesNotFoundErrorMessage: "",
				},
			},
			want: &RepositoriesInfo{
				Repositories: []*ghactions.Repository{
					{
						Id:            42,
						Name:          "repo1",
						GlobalRelayId: "MDQ6VXNlcjI=",
						OwnerLogin:    "org1",
						Visibility:    1,
					},
				},
				RepositoriesNotFoundErrorMessage: "",
			},
		},
		{
			name: "returns appended response when > 100 nwos",
			nwos: overLimitNwos,
			mockRes: []*ghactions.FindRepositoriesByNameResponse{
				{
					Repositories: []*ghactions.Repository{
						{
							Id:            42,
							Name:          "repo1",
							GlobalRelayId: "MDQ6VXNlcjI=",
							OwnerLogin:    "org1",
							Visibility:    1,
						},
					},
					RepositoriesNotFoundErrorMessage: "",
				},
				{
					Repositories: []*ghactions.Repository{
						{
							Id:            43,
							Name:          "repo2",
							GlobalRelayId: "MDQ6VXNkcjI=",
							OwnerLogin:    "org2",
							Visibility:    3,
						},
					},
					RepositoriesNotFoundErrorMessage: "",
				},
			},
			want: &RepositoriesInfo{
				Repositories: []*ghactions.Repository{
					{
						Id:            42,
						Name:          "repo1",
						GlobalRelayId: "MDQ6VXNlcjI=",
						OwnerLogin:    "org1",
						Visibility:    1,
					},
					{
						Id:            43,
						Name:          "repo2",
						GlobalRelayId: "MDQ6VXNkcjI=",
						OwnerLogin:    "org2",
						Visibility:    3,
					},
				},
				RepositoriesNotFoundErrorMessage: "",
			},
		},
		{
			name: "returns error message in case of repo not found",
			nwos: []string{"org1/repo1", "org2/repo2"},
			mockRes: []*ghactions.FindRepositoriesByNameResponse{
				{
					Repositories:                     []*ghactions.Repository(nil),
					RepositoriesNotFoundErrorMessage: "Repositories not found: org1/repo1 and org2/repo2.",
				},
			},
			want: &RepositoriesInfo{
				Repositories:                     []*ghactions.Repository{},
				RepositoriesNotFoundErrorMessage: "Repositories not found: org1/repo1 and org2/repo2.",
			},
		},
		{
			name: "returns nil when no nwos are provided",
			nwos: []string{},
			mockRes: []*ghactions.FindRepositoriesByNameResponse{
				{
					Repositories:                     []*ghactions.Repository{},
					RepositoriesNotFoundErrorMessage: "",
				},
			},
			want: &RepositoriesInfo{
				Repositories:                     []*ghactions.Repository{},
				RepositoriesNotFoundErrorMessage: "",
			},
			returnedErr: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockRepoSvc := NewMockReposService(t)

			for index, value := range tt.mockRes {
				start := index * FindRepositoriesByNameMaxBatchSize
				end := start + FindRepositoriesByNameMaxBatchSize
				if end > len(tt.nwos) {
					end = len(tt.nwos)
				}

				if len(tt.nwos) != 0 {
					mockRepoSvc.EXPECT().FindRepositoriesByName(mock.Anything, &ghactions.FindRepositoriesByNameRequest{
						Nwos: tt.nwos[start:end],
					}).Return(value, tt.returnedErr).Once()
				}
			}

			c := NewMockTestClient(nil, mockRepoSvc, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			got, err := c.FindRepositoriesByName(context.TODO(), tt.nwos)

			if tt.returnedErr != nil {
				assert.EqualError(t, err, "error fetching repositories: "+tt.returnedErr.Error())
			} else {
				require.NoError(t, err)
			}

			assert.Equal(t, tt.want, got)
		})
	}
}

func TestGetNextGlobalID(t *testing.T) {
	legacyRepoGID := testutils.EncodeGlobalID("Repository", 1234567)

	tests := []struct {
		desc            string
		legacyOrNextGID string
		clientRes       *ghactions.GetNextGlobalIdResponse
		clientErr       error
		want            types.GlobalID
		wantErr         bool
		wantNotFoundErr bool
		wantNumCalls    int
	}{
		{
			desc:            "returns same global id for empty global id",
			legacyOrNextGID: "",
			want:            "",
			wantNumCalls:    0,
		},
		{
			desc:            "returns next global id",
			legacyOrNextGID: legacyRepoGID,
			clientRes: &ghactions.GetNextGlobalIdResponse{
				NextGlobalId: "R_next",
			},
			want:         "R_next",
			wantNumCalls: 1,
		},
		{
			desc:            "next global id not foumd",
			legacyOrNextGID: legacyRepoGID,
			clientErr:       twirp.NewError(twirp.NotFound, "next global id not found"),
			wantErr:         true,
			wantNotFoundErr: true,
			wantNumCalls:    1,
		},
		{
			desc:            "internal error",
			legacyOrNextGID: legacyRepoGID,
			clientErr:       twirp.NewError(twirp.Internal, "database unavailable"),
			wantErr:         true,
			wantNotFoundErr: false,
			wantNumCalls:    1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockSvc := NewMockGlobalIDService(t)
			if !types.IsZeroValueGlobalID(tt.legacyOrNextGID) {
				mockSvc.EXPECT().GetNextGlobalId(mock.Anything, mock.Anything).Return(tt.clientRes, tt.clientErr)
			}
			c := NewMockTestClient(nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, mockSvc, nil, nil, false)

			got, gotErr := c.GetNextGlobalID(context.TODO(), tt.legacyOrNextGID)
			if tt.wantErr {
				assert.Error(t, gotErr)
				assert.Equal(t, tt.wantNotFoundErr, terrors.IsNotFoundError(gotErr))
			} else {
				require.NoError(t, gotErr)
			}

			assert.Equal(t, tt.want, got)

			mockSvc.AssertNumberOfCalls(t, "GetNextGlobalId", tt.wantNumCalls)
		})
	}
}

// test the bulk method
func TestGetNextGlobalIDs(t *testing.T) {
	testRepoID := testutils.EncodeGlobalID("Repository", 1234567)
	actorID := testutils.EncodeGlobalID("User", 7654321)
	notFoundID := testutils.EncodeGlobalID("Environment", 4040404)

	type res struct {
		data *ghactions.GetNextGlobalIdResponse
		err  error
	}

	tests := []struct {
		desc             string
		legacyOrNextGIDs []string
		clientRes        map[string]res
		clientErr        error
		want             map[string]types.GlobalID
		wantAllIDsFound  bool
		wantErr          bool
		wantNumCalls     int
	}{
		{
			desc:             "returns single next id",
			legacyOrNextGIDs: []string{testRepoID},
			clientRes: map[string]res{
				string(testRepoID): {
					&ghactions.GetNextGlobalIdResponse{
						NextGlobalId: "R_next",
					},
					nil,
				},
			},
			want: map[string]types.GlobalID{
				testRepoID: "R_next",
			},
			wantAllIDsFound: true,
			wantNumCalls:    1,
		},
		{
			desc:             "returns multiple next ids",
			legacyOrNextGIDs: []string{testRepoID, actorID},
			clientRes: map[string]res{
				string(testRepoID): {
					&ghactions.GetNextGlobalIdResponse{
						NextGlobalId: "R_next",
					},
					nil,
				},
				string(actorID): {
					&ghactions.GetNextGlobalIdResponse{
						NextGlobalId: "U_next",
					},
					nil,
				},
			},
			want: map[string]types.GlobalID{
				testRepoID: "R_next",
				actorID:    "U_next",
			},
			wantAllIDsFound: true,
			wantNumCalls:    2,
		},
		{
			desc:             "leaves out next global ids not found",
			legacyOrNextGIDs: []string{testRepoID, actorID, notFoundID},
			clientRes: map[string]res{
				testRepoID: {
					&ghactions.GetNextGlobalIdResponse{
						NextGlobalId: "R_next",
					},
					nil,
				},
				actorID: {
					&ghactions.GetNextGlobalIdResponse{
						NextGlobalId: "U_next",
					},
					nil,
				},
				notFoundID: {
					nil,
					twirp.NewError(twirp.NotFound, "next global id not found"),
				},
			},
			want: map[string]types.GlobalID{
				testRepoID: "R_next",
				actorID:    "U_next",
			},
			wantAllIDsFound: false,
			wantNumCalls:    3,
		},
		{
			desc:             "propagates errors other than not found",
			legacyOrNextGIDs: []string{testRepoID, actorID},
			clientRes: map[string]res{
				testRepoID: {
					&ghactions.GetNextGlobalIdResponse{
						NextGlobalId: "R_next",
					},
					nil,
				},
				actorID: {
					nil,
					twirp.NewError(twirp.Internal, "database unavailable"),
				},
			},
			wantErr:      true,
			wantNumCalls: 2,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockSvc := NewMockGlobalIDService(t)
			for globalID, resp := range tt.clientRes {
				req := &ghactions.GetNextGlobalIdRequest{
					GlobalId: globalID,
				}
				mockSvc.EXPECT().GetNextGlobalId(mock.Anything, req).Return(resp.data, resp.err)
			}

			c := NewMockTestClient(nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, mockSvc, nil, nil, false)

			got, allIDsFound, gotErr := c.GetNextGlobalIDs(context.TODO(), tt.legacyOrNextGIDs)
			if tt.wantErr {
				assert.Error(t, gotErr)
				// The bulk method should return false for allIDsFound if any of the IDs are not found
				assert.False(t, terrors.IsNotFoundError(gotErr))
			} else {
				require.NoError(t, gotErr)
			}

			assert.Equal(t, tt.want, got)
			assert.Equal(t, tt.wantAllIDsFound, allIDsFound)

			mockSvc.AssertNumberOfCalls(t, "GetNextGlobalId", tt.wantNumCalls)
		})
	}
}

func TestGetAdditionalWorkflows(t *testing.T) {
	testRepoID := int64(100)
	eventType := "pull_request"
	responseRepo1GlobalID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	responseRepo2GlobalID := types.GlobalID(testutils.EncodeGlobalID("Repository", 3456678))
	responseOwnerGlobalID := types.GlobalID(testutils.EncodeGlobalID("Organization", 1234567))
	oid := types.CommitSha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	baseRef := types.GitRef("refs/heads/main")

	tests := []struct {
		desc            string
		repoID          int64
		eventType       string
		clientRes       *ghactions.GetAdditionalWorkflowsResponse
		clientErr       error
		want            *AdditionalWorkflows
		wantErr         bool
		wantNotFoundErr bool
		wantNumCalls    int
	}{
		{
			desc:            "invalid repository id",
			repoID:          testRepoID,
			eventType:       eventType,
			clientErr:       twirp.NewError(twirp.NotFound, "repository not found for given repoID"),
			wantErr:         true,
			wantNotFoundErr: true,
			wantNumCalls:    1,
		},
		{
			desc:            "internal error",
			repoID:          testRepoID,
			eventType:       eventType,
			clientErr:       twirp.NewError(twirp.Internal, "internal error from gh/gh"),
			wantErr:         true,
			wantNotFoundErr: false,
			wantNumCalls:    1,
		},
		{
			desc:            "no ruleset workflows configured for organization",
			repoID:          testRepoID,
			eventType:       eventType,
			wantErr:         false,
			wantNotFoundErr: false,
			clientRes: &ghactions.GetAdditionalWorkflowsResponse{
				RulesetWorkflows: []*ghactions.RequiredWorkflow{},
			},
			want: &AdditionalWorkflows{
				RulesetWorkflows: []*RequiredWorkflow{},
			},
			wantNumCalls: 1,
		},
		{
			desc:            "return ruleset workflows configured for organization",
			repoID:          testRepoID,
			eventType:       eventType,
			wantErr:         false,
			wantNotFoundErr: false,
			clientRes: &ghactions.GetAdditionalWorkflowsResponse{
				RulesetWorkflows: []*ghactions.RequiredWorkflow{
					{
						RepositoryId: &ghactions.Identity{
							GlobalId: responseRepo1GlobalID.String(),
						},
						OwnerId: &ghactions.Identity{
							GlobalId: responseOwnerGlobalID.String(),
						},
						RepositoryNwo:  "test-org/test-repo",
						Path:           ".github/required-workflows/test.yml",
						Ref:            "ref/heads/main",
						RepoDatabaseId: 1,
						Visibility:     ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
					},
					{
						RepositoryId: &ghactions.Identity{
							GlobalId: responseRepo2GlobalID.String(),
						},
						OwnerId: &ghactions.Identity{
							GlobalId: responseOwnerGlobalID.String(),
						},
						RepositoryNwo:  "test-org/test-repo-2",
						Path:           ".github/required-workflows/required.yml",
						Ref:            "ref/heads/main",
						RepoDatabaseId: 2,
						Visibility:     ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
					},
				},
			},
			want: &AdditionalWorkflows{
				RulesetWorkflows: []*RequiredWorkflow{
					{
						RepoID:         responseRepo1GlobalID,
						OwnerID:        responseOwnerGlobalID,
						RepoNwo:        "test-org/test-repo",
						Path:           ".github/required-workflows/test.yml",
						Ref:            "ref/heads/main",
						RepoDatabaseID: 1,
						RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
					},
					{
						RepoID:         responseRepo2GlobalID,
						OwnerID:        responseOwnerGlobalID,
						RepoNwo:        "test-org/test-repo-2",
						Path:           ".github/required-workflows/required.yml",
						Ref:            "ref/heads/main",
						RepoDatabaseID: 2,
						RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
					},
				},
			},
			wantNumCalls: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockSvc := NewMockReposService(t)
			mockSvc.EXPECT().GetAdditionalWorkflows(mock.Anything, mock.Anything).Return(tt.clientRes, tt.clientErr)
			c := NewMockTestClient(nil, mockSvc, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)

			event := EventReference{
				BaseRef:   baseRef,
				BeforeOid: oid,
				AfterOid:  oid,
				Type:      tt.eventType,
			}

			got, gotErr := c.GetAdditionalWorkflows(context.TODO(), tt.repoID, event)
			if tt.wantErr {
				assert.Error(t, gotErr)
				assert.Equal(t, tt.wantNotFoundErr, terrors.IsNotFoundError(gotErr))
			} else {
				require.NoError(t, gotErr)
			}

			assert.Equal(t, tt.want, got)

			mockSvc.AssertNumberOfCalls(t, "GetAdditionalWorkflows", tt.wantNumCalls)
		})
	}
}

func TestUpdateWorkflowRun(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	workflowRunID := int64(123)
	workflowRunName := "run name"

	tests := []struct {
		desc        string
		returnedErr error
	}{
		{
			desc:        "returns an error if one is returned from the checks API",
			returnedErr: twirp.NewError(twirp.Internal, "test error"),
		},
		{
			desc: "returns nil on success",
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockChecksAPI := NewMockChecksService(t)
			mockChecksAPI.EXPECT().UpdateWorkflowRun(mock.Anything, &ghactions.UpdateWorkflowRunRequest{
				RepositoryId: &ghactions.Identity{
					GlobalId: testRepoID.String(),
				},
				WorkflowRunId: workflowRunID,
				RunName:       workflowRunName,
			}).Return(&ghactions.UpdateWorkflowRunResponse{}, tt.returnedErr)

			c := NewMockTestClient(nil, nil, nil, nil, nil, nil, nil, nil, mockChecksAPI, nil, nil, nil, nil, nil, false)

			err := c.UpdateWorkflowRun(context.TODO(), testRepoID, workflowRunID, workflowRunName)

			if tt.returnedErr != nil {
				assert.EqualError(t, err, tt.returnedErr.Error())
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestFindTreeIDAndPreviousWorkflowRunToReuse(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	workflowPath := ".github/workflows/test.yml"
	eventType := "push"
	commitSha := types.CommitSha("deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
	testCheckSuiteId := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 1234567))

	tests := []struct {
		desc                         string
		returnedErr                  error
		foundReusableCheckSuite      bool
		expectedTreeId               types.CommitSha
		expectedCheckSuiteGlobalId   types.GlobalID
		expectedCheckSuiteDatabaseId int64
	}{
		{
			desc:                    "returns an error if one is returned from the twirp endpoint",
			returnedErr:             twirp.NewError(twirp.Internal, "test error"),
			foundReusableCheckSuite: false,
			expectedTreeId:          types.CommitSha(""),
		},
		{
			desc:                    "returns a treeID if one is recieved on success",
			foundReusableCheckSuite: false,
			expectedTreeId:          types.CommitSha("sometreeid"),
		},
		{
			desc:                         "returns a treeID if one is recieved on success",
			foundReusableCheckSuite:      true,
			expectedTreeId:               types.CommitSha("sometreeid"),
			expectedCheckSuiteGlobalId:   testCheckSuiteId,
			expectedCheckSuiteDatabaseId: 1234567,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockChecksAPI := NewMockChecksService(t)

			var checkSuiteToCloneReponse *ghactions.CheckSuite = nil

			if tt.foundReusableCheckSuite {
				checkSuiteToCloneReponse = &ghactions.CheckSuite{
					CheckSuiteGlobalId: &ghactions.Identity{
						GlobalId: tt.expectedCheckSuiteGlobalId.String(),
					},
					CheckSuiteDatabaseId: tt.expectedCheckSuiteDatabaseId,
				}
			}

			mockChecksAPI.EXPECT().FindPreviousWorkflowRunToReuse(mock.Anything, &ghactions.FindPreviousWorkflowRunToReuseRequest{
				RepositoryId: &ghactions.Identity{
					GlobalId: testRepoID.String(),
				},
				WorkflowPath: workflowPath,
				EventType:    eventType,
				CommitSha:    commitSha.String(),
			}).Return(&ghactions.FindPreviousWorkflowRunToReuseResponse{
				TreeId:            tt.expectedTreeId.String(),
				CheckSuiteToClone: checkSuiteToCloneReponse,
			}, tt.returnedErr)

			c := NewMockTestClient(nil, nil, nil, nil, nil, nil, nil, nil, mockChecksAPI, nil, nil, nil, nil, nil, false)

			returnedTreeId, checkSuiteToClone, err := c.FindTreeIDAndPreviousWorkflowRunToReuse(context.TODO(), testRepoID, workflowPath, eventType, commitSha)

			if tt.returnedErr != nil {
				assert.EqualError(t, err, tt.returnedErr.Error())
			} else {
				require.NoError(t, err)
			}

			assert.Equal(t, tt.expectedTreeId, returnedTreeId)

			if tt.foundReusableCheckSuite {
				assert.Equal(t, tt.expectedCheckSuiteGlobalId, checkSuiteToClone.GlobalID)
				assert.Equal(t, tt.expectedCheckSuiteDatabaseId, checkSuiteToClone.DatabaseID)
			} else {
				require.Nil(t, checkSuiteToClone)
			}
		})
	}
}

func TestGetAccountDetailsForRepository(t *testing.T) {
	testRepoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))

	tests := []struct {
		desc                string
		returnedErr         error
		expectedPlanName    ghactions.PlanName
		expectedAccountType ghactions.RepositoryOwner
	}{
		{
			desc:        "returns an error if one is returned from the twirp endpoint",
			returnedErr: twirp.NewError(twirp.Internal, "test error"),
		},
		{
			desc:                "returns expected response for valid inputs",
			returnedErr:         nil,
			expectedPlanName:    ghactions.PlanName_PLAN_NAME_BUSINESS,
			expectedAccountType: ghactions.RepositoryOwner_REPOSITORY_OWNER_ORGANIZATION,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockAccountDetailsAPI := NewMockAccountDetailsService(t)

			mockAccountDetailsAPI.EXPECT().GetAccountDetailsForRepository(mock.Anything, &ghactions.GetAccountDetailsForRepositoryRequest{
				RepositoryId: &ghactions.Identity{
					GlobalId: testRepoID.String(),
				},
			}).Return(&ghactions.GetAccountDetailsForRepositoryResponse{
				AccountType: tt.expectedAccountType,
				PlanName:    tt.expectedPlanName,
			}, tt.returnedErr)

			c := NewMockTestClient(nil, nil, nil, nil, nil, nil, nil, mockAccountDetailsAPI, nil, nil, nil, nil, nil, nil, false)

			repoAccountDetails, err := c.GetAccountDetailsForRepository(context.TODO(), testRepoID)

			if tt.returnedErr != nil {
				assert.EqualError(t, err, tt.returnedErr.Error())
				assert.Nil(t, repoAccountDetails)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expectedAccountType, repoAccountDetails.OwnerType)
				assert.Equal(t, tt.expectedPlanName, repoAccountDetails.PlanName)
			}
		})
	}
}

func TestResolveActions(t *testing.T) {
	testRepoID := 4234
	testRunID := 100
	testJobID := "test-job"
	testTenantID := 42

	tests := []struct {
		desc          string
		isMultiTenant bool
		setupMocks    func() *MockResolveActionsService
		wantErr       bool
		actions       []*Action
		expectedResp  []*ResolveActionsResponse
	}{
		{
			desc: "returns an error if one is returned from the twirp endpoint",
			setupMocks: func() *MockResolveActionsService {
				mockResolveActionsAPI := NewMockResolveActionsService(t)
				mockResolveActionsAPI.EXPECT().ResolveActions(mock.Anything, &ghactions.ResolveActionsRequest{
					Actions: []*ghactions.Action{
						{
							Nwo: "test-org/test-repo",
							Ref: "v1",
						},
					},
					WorkflowRunId:           int64(testRunID),
					JobId:                   testJobID,
					WorkflowRepoId:          int64(testRepoID),
					ShouldInstrumentRequest: true,
				}).Return(nil, twirp.NewError(twirp.Internal, "test error"))
				return mockResolveActionsAPI
			},
			actions: []*Action{
				{
					Nwo:  "test-org/test-repo",
					Ref:  "v1",
					Path: ".github/actions/test",
				},
			},
			wantErr: true,
		},
		{
			desc: "returns expected response after resolving actions",
			setupMocks: func() *MockResolveActionsService {
				mockResolveActionsAPI := NewMockResolveActionsService(t)
				mockResolveActionsAPI.EXPECT().ResolveActions(mock.Anything, &ghactions.ResolveActionsRequest{
					Actions: []*ghactions.Action{
						{
							Nwo: "test-org-1/test-repo-1",
							Ref: "v1",
						},
						{
							Nwo: "test-org-2/test-repo-2",
							Ref: "main",
						},
						{
							Nwo: "test-org-3/test-repo-3",
							Ref: "4dcxweEfcvsfDAFsfmvDeWWcs",
						},
					},
					WorkflowRunId:           int64(testRunID),
					JobId:                   testJobID,
					WorkflowRepoId:          int64(testRepoID),
					ShouldInstrumentRequest: true,
				}).Return(&ghactions.ResolveActionsResponse{
					ResolvedActions: []*ghactions.ResolvedActionContent{
						{
							ResolvedActionContent: &ghactions.ResolvedActionContent_ResolvedAction{
								ResolvedAction: &ghactions.ResolvedAction{
									Id:              20,
									Name:            "test-org-1/test-repo-1",
									ResolvedName:    "test-org-1/test-repo-1",
									Ref:             "v1",
									ResolvedRef:     "v1",
									ResolvedSha:     "512asfasfdsg",
									Visibility:      "public",
									ZipUrl:          "test-zip-url",
									TarUrl:          "test-tar-url",
									ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
								},
							},
						},
						{
							ResolvedActionContent: &ghactions.ResolvedActionContent_Error{
								Error: &ghactions.ResolveActionError{
									ErrorCode:    422,
									ErrorMessage: fmt.Sprintf("Unable to find the given repository for the action test-org-2/test-repo-2"),
								},
							},
						},
						{
							ResolvedActionContent: &ghactions.ResolvedActionContent_ResolvedAction{
								ResolvedAction: &ghactions.ResolvedAction{
									Id:              21,
									Name:            "test-org-3/test-repo-3",
									ResolvedName:    "test-org-3/test-repo-3",
									Ref:             "4dcxweEfcvsfDAFsfmvDeWWcs",
									ResolvedRef:     "4dcxweEfcvsfDAFsfmvDeWWcs",
									ResolvedSha:     "4dcxweEfcvsfDAFsfmvDeWWcs",
									Visibility:      "private",
									ZipUrl:          "test-zip-url-1",
									TarUrl:          "test-tar-url-1",
									ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
								},
							},
						},
					},
				}, nil)
				return mockResolveActionsAPI
			},
			actions: []*Action{
				{
					Nwo:  "test-org-1/test-repo-1",
					Ref:  "v1",
					Path: ".github/actions/test",
				},
				{
					Nwo:  "test-org-2/test-repo-2",
					Ref:  "main",
					Path: "",
				},
				{
					Nwo:  "test-org-3/test-repo-3",
					Ref:  "4dcxweEfcvsfDAFsfmvDeWWcs",
					Path: "",
				},
			},
			wantErr: false,
			expectedResp: []*ResolveActionsResponse{
				{
					ResolvedAction: &ghactions.ResolvedAction{
						Id:              20,
						Name:            "test-org-1/test-repo-1",
						ResolvedName:    "test-org-1/test-repo-1",
						Ref:             "v1",
						ResolvedRef:     "v1",
						ResolvedSha:     "512asfasfdsg",
						Visibility:      "public",
						ZipUrl:          "test-zip-url",
						TarUrl:          "test-tar-url",
						ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
					},
				},
				{
					Error: &ResolveActionsErr{
						Action: &Action{
							Nwo:  "test-org-2/test-repo-2",
							Ref:  "main",
							Path: "",
						},
						Err: errors.New("Unable to find the given repository for the action test-org-2/test-repo-2"),
					},
				},
				{
					ResolvedAction: &ghactions.ResolvedAction{
						Id:              21,
						Name:            "test-org-3/test-repo-3",
						ResolvedName:    "test-org-3/test-repo-3",
						Ref:             "4dcxweEfcvsfDAFsfmvDeWWcs",
						ResolvedRef:     "4dcxweEfcvsfDAFsfmvDeWWcs",
						ResolvedSha:     "4dcxweEfcvsfDAFsfmvDeWWcs",
						Visibility:      "private",
						ZipUrl:          "test-zip-url-1",
						TarUrl:          "test-tar-url-1",
						ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
					},
				},
			},
		},
		{
			desc: "returns expected response after resolving actions in batches",
			setupMocks: func() *MockResolveActionsService {
				mockResolveActionsAPI := NewMockResolveActionsService(t)
				inputActions := getInputActionsForTwirpCall()
				respActions := getResolvedActionsTwirpResponse()
				mockResolveActionsAPI.EXPECT().ResolveActions(mock.Anything, &ghactions.ResolveActionsRequest{
					Actions:                 inputActions[0:ResolveActionsBatchSize],
					WorkflowRunId:           int64(testRunID),
					JobId:                   testJobID,
					WorkflowRepoId:          int64(testRepoID),
					ShouldInstrumentRequest: true,
				}).Return(&ghactions.ResolveActionsResponse{
					ResolvedActions: respActions.ResolvedActions[0:ResolveActionsBatchSize],
				}, nil)
				mockResolveActionsAPI.EXPECT().ResolveActions(mock.Anything, &ghactions.ResolveActionsRequest{
					Actions:                 inputActions[ResolveActionsBatchSize:],
					WorkflowRunId:           int64(testRunID),
					JobId:                   testJobID,
					WorkflowRepoId:          int64(testRepoID),
					ShouldInstrumentRequest: true,
				}).Return(&ghactions.ResolveActionsResponse{
					ResolvedActions: respActions.ResolvedActions[ResolveActionsBatchSize:],
				}, nil)
				return mockResolveActionsAPI
			},
			actions:      getInputActions(),
			wantErr:      false,
			expectedResp: getResolvedActionsExpectedResponse(),
		},
		{
			desc:          "returns expected response after resolving actions in multi-tenant mode",
			isMultiTenant: true,
			setupMocks: func() *MockResolveActionsService {
				mockResolveActionsAPI := NewMockResolveActionsService(t)
				mockResolveActionsAPI.EXPECT().ResolveActions(mock.Anything, &ghactions.ResolveActionsRequest{
					Actions: []*ghactions.Action{
						{
							Nwo: "test-org-1/test-repo-1",
							Ref: "v1",
						},
						{
							Nwo: "@actions/checkout",
							Ref: "v1",
						},
						{
							Nwo: "test-org-2/test-repo-2/test-action.yml",
							Ref: "main",
						},
					},
					WorkflowRunId:           int64(testRunID),
					JobId:                   testJobID,
					WorkflowRepoId:          int64(testRepoID),
					ShouldInstrumentRequest: true,
				}).Return(&ghactions.ResolveActionsResponse{
					ResolvedActions: []*ghactions.ResolvedActionContent{
						{
							ResolvedActionContent: &ghactions.ResolvedActionContent_ResolvedAction{
								ResolvedAction: &ghactions.ResolvedAction{
									Id:              20,
									Name:            "test-org-1/test-repo-1",
									ResolvedName:    "test-org-1/test-repo-1",
									Ref:             "v1",
									ResolvedRef:     "v1",
									ResolvedSha:     "512asfasfdsg",
									Visibility:      "internal",
									ZipUrl:          "test-zip-url",
									TarUrl:          "test-tar-url",
									ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
								},
							},
						},
						{
							ResolvedActionContent: &ghactions.ResolvedActionContent_ResolvedAction{
								ResolvedAction: &ghactions.ResolvedAction{
									Id:              20,
									Name:            "@actions/checkout",
									ResolvedName:    "@actions/checkout",
									Ref:             "v1",
									ResolvedRef:     "v1",
									ResolvedSha:     "512asfasfdsg",
									Visibility:      "public",
									ZipUrl:          "test-zip-url",
									TarUrl:          "test-tar-url",
									ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
								},
							},
						},
						{
							ResolvedActionContent: &ghactions.ResolvedActionContent_ResolvedAction{
								ResolvedAction: &ghactions.ResolvedAction{
									Id:           20,
									Name:         "test-org-2/test-repo-2/test-action.yml",
									ResolvedName: "test-org-2/test-repo-2/test-action.yml",
									Ref:          "main",
									ResolvedRef:  "main",
									ResolvedSha:  "512asfasfdsg",
									Visibility:   "private",
									ZipUrl:       "test-zip-url",
									TarUrl:       "test-tar-url",
								},
							},
						},
					},
				}, nil)
				return mockResolveActionsAPI
			},
			actions: []*Action{
				{
					Nwo:  "test-org-1/test-repo-1",
					Ref:  "v1",
					Path: ".github/actions/test",
				},
				{
					Nwo:  "@actions/checkout",
					Ref:  "v1",
					Path: ".github/actions/test",
				},
				{
					Nwo:  "test-org-2/test-repo-2/test-action.yml",
					Ref:  "main",
					Path: ".github/actions/test",
				},
			},
			wantErr: false,
			expectedResp: []*ResolveActionsResponse{
				{
					ResolvedAction: &ghactions.ResolvedAction{
						Id:              20,
						Name:            "test-org-1/test-repo-1",
						ResolvedName:    "test-org-1/test-repo-1",
						Ref:             "v1",
						ResolvedRef:     "v1",
						ResolvedSha:     "512asfasfdsg",
						Visibility:      "internal",
						ZipUrl:          "test-zip-url",
						TarUrl:          "test-tar-url",
						ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
					},
				},
				{
					ResolvedAction: &ghactions.ResolvedAction{
						Id:              20,
						Name:            "@actions/checkout",
						ResolvedName:    "@actions/checkout",
						Ref:             "v1",
						ResolvedRef:     "v1",
						ResolvedSha:     "512asfasfdsg",
						Visibility:      "public",
						ZipUrl:          "test-zip-url",
						TarUrl:          "test-tar-url",
						ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
					},
				},
				{
					ResolvedAction: &ghactions.ResolvedAction{
						Id:              20,
						Name:            "test-org-2/test-repo-2/test-action.yml",
						ResolvedName:    "test-org-2/test-repo-2/test-action.yml",
						Ref:             "main",
						ResolvedRef:     "main",
						ResolvedSha:     "512asfasfdsg",
						Visibility:      "private",
						ZipUrl:          "test-zip-url",
						TarUrl:          "test-tar-url",
						ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_INVALID,
					},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			globallyEnabled := &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: true,
			}

			mockActionsFeaturesService := NewMockMonolithFeaturesService(t)
			mockActionsFeaturesService.EXPECT().CheckGlobalFeature(mock.Anything, mock.Anything).Return(globallyEnabled, nil)
			c := NewMockTestClient(nil, nil, nil, mockActionsFeaturesService, nil, nil, nil, nil, nil, nil, nil, nil, tt.setupMocks(), nil, tt.isMultiTenant)

			var ctx = context.Background()
			var err error
			if tt.isMultiTenant {
				ctx, err = ghtenant.ContextWithTenantID(ctx, int64(testTenantID), tt.isMultiTenant)
				require.NoError(t, err)
			}
			resolveActionsResponse, err := c.ResolveActions(ctx, tt.actions, int64(testRunID), testJobID, int64(testRepoID), true, false)

			if tt.wantErr {
				assert.Error(t, err)
				assert.Nil(t, resolveActionsResponse)
			} else {
				assert.Equal(t, len(tt.actions), len(resolveActionsResponse))
				for i, resolvedAction := range resolveActionsResponse {
					if tt.expectedResp[i].Error == nil {
						assert.True(t, reflect.DeepEqual(tt.expectedResp[i].ResolvedAction, resolvedAction.ResolvedAction))
					} else {
						assert.NotNil(t, resolvedAction.Error)
						assert.Equal(t, tt.actions[i].Nwo, resolvedAction.Error.Action.Nwo)
						assert.Equal(t, tt.actions[i].Ref, resolvedAction.Error.Action.Ref)
						assert.Equal(t, tt.expectedResp[i].Error.Err.Error(), resolvedAction.Error.Err.Error())
					}
				}
			}
		})
	}
}

func TestEducationAutogradingSubstitution(t *testing.T) {
	testRepoID := 4234
	testRunID := 100
	testJobID := "test-job"
	testTenantID := 1146

	tests := []struct {
		desc          string
		isMultiTenant bool
		globalRes     *twirpFeatures.CheckGlobalFeatureResponse
		featuresRes   *twirpFeatures.CheckActorsFeatureResponse
		setupMocks    func() *MockResolveActionsService
		actions       []*Action
		expectedResp  []*ResolveActionsResponse
	}{
		{
			desc: "with flag enabled, swaps education/autograding with classroom-resources/autograding",
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			setupMocks: func() *MockResolveActionsService {
				mockResolveActionsAPI := NewMockResolveActionsService(t)
				mockResolveActionsAPI.EXPECT().ResolveActions(mock.Anything, &ghactions.ResolveActionsRequest{
					Actions: []*ghactions.Action{
						{
							Nwo: "classroom-resources/autograding",
							Ref: "v1",
						},
					},
					WorkflowRunId:           int64(testRunID),
					JobId:                   testJobID,
					WorkflowRepoId:          int64(testRepoID),
					ShouldInstrumentRequest: true,
				}).Return(&ghactions.ResolveActionsResponse{
					ResolvedActions: []*ghactions.ResolvedActionContent{
						{
							ResolvedActionContent: &ghactions.ResolvedActionContent_ResolvedAction{
								ResolvedAction: &ghactions.ResolvedAction{},
							},
						},
					},
				}, nil)
				return mockResolveActionsAPI
			},
			actions: []*Action{
				{
					Nwo:  "education/autograding",
					Ref:  "v1",
					Path: "",
				},
			},
		},
		{
			desc: "with flag enabled, does not change unrelated nwos",
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			setupMocks: func() *MockResolveActionsService {
				mockResolveActionsAPI := NewMockResolveActionsService(t)
				mockResolveActionsAPI.EXPECT().ResolveActions(mock.Anything, &ghactions.ResolveActionsRequest{
					Actions: []*ghactions.Action{
						{
							Nwo: "actions/checkout",
							Ref: "v4",
						},
					},
					WorkflowRunId:           int64(testRunID),
					JobId:                   testJobID,
					WorkflowRepoId:          int64(testRepoID),
					ShouldInstrumentRequest: true,
				}).Return(&ghactions.ResolveActionsResponse{
					ResolvedActions: []*ghactions.ResolvedActionContent{
						{
							ResolvedActionContent: &ghactions.ResolvedActionContent_ResolvedAction{
								ResolvedAction: &ghactions.ResolvedAction{},
							},
						},
					},
				}, nil)
				return mockResolveActionsAPI
			},
			actions: []*Action{
				{
					Nwo:  "actions/checkout",
					Ref:  "v4",
					Path: "",
				},
			},
		},
		{
			desc: "with flag enabled and not running on dotcom, does not swap education/autograding with classroom-resources/autograding",
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: true,
					},
				},
			},
			isMultiTenant: true,
			setupMocks: func() *MockResolveActionsService {
				mockResolveActionsAPI := NewMockResolveActionsService(t)
				mockResolveActionsAPI.EXPECT().ResolveActions(mock.Anything, &ghactions.ResolveActionsRequest{
					Actions: []*ghactions.Action{
						{
							Nwo: "education/autograding",
							Ref: "v1",
						},
					},
					WorkflowRunId:           int64(testRunID),
					JobId:                   testJobID,
					WorkflowRepoId:          int64(testRepoID),
					ShouldInstrumentRequest: true,
				}).Return(&ghactions.ResolveActionsResponse{
					ResolvedActions: []*ghactions.ResolvedActionContent{
						{
							ResolvedActionContent: &ghactions.ResolvedActionContent_ResolvedAction{
								ResolvedAction: &ghactions.ResolvedAction{},
							},
						},
					},
				}, nil)
				return mockResolveActionsAPI
			},
			actions: []*Action{
				{
					Nwo:  "education/autograding",
					Ref:  "v1",
					Path: "",
				},
			},
		},
		{
			desc: "with flag disabled, it does not swap education/autograding with classroom-resources/autograding",
			globalRes: &twirpFeatures.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			featuresRes: &twirpFeatures.CheckActorsFeatureResponse{
				Results: []*twirpFeatures.ActorFeatureResult{
					{
						ActorId:   "Repository:1234567",
						IsEnabled: false,
					},
				},
			},
			setupMocks: func() *MockResolveActionsService {
				mockResolveActionsAPI := NewMockResolveActionsService(t)
				mockResolveActionsAPI.EXPECT().ResolveActions(mock.Anything, &ghactions.ResolveActionsRequest{
					Actions: []*ghactions.Action{
						{
							Nwo: "education/autograding",
							Ref: "v1",
						},
					},
					WorkflowRunId:           int64(testRunID),
					JobId:                   testJobID,
					WorkflowRepoId:          int64(testRepoID),
					ShouldInstrumentRequest: true,
				}).Return(&ghactions.ResolveActionsResponse{
					ResolvedActions: []*ghactions.ResolvedActionContent{
						{
							ResolvedActionContent: &ghactions.ResolvedActionContent_ResolvedAction{
								ResolvedAction: &ghactions.ResolvedAction{},
							},
						},
					},
				}, nil)
				return mockResolveActionsAPI
			},
			actions: []*Action{
				{
					Nwo:  "education/autograding",
					Ref:  "v1",
					Path: "",
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockActionsFeaturesService := NewMockMonolithFeaturesService(t)
			mockActionsFeaturesService.EXPECT().CheckGlobalFeature(mock.Anything, mock.Anything).Return(tt.globalRes, nil)
			mockActionsFeaturesService.EXPECT().CheckActorsFeature(mock.Anything, mock.Anything).Return(tt.featuresRes, nil)
			c := NewMockTestClient(nil, nil, nil, mockActionsFeaturesService, nil, nil, nil, nil, nil, nil, nil, nil, tt.setupMocks(), nil, tt.isMultiTenant)
			// Set this so that multitenant cases work as expected instead of thinking the environment is dotcom
			testutils.SetLaunchConfigEnv(t, testutils.EnvPair{
				Key:   "LAUNCH_IS_MULTI_TENANT",
				Value: fmt.Sprint(tt.isMultiTenant),
			})

			var ctx = context.Background()
			var err error
			if tt.isMultiTenant {
				ctx, err = ghtenant.ContextWithTenantID(ctx, int64(testTenantID), tt.isMultiTenant)
				require.NoError(t, err)
			}

			c.ResolveActions(ctx, tt.actions, int64(testRunID), testJobID, int64(testRepoID), true, false)
		})
	}
}

func TestSetUserAgent(t *testing.T) {
	tests := map[string]struct {
		desc                        string
		ctx                         context.Context
		headerExists                bool
		existingHeader              http.Header
		env                         string
		expectedUserAgentValue      string
		expectedExistingHeaderName  string
		expectedExistingHeaderValue string
	}{
		"no-existing-header": {
			desc:                   "adds the user-agent to a new header in the context",
			ctx:                    context.Background(),
			env:                    "testEnv",
			expectedUserAgentValue: "launch/testEnv",
		},
		"existing-header": {
			desc:                        "adds the user-agent to the header already existing in the context",
			ctx:                         context.Background(),
			headerExists:                true,
			existingHeader:              make(http.Header),
			env:                         "testEnv",
			expectedUserAgentValue:      "launch/testEnv",
			expectedExistingHeaderName:  "blah",
			expectedExistingHeaderValue: "foo",
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			c := NewMockTestClient(nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)
			c.env = tt.env

			ctx := tt.ctx

			if tt.headerExists {
				tt.existingHeader.Set(tt.expectedExistingHeaderName, tt.expectedExistingHeaderValue)
				var err error
				ctx, err = twirp.WithHTTPRequestHeaders(ctx, tt.existingHeader)
				require.NoError(t, err)
			}

			ctx, err := c.setUserAgent(ctx)
			require.NoError(t, err)

			header, ok := twirp.HTTPRequestHeaders(ctx)
			assert.True(t, ok)
			assert.Equal(t, tt.expectedUserAgentValue, header.Get("User-Agent"))

			if tt.headerExists {
				assert.Equal(t, tt.expectedExistingHeaderValue, header.Get(tt.expectedExistingHeaderName))
			}
		})
	}
}

func TestGetRepositoryVisibility(t *testing.T) {
	tests := []struct {
		desc               string
		inputRepoID        int64
		expectedVisibility ghactions.RepositoryVisibility
		resErr             error
	}{
		{
			desc:               "returns an error if one is returned from the twirp endpoint",
			inputRepoID:        1,
			expectedVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INVALID,
			resErr:             twirp.NewError(twirp.Internal, "test error"),
		},
		{
			desc:               "returns expected response for valid inputs",
			inputRepoID:        1,
			expectedVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC,
			resErr:             nil,
		},
		{
			desc:               "returns invalid visibility for repo ID of 0",
			inputRepoID:        0,
			expectedVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INVALID,
			resErr:             nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mockReposAPI := &MockReposService{}

			req := &ghactions.GetRepositoryVisibilityRequest{
				RepositoryId: tt.inputRepoID,
			}
			res := &ghactions.GetRepositoryVisibilityResponse{
				Visibility: tt.expectedVisibility,
			}

			if tt.resErr != nil {
				mockReposAPI.On("GetRepositoryVisibility", mock.Anything, req).Return(nil, tt.resErr).Times(1)
			} else {
				if tt.inputRepoID == 0 {
					mockReposAPI.AssertNotCalled(t, "GetRepositoryVisibility")
				} else {
					mockReposAPI.On("GetRepositoryVisibility", mock.Anything, req).Return(res, nil).Times(1)
				}
			}

			c := NewMockTestClient(nil, mockReposAPI, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)

			ctx := context.Background()
			visibility, err := c.GetRepositoryVisibility(ctx, tt.inputRepoID)

			if tt.resErr == nil {
				require.NoError(t, err)
			} else {
				require.Error(t, err)
			}

			require.Equal(t, tt.expectedVisibility, visibility)

			mockReposAPI.AssertExpectations(t)
		})
	}
}

func TestTestGetRepositoryVisibility_Cache(t *testing.T) {
	mockReposAPI := &MockReposService{}

	req := &ghactions.GetRepositoryVisibilityRequest{
		RepositoryId: 1,
	}
	res := &ghactions.GetRepositoryVisibilityResponse{
		Visibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC,
	}

	// we expect to read the second request from the cache so the API should only be called oncee
	mockReposAPI.On("GetRepositoryVisibility", mock.Anything, req).Return(res, nil).Times(1)
	c := NewMockTestClient(nil, mockReposAPI, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false)

	_, err := c.GetRepositoryVisibility(context.TODO(), 1)
	require.NoError(t, err)

	_, err = c.GetRepositoryVisibility(context.TODO(), 1)
	require.NoError(t, err)

	mockReposAPI.AssertExpectations(t)
}

func getInputActions() []*Action {
	inputActions := make([]*Action, 0)
	for i := 1; i <= 5; i++ {
		for j := 1; j <= 5; j++ {
			inputActions = append(inputActions, &Action{
				Nwo: fmt.Sprintf("test-org-%d/test-repo-%d", i, j),
				Ref: fmt.Sprintf("v%d", j),
			})
		}
	}
	return inputActions
}

func getInputActionsForTwirpCall() []*ghactions.Action {
	inputActions := make([]*ghactions.Action, 0)
	for i := 1; i <= 5; i++ {
		for j := 1; j <= 5; j++ {
			inputActions = append(inputActions, &ghactions.Action{
				Nwo: fmt.Sprintf("test-org-%d/test-repo-%d", i, j),
				Ref: fmt.Sprintf("v%d", j),
			})
		}
	}
	return inputActions
}

func getResolvedActionsTwirpResponse() *ghactions.ResolveActionsResponse {
	resolvedActions := make([]*ghactions.ResolvedActionContent, 0)
	for i := 1; i <= 5; i++ {
		for j := 1; j <= 5; j++ {
			if j == 4 {
				resolvedActions = append(resolvedActions, &ghactions.ResolvedActionContent{
					ResolvedActionContent: &ghactions.ResolvedActionContent_Error{
						Error: &ghactions.ResolveActionError{
							ErrorCode:    400,
							ErrorMessage: fmt.Sprintf("Unable to resolve action test-org-%d/test-repo-%d", i, j),
						},
					},
				})
				continue
			}
			resolvedActions = append(resolvedActions, &ghactions.ResolvedActionContent{
				ResolvedActionContent: &ghactions.ResolvedActionContent_ResolvedAction{
					ResolvedAction: &ghactions.ResolvedAction{
						Id:           int64(i*10 + j),
						Name:         fmt.Sprintf("test-org-%d/test-repo-%d", i, j),
						ResolvedName: fmt.Sprintf("test-org-%d/test-repo-%d", i, j),
						Ref:          fmt.Sprintf("v%d", j),
						ResolvedRef:  fmt.Sprintf("v%d", j),
						ResolvedSha:  fmt.Sprintf("testSHA-%d-%d", i, j),
						Visibility:   "public",
						ZipUrl:       fmt.Sprintf("test-zip-url-%d-%d", i, j),
						TarUrl:       fmt.Sprintf("test-tar-url-%d-%d", i, j),
					},
				},
			})
		}
	}
	return &ghactions.ResolveActionsResponse{
		ResolvedActions: resolvedActions,
	}
}

func getResolvedActionsExpectedResponse() []*ResolveActionsResponse {
	resolvedActions := make([]*ResolveActionsResponse, 0)
	for i := 1; i <= 5; i++ {
		for j := 1; j <= 5; j++ {
			if j == 4 {
				resolvedActions = append(resolvedActions, &ResolveActionsResponse{
					Error: &ResolveActionsErr{
						Action: &Action{
							Nwo: fmt.Sprintf("test-org-%d/test-repo-%d", i, j),
							Ref: fmt.Sprintf("v%d", j),
						},
						Err: errors.New(fmt.Sprintf("Unable to resolve action test-org-%d/test-repo-%d", i, j)),
					},
				})
				continue
			}
			resolvedActions = append(resolvedActions, &ResolveActionsResponse{
				ResolvedAction: &ghactions.ResolvedAction{
					Id:           int64(i*10 + j),
					Name:         fmt.Sprintf("test-org-%d/test-repo-%d", i, j),
					ResolvedName: fmt.Sprintf("test-org-%d/test-repo-%d", i, j),
					Ref:          fmt.Sprintf("v%d", j),
					ResolvedRef:  fmt.Sprintf("v%d", j),
					ResolvedSha:  fmt.Sprintf("testSHA-%d-%d", i, j),
					Visibility:   "public",
					ZipUrl:       fmt.Sprintf("test-zip-url-%d-%d", i, j),
					TarUrl:       fmt.Sprintf("test-tar-url-%d-%d", i, j),
				},
			})
		}
	}
	return resolvedActions
}

func makeActor(globalID types.GlobalID, name string, private bool) (*ghactions.Actor, error) {
	actorType := ghactions.Actor_TYPE_INVALID
	databaseID := int64(0)
	var err error

	if !globalID.IsZeroValue() {
		var actorTypeHint string
		actorTypeHint, databaseID, err = globalID.Decode()
		if err != nil {
			return nil, err
		}

		// Format the type hint consistent with enum values defined in the Actor_Type pseudo-enum.
		actorTypeEnumMember := strings.ToUpper(fmt.Sprintf("TYPE_%s", actorTypeHint))
		actorTypeCandidate, found := ghactions.Actor_Type_value[actorTypeEnumMember]
		if found {
			actorType = ghactions.Actor_Type(actorTypeCandidate)
		}
	}

	actor := ghactions.Actor{
		Type:      actorType,
		Id:        databaseID,
		IdString:  name,
		PlanName:  "fake_plan",
		IsPrivate: &wrapperspb.BoolValue{Value: private},
		CreatedAt: fixedCreatedAtDate,
		GlobalId:  &ghactions.Identity{GlobalId: globalID.String()},
		IsHammy:   &wrapperspb.BoolValue{Value: false},
	}
	return &actor, nil
}

func makeFindRepositoriesResponse(repo *ghactions.Repository, notFoundMsg string) *ghactions.FindRepositoriesByNameResponse {
	repos := []*ghactions.Repository{}
	if repo != nil {
		repos = append(repos, repo)
	}

	return &ghactions.FindRepositoriesByNameResponse{
		Repositories:                     repos,
		RepositoriesNotFoundErrorMessage: notFoundMsg,
	}
}

func formatNWO(owner, repo *ghactions.Actor) string {
	fallback := "MISSING"
	ownerName := fallback
	if owner != nil {
		ownerName = owner.IdString
	}

	repoName := fallback
	if repo != nil {
		repoName = repo.IdString
	}

	return fmt.Sprintf("%s/%s", ownerName, repoName)
}

func toRepository(owner, repo *ghactions.Actor, public bool) *ghactions.Repository {
	if owner == nil || repo == nil {
		return nil
	}

	if owner.Type != ghactions.Actor_TYPE_ORGANIZATION && owner.Type != ghactions.Actor_TYPE_USER {
		return nil
	}

	if repo.Type != ghactions.Actor_TYPE_REPOSITORY {
		return nil
	}

	visibility := ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE
	if public {
		visibility = ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC
	}

	return &ghactions.Repository{
		Id:            repo.Id,
		Name:          repo.IdString,
		GlobalRelayId: repo.GlobalId.GlobalId,
		OwnerLogin:    owner.IdString,
		Visibility:    visibility,
	}
}

func toEntity(a *ghactions.Actor) *Entity {
	if a == nil {
		return nil
	}

	simplfiedTypeName, _ := strings.CutPrefix(a.Type.String(), "TYPE_")
	simplfiedTypeName = titleCaseFormatter.String(simplfiedTypeName)

	return &Entity{
		ID:        a.Id,
		GlobalID:  types.GlobalID(a.GlobalId.GlobalId),
		Name:      a.IdString,
		Type:      simplfiedTypeName,
		CreatedAt: a.CreatedAt.AsTime(),
	}
}
