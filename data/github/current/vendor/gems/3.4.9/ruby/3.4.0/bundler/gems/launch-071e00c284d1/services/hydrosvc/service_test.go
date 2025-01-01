package hydrosvc

import (
	"context"
	"fmt"
	"strings"
	"testing"

	hydroschemas "github.com/github/hydro-client-go/v3/generated/hydro/schemas/hydro/v1"
	"github.com/github/hydro-client-go/v3/pkg/hydro"
	"github.com/golang/protobuf/proto"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"google.golang.org/protobuf/runtime/protoiface"
	emptypb "google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	kredzpb "github.com/github/kredz/services/protobuf/credz"

	"github.com/github/launch/clients/ghtwirp"
	ghschemasV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	ghschemas "github.com/github/launch/hydro/schemas/github/v1"
	ghentities "github.com/github/launch/hydro/schemas/github/v1/entities"
	"github.com/github/launch/services/deploy/adminevents"
	"github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/pbtypes"
	launchtypes "github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

const (
	nextIDPrefix = "next_"

	repositoryDatabaseID = 123
	repositoryID         = "test-repository-id"
	userID               = "test-user-id"
	userDatabaseID       = 123
	orgDatabaseID        = 1234
	orgID                = "test-org-id"
	orgLogin             = "test-org"
	userLogin            = "user-login"
	workflowID           = 123
	workflowFilePath     = ".github/workflows/test.yml"
	branchRef            = "refs/heads/test-branch"
	environment          = "production"
	workflowDisabledType = "disabled"
	installationID       = 321
	ownerDatabaseID      = 234
)

func TestHandleHydroMessage(t *testing.T) {
	type testCase struct {
		desc                  string
		isExperimentEnabled   bool
		hydroMessage          proto.Message
		topic                 string
		owner                 kredzpb.IsCredentialOwnerOwner
		repoGlobalID          string
		errExpected           bool
		eventType             string
		expectedDeployerCalls int
		workflowType          string
	}

	tests := []testCase{
		{
			desc: "properly calls deployer for Repository Deleted events",
			hydroMessage: &ghschemas.RepositoryDeleted{
				DeletedRepository: &ghentities.Repository{
					GlobalRelayId: repositoryID,
					NextGlobalId:  nextIDFromGlobalID(repositoryID),
				},
			},
			topic:        RepositoryDeletedTopic,
			repoGlobalID: repositoryID,
			owner: &kredzpb.CredentialOwner_Repository{
				Repository: &kredzpb.Repository{
					GlobalId: nextIDFromGlobalID(repositoryID),
				},
			},
			eventType:             adminevents.RepositoryDeleted,
			expectedDeployerCalls: 1,
		},
		{
			desc: "properly calls deployer for Repository Transfer events if transfer is immediate",
			hydroMessage: &ghschemas.RepositoryTransfer{
				Repository: &ghentities.Repository{
					GlobalRelayId: repositoryID,
				},
				Criteria: ghschemas.RepositoryTransfer_IMMEDIATE,
			},
			eventType:             adminevents.RepositoryTransferred,
			topic:                 RepositoryTransferTopic,
			repoGlobalID:          repositoryID,
			expectedDeployerCalls: 1,
		},
		{
			desc: "properly calls deployer for Repository Transfer events if requested transfer is responded to",
			hydroMessage: &ghschemas.RepositoryTransfer{
				Repository: &ghentities.Repository{
					GlobalRelayId: repositoryID,
				},
				Criteria: ghschemas.RepositoryTransfer_REQUEST,
				State:    ghschemas.RepositoryTransfer_RESPONDED,
			},
			eventType:             adminevents.RepositoryTransferred,
			topic:                 RepositoryTransferTopic,
			repoGlobalID:          repositoryID,
			expectedDeployerCalls: 1,
		},
		{
			desc: "does not call deployer when transfer is not immediate and not responded to",
			hydroMessage: &ghschemas.RepositoryTransfer{
				Repository: &ghentities.Repository{
					GlobalRelayId: repositoryID,
				},
				Criteria: ghschemas.RepositoryTransfer_REQUEST,
				State:    ghschemas.RepositoryTransfer_REQUESTED,
			},
			topic:        RepositoryTransferTopic,
			repoGlobalID: nextIDFromGlobalID(repositoryID),
		},
		{
			desc: "properly calls deployer for repository archived status changed events if the repo is archived",
			hydroMessage: &ghschemas.RepositoryArchivedStatusChanged{

				RepositoryId:       uint64(42),
				RepositoryGlobalId: testutils.EncodeGlobalID("Repository", 42),
				IsArchived:         true,
			},
			eventType:             adminevents.RepositoryArchived,
			topic:                 RepositoryArchivedStatusChangedTopic,
			repoGlobalID:          testutils.EncodeGlobalID("Repository", 42),
			expectedDeployerCalls: 1,
		},
		{
			desc: "does not call deployer for repository archived status changed events if the repo is un-archived",
			hydroMessage: &ghschemas.RepositoryArchivedStatusChanged{
				RepositoryId:       uint64(42),
				RepositoryGlobalId: testutils.EncodeGlobalID("Repository", 42),
				IsArchived:         false,
			},
			topic:                 RepositoryArchivedStatusChangedTopic,
			repoGlobalID:          testutils.EncodeGlobalID("Repository", 42),
			expectedDeployerCalls: 0,
		},
		{
			desc: "does not call deployer for repository archived status changed events if the repository global id is not set",
			hydroMessage: &ghschemas.RepositoryArchivedStatusChanged{
				RepositoryId:       uint64(42),
				RepositoryGlobalId: "",
				IsArchived:         true,
			},
			eventType:             adminevents.RepositoryArchived,
			topic:                 RepositoryArchivedStatusChangedTopic,
			repoGlobalID:          testutils.EncodeGlobalID("Repository", 42),
			expectedDeployerCalls: 0,
		},
		{
			desc: "returns error for invalid topic",
			hydroMessage: &ghschemas.UserDestroy{
				User: &ghentities.User{
					Id:            2,
					Type:          ghentities.User_ORGANIZATION,
					Login:         userLogin,
					GlobalRelayId: orgID,
				},
			},
			topic:       "invalid-topic",
			errExpected: true,
		},
		{
			desc: "returns error for invalid topic with next global ID",
			hydroMessage: &ghschemas.UserDestroy{
				User: &ghentities.User{
					Id:           2,
					Type:         ghentities.User_ORGANIZATION,
					Login:        userLogin,
					NextGlobalId: nextIDFromGlobalID(orgID),
				},
			},
			topic:       "invalid-topic",
			errExpected: true,
		},
		{
			desc:  "properly calls deployer for WorkflowStateChange events if a workflow is active",
			topic: WorkflowStateChangeTopic,
			hydroMessage: &ghschemasV0.WorkflowStateChange{
				WorkflowId:       workflowID,
				WorkflowState:    ghschemasV0.WorkflowStateChange_ACTIVE,
				WorkflowFilePath: workflowFilePath,
				BranchRef:        branchRef,
				InstallationId:   installationID,
				Environment:      environment,
				Actor: &ghentities.User{
					GlobalRelayId: userID,
				},
				Repository: &ghentities.Repository{
					GlobalRelayId: repositoryID,
					OwnerId:       wrapperspb.UInt32(ownerDatabaseID),
				},
			},
			expectedDeployerCalls: 1,
			workflowType:          "active",
		},
		{
			desc:  "properly calls deployer for WorkflowStateChange events if a workflow is not active",
			topic: WorkflowStateChangeTopic,
			hydroMessage: &ghschemasV0.WorkflowStateChange{
				WorkflowId:       workflowID,
				WorkflowState:    ghschemasV0.WorkflowStateChange_DISABLED_INACTIVITY,
				WorkflowFilePath: workflowFilePath,
				BranchRef:        branchRef,
				InstallationId:   installationID,
				Environment:      environment,
				Actor:            nil,
				Repository: &ghentities.Repository{
					GlobalRelayId: repositoryID,
					NextGlobalId:  nextIDFromGlobalID(repositoryID),
				},
			},
			expectedDeployerCalls: 1,
			workflowType:          workflowDisabledType,
		},
		{
			desc: "properly calls deployer for user is marked as spammy",
			hydroMessage: &ghschemas.AbuseClassification{
				Account: &ghentities.User{
					Id:            userDatabaseID,
					GlobalRelayId: userID,
					NextGlobalId:  nextIDFromGlobalID(userID),
					Spammy:        true,
					Login:         userLogin,
				},
				CurrentSpammyReason: &wrapperspb.StringValue{Value: "spammy user"},
			},
			topic:                 AbuseClassification,
			expectedDeployerCalls: 1,
		},
		{
			desc: "properly calls deployer for user action invocation blocked",
			hydroMessage: &ghschemasV0.InvocationBlocked{
				Account: &ghentities.User{
					Id:            userDatabaseID,
					GlobalRelayId: userID,
					NextGlobalId:  nextIDFromGlobalID(userID),
					Login:         userLogin,
				},
			},
			topic:                 InvocationBlockedTopic,
			expectedDeployerCalls: 1,
		},
		{
			desc: "properly calls deployer for user action invocation unblocked",
			hydroMessage: &ghschemasV0.InvocationUnblocked{
				Account: &ghentities.User{
					Id:            userDatabaseID,
					GlobalRelayId: userID,
					NextGlobalId:  nextIDFromGlobalID(userID),
					Login:         userLogin,
				},
			},
			topic:                 InvocationUnblockedTopic,
			expectedDeployerCalls: 1,
		},
		{
			desc: "does not call deployer when invocation blocked message has nil account",
			hydroMessage: &ghschemasV0.InvocationBlocked{
				Account: nil,
			},
			topic:                 InvocationBlockedTopic,
			expectedDeployerCalls: 0,
		},
		{
			desc: "does not call deployer when absue classification message has nil account",
			hydroMessage: &ghschemasV0.InvocationBlocked{
				Account: nil,
			},
			topic:                 AbuseClassification,
			expectedDeployerCalls: 0,
		},
		{
			desc: "properly calls deployer for user is unmarked as spammy",
			hydroMessage: &ghschemas.AbuseClassification{
				Account: &ghentities.User{
					Id:            userDatabaseID,
					GlobalRelayId: userID,
					NextGlobalId:  nextIDFromGlobalID(userID),
					Spammy:        false,
					Login:         userLogin,
				},
				Origin: ghentities.AbuseClassificationOrigin_STAFFTOOLS,
			},
			topic:                 AbuseClassification,
			expectedDeployerCalls: 1,
		},
		{
			desc:  "properly calls deployer for UserDestroy events to report admin event to actions",
			topic: UserDestroyTopic,
			hydroMessage: &ghschemas.UserDestroy{
				User: &ghentities.User{
					Id:            userDatabaseID,
					Type:          ghentities.User_USER,
					Login:         userLogin,
					GlobalRelayId: userID,
					NextGlobalId:  nextIDFromGlobalID(userID),
				},
			},
			expectedDeployerCalls: 1,
		},
		{
			desc: "properly calls deployer for Repository Restored events",
			hydroMessage: &ghschemas.RepositoryRestored{
				RestoredRepository: &ghentities.Repository{
					Id:            repositoryDatabaseID,
					GlobalRelayId: repositoryID,
					NextGlobalId:  nextIDFromGlobalID(repositoryID),
				},
			},
			topic:        RepositoryRestoredTopic,
			repoGlobalID: repositoryID,
			owner: &kredzpb.CredentialOwner_Repository{
				Repository: &kredzpb.Repository{
					GlobalId: nextIDFromGlobalID(repositoryID),
				},
			},
			eventType:             adminevents.BillingOwnerRestored,
			expectedDeployerCalls: 1,
		},
		{
			desc: "not calls deployer for Repository Restored events if the owner is spammy",
			hydroMessage: &ghschemas.RepositoryRestored{
				RestoredRepository: &ghentities.Repository{
					Id:            repositoryDatabaseID,
					GlobalRelayId: repositoryID,
					NextGlobalId:  nextIDFromGlobalID(repositoryID),
				},
			},
			topic:        RepositoryRestoredTopic,
			repoGlobalID: repositoryID,
			owner: &kredzpb.CredentialOwner_Repository{
				Repository: &kredzpb.Repository{
					GlobalId: nextIDFromGlobalID(repositoryID),
				},
			},
			eventType:             adminevents.BillingOwnerRestored,
			expectedDeployerCalls: 0,
		},
		{
			desc: "properly calls deployer for Org Restored events",
			hydroMessage: &ghschemas.OrganizationRestore{
				Organization: &ghentities.Organization{
					Id:            orgDatabaseID,
					GlobalRelayId: orgID,
				},
			},
			topic:                 OrganizationRestoreTopic,
			eventType:             adminevents.BillingOwnerRestored,
			expectedDeployerCalls: 1,
		},
		{
			desc: "not calls deployer for Org Restored events if the owner is spammy",
			hydroMessage: &ghschemas.OrganizationRestore{
				Organization: &ghentities.Organization{
					Id:            orgDatabaseID,
					GlobalRelayId: orgID,
					Spammy:        true,
				},
			},
			topic:                 OrganizationRestoreTopic,
			eventType:             adminevents.BillingOwnerRestored,
			expectedDeployerCalls: 0,
		},
	}

	testsWithExperiment := make([]testCase, 0, len(tests))
	for _, tt := range tests {
		test := tt
		test.isExperimentEnabled = true
		test.desc = fmt.Sprintf("%s with experiment enabled", test.desc)
		testsWithExperiment = append(testsWithExperiment, test)
	}

	for _, tt := range append(tests, testsWithExperiment...) {
		t.Run(tt.desc, func(t *testing.T) {
			encoder := hydro.NewDefaultEncoder(hydro.CP1IAD)
			value, err := encoder.Encode(tt.hydroMessage)
			require.NoError(t, err)

			msg := hydro.Message{
				Topic: tt.topic,
				Value: value,
			}

			mockTwirpClient := &ghtwirp.MockClient{}
			mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
				return types.NewGlobalID(ctx, nextIDFromGlobalID(globalID))
			}, nil)

			mockDeployerTwirpClient := &deploy.MockLaunchDeploymentService{}

			if tt.expectedDeployerCalls > 0 && tt.topic != WorkflowStateChangeTopic && tt.topic != AbuseClassification && tt.topic != UserDestroyTopic && tt.topic != InvocationBlockedTopic && tt.topic != InvocationUnblockedTopic && tt.topic != RepositoryRestoredTopic && tt.topic != OrganizationRestoreTopic {
				workflowCancelReq := &deploy.WorkflowCancelAllRequest{
					RepositoryId: &pbtypes.Identity{
						GlobalId: nextIDFromGlobalID(tt.repoGlobalID),
					},
					EventType: tt.eventType,
				}
				mockDeployerTwirpClient.On("WorkflowCancelAll", mock.Anything, workflowCancelReq).Return(&deploy.WorkflowCancelAllResponse{}, nil)
			} else if tt.expectedDeployerCalls > 0 && tt.topic == WorkflowStateChangeTopic {
				if tt.workflowType == workflowDisabledType {
					// mock disabling a worflow
					disableReq := &launchtypes.DisableScheduledWorkflowRequest{
						Environment: environment,
						RepositoryNodeId: &pbtypes.Identity{
							GlobalId: nextIDFromGlobalID(repositoryID),
						},
						WorkflowFilePath: workflowFilePath,
					}

					mockDeployerTwirpClient.On("DisableScheduledWorkflow", mock.Anything, disableReq).Return(&emptypb.Empty{}, nil)

				} else {
					// mock enabling a worklfow
					synchronizeReq := &launchtypes.SynchronizeScheduledWorkflowsRequest{
						Ref: branchRef,
						RepositoryNodeId: &pbtypes.Identity{
							GlobalId: nextIDFromGlobalID(repositoryID),
						},
						InstallationId: installationID,
						ActorNodeId: &pbtypes.Identity{
							GlobalId: nextIDFromGlobalID(userID),
						},
						OwnerDatabaseId: ownerDatabaseID,
					}

					mockDeployerTwirpClient.On("SynchronizeScheduledWorkflows", mock.Anything, synchronizeReq).Return(&emptypb.Empty{}, nil)

				}
			} else if tt.expectedDeployerCalls > 0 && tt.topic == AbuseClassification {
				hydroMessageValue := deserializeAbuseClassificationHydroMessage(tt.hydroMessage)

				if hydroMessageValue.GetAccount().GetSpammy() {
					ownerReposReq := &deploy.ReportAdminEventForOwnerReposRequest{
						AdminEvent:    adminevents.OwnerMarkedAsSpammy,
						OwnerId:       userDatabaseID,
						OwnerGlobalId: nextIDFromGlobalID(userID),
						OwnerName:     userLogin,
						Data:          "spammy user",
					}

					billingOwnerReq := &deploy.ReportAdminEventForBillingOwnerRequest{
						AdminEvent:    adminevents.OwnerMarkedAsSpammy,
						OwnerId:       userDatabaseID,
						OwnerGlobalId: nextIDFromGlobalID(userID),
						OwnerName:     userLogin,
						Data:          "spammy user",
					}

					workflowCancelReq := &deploy.WorkflowCancelAllForNonOwnerReposRequest{
						ActorName: userLogin,
						ActorId:   int64(userDatabaseID),
						ActorGlobalId: &pbtypes.Identity{
							GlobalId: nextIDFromGlobalID(userID),
						},
						Data: "spammy user",
					}

					workflowCancelResp := &deploy.WorkflowCancelAllForNonOwnerReposResponse{
						WorkflowCount: int64(1),
					}

					mockDeployerTwirpClient.On("ReportAdminEventForOwnerRepos", mock.Anything, ownerReposReq).Return(&emptypb.Empty{}, nil)
					mockDeployerTwirpClient.On("ReportAdminEventForBillingOwner", mock.Anything, billingOwnerReq).Return(&emptypb.Empty{}, nil)
					mockDeployerTwirpClient.On("WorkflowCancelAllForNonOwnerRepos", mock.Anything, workflowCancelReq).Return(workflowCancelResp, nil)

				} else if hydroMessageValue.GetPreviousClassification() == ghentities.AbuseClassificationState_SPAMMY {
					// not spammy, from stafftools
					billingOwnerReq := &deploy.ReportAdminEventForBillingOwnerRequest{
						AdminEvent:    adminevents.OwnerUnmarkedAsSpammy,
						OwnerId:       userDatabaseID,
						OwnerGlobalId: userID,
						OwnerName:     userLogin,
					}

					mockDeployerTwirpClient.On("ReportAdminEventForBillingOwner", mock.Anything, billingOwnerReq).Return(&emptypb.Empty{}, nil)
				}
			} else if tt.expectedDeployerCalls > 0 && tt.topic == InvocationBlockedTopic {
				// mock report admin event
				ownerReposReq := &deploy.ReportAdminEventForOwnerReposRequest{
					AdminEvent:    adminevents.OwnerInvocationBlocked,
					OwnerId:       userDatabaseID,
					OwnerGlobalId: nextIDFromGlobalID(userID),
					OwnerName:     userLogin,
					Data:          "action invocation blocked",
				}

				billingOwnerReq := &deploy.ReportAdminEventForBillingOwnerRequest{
					AdminEvent:    adminevents.OwnerInvocationBlocked,
					OwnerId:       userDatabaseID,
					OwnerGlobalId: nextIDFromGlobalID(userID),
					OwnerName:     userLogin,
				}

				workflowCancelReq := &deploy.WorkflowCancelAllForNonOwnerReposRequest{
					ActorName: userLogin,
					ActorId:   int64(userDatabaseID),
					ActorGlobalId: &pbtypes.Identity{
						GlobalId: nextIDFromGlobalID(userID),
					},
					Data: "action invocation blocked",
				}

				workflowCancelResp := &deploy.WorkflowCancelAllForNonOwnerReposResponse{
					WorkflowCount: int64(1),
				}

				mockDeployerTwirpClient.On("ReportAdminEventForOwnerRepos", mock.Anything, ownerReposReq).Return(&emptypb.Empty{}, nil)
				mockDeployerTwirpClient.On("ReportAdminEventForBillingOwner", mock.Anything, billingOwnerReq).Return(&emptypb.Empty{}, nil)
				mockDeployerTwirpClient.On("WorkflowCancelAllForNonOwnerRepos", mock.Anything, workflowCancelReq).Return(workflowCancelResp, nil)

			} else if tt.expectedDeployerCalls > 0 && tt.topic == InvocationUnblockedTopic {
				billingOwnerReq := &deploy.ReportAdminEventForBillingOwnerRequest{
					AdminEvent:    adminevents.OwnerInvocationUnblocked,
					OwnerId:       userDatabaseID,
					OwnerGlobalId: nextIDFromGlobalID(userID),
					OwnerName:     userLogin,
				}

				mockDeployerTwirpClient.On("ReportAdminEventForBillingOwner", mock.Anything, billingOwnerReq).Return(&emptypb.Empty{}, nil)

			} else if tt.expectedDeployerCalls > 0 && tt.topic == UserDestroyTopic {
				billingOwnerReq := &deploy.ReportAdminEventForBillingOwnerRequest{
					AdminEvent:    adminevents.BillingOwnerDeleted,
					OwnerId:       userDatabaseID,
					OwnerGlobalId: nextIDFromGlobalID(userID),
					OwnerName:     userLogin,
				}

				workflowCancelReq := &deploy.WorkflowCancelAllForNonOwnerReposRequest{
					ActorName: userLogin,
					ActorId:   int64(userDatabaseID),
					ActorGlobalId: &pbtypes.Identity{
						GlobalId: nextIDFromGlobalID(userID),
					},
					Data: "BillingOwnerDeleted",
				}

				workflowCancelResp := &deploy.WorkflowCancelAllForNonOwnerReposResponse{
					WorkflowCount: int64(1),
				}

				mockDeployerTwirpClient.On("ReportAdminEventForBillingOwner", mock.Anything, billingOwnerReq).Return(&emptypb.Empty{}, nil)
				mockDeployerTwirpClient.On("WorkflowCancelAllForNonOwnerRepos", mock.Anything, workflowCancelReq).Return(workflowCancelResp, nil)

			} else if tt.expectedDeployerCalls > 0 && tt.topic == RepositoryRestoredTopic {
				// mock twirp client
				mockTwirpClient.On("GetBillingDetails", mock.Anything, types.GlobalID(nextIDFromGlobalID(repositoryID))).Return(&ghtwirp.WorkflowBillingDetails{
					IsActionsUsageAllowed: true,
					IsOwnerSpammy:         false,
				}, nil)
				mockTwirpClient.On("GetRepositoryOwners", mock.Anything, int64(repositoryDatabaseID)).Return(&ghtwirp.RepositoryOwners{
					Owner: ghtwirp.Entity{
						ID:       int64(userDatabaseID),
						GlobalID: types.GlobalID(nextIDFromGlobalID(userID)),
						Name:     userLogin,
					},
				}, nil)
				// mock report admin event
				billingOwnerReq := &deploy.ReportAdminEventForBillingOwnerRequest{
					AdminEvent:    adminevents.BillingOwnerRestored,
					OwnerId:       userDatabaseID,
					OwnerGlobalId: nextIDFromGlobalID(userID),
					OwnerName:     userLogin,
				}

				mockDeployerTwirpClient.On("ReportAdminEventForBillingOwner", mock.Anything, billingOwnerReq).Return(&emptypb.Empty{}, nil)

			} else if tt.expectedDeployerCalls == 0 && tt.topic == RepositoryRestoredTopic {
				// mock twirp client
				mockTwirpClient.On("GetBillingDetails", mock.Anything, types.GlobalID(nextIDFromGlobalID(repositoryID))).Return(&ghtwirp.WorkflowBillingDetails{
					IsActionsUsageAllowed: true,
					IsOwnerSpammy:         true,
				}, nil)
			} else if tt.expectedDeployerCalls > 0 && tt.topic == OrganizationRestoreTopic {
				// mock twirp client
				mockTwirpClient.On("GetOrganizationOwner", mock.Anything, int64(orgDatabaseID)).Return(&ghtwirp.OrganizationOwner{
					Organization: ghtwirp.Entity{
						ID:       int64(orgDatabaseID),
						GlobalID: types.GlobalID(orgID),
						Name:     orgLogin,
					},
				}, nil)
				// mock report admin event
				billingOwnerReq := &deploy.ReportAdminEventForBillingOwnerRequest{
					AdminEvent:    adminevents.BillingOwnerRestored,
					OwnerId:       int64(orgDatabaseID),
					OwnerGlobalId: orgID,
					OwnerName:     orgLogin,
				}

				mockDeployerTwirpClient.On("ReportAdminEventForBillingOwner", mock.Anything, billingOwnerReq).Return(&emptypb.Empty{}, nil)
			}

			svc := NewTestService(mockTwirpClient, mockDeployerTwirpClient)
			err = svc.handleHydroMessage(context.Background(), msg)
			if tt.errExpected {
				assert.Error(t, err)
			} else {
				require.NoError(t, err)
			}

			mockDeployerTwirpClient.AssertExpectations(t)

			if tt.topic == WorkflowStateChangeTopic {
				if tt.workflowType == workflowDisabledType {
					mockDeployerTwirpClient.AssertNumberOfCalls(t, "DisableScheduledWorkflow", tt.expectedDeployerCalls)
				} else {
					mockDeployerTwirpClient.AssertNumberOfCalls(t, "SynchronizeScheduledWorkflows", tt.expectedDeployerCalls)
				}
			} else if tt.topic == AbuseClassification {
				hydroMessageValue := deserializeAbuseClassificationHydroMessage(tt.hydroMessage)
				if hydroMessageValue.GetAccount().GetSpammy() {
					mockDeployerTwirpClient.AssertNumberOfCalls(t, "ReportAdminEventForOwnerRepos", tt.expectedDeployerCalls)
					mockDeployerTwirpClient.AssertNumberOfCalls(t, "ReportAdminEventForBillingOwner", tt.expectedDeployerCalls)
					mockDeployerTwirpClient.AssertNumberOfCalls(t, "WorkflowCancelAllForNonOwnerRepos", tt.expectedDeployerCalls)
				} else if hydroMessageValue.GetPreviousClassification() == ghentities.AbuseClassificationState_SPAMMY {
					mockTwirpClient.AssertNumberOfCalls(t, "ReportAdminEventForBillingOwner", tt.expectedDeployerCalls)
					mockTwirpClient.AssertNotCalled(t, "ReportAdminEventForOwnerRepos")
				} else {
					mockDeployerTwirpClient.AssertNotCalled(t, "ReportAdminEventForBillingOwner", tt.expectedDeployerCalls)
					mockDeployerTwirpClient.AssertNotCalled(t, "ReportAdminEventForOwnerRepos")
				}
			} else if tt.topic == InvocationBlockedTopic {
				mockDeployerTwirpClient.AssertNumberOfCalls(t, "ReportAdminEventForOwnerRepos", tt.expectedDeployerCalls)
				mockDeployerTwirpClient.AssertNumberOfCalls(t, "ReportAdminEventForBillingOwner", tt.expectedDeployerCalls)
				mockDeployerTwirpClient.AssertNumberOfCalls(t, "WorkflowCancelAllForNonOwnerRepos", tt.expectedDeployerCalls)
			} else if tt.topic == InvocationUnblockedTopic {
				mockDeployerTwirpClient.AssertNumberOfCalls(t, "ReportAdminEventForBillingOwner", tt.expectedDeployerCalls)
			} else if tt.topic == UserDestroyTopic {
				mockDeployerTwirpClient.AssertNumberOfCalls(t, "ReportAdminEventForBillingOwner", tt.expectedDeployerCalls)
				mockDeployerTwirpClient.AssertNumberOfCalls(t, "WorkflowCancelAllForNonOwnerRepos", tt.expectedDeployerCalls)
			} else if tt.topic == RepositoryRestoredTopic {
				mockDeployerTwirpClient.AssertNumberOfCalls(t, "ReportAdminEventForBillingOwner", tt.expectedDeployerCalls)
			} else if tt.topic == OrganizationRestoreTopic {
				mockDeployerTwirpClient.AssertNumberOfCalls(t, "ReportAdminEventForBillingOwner", tt.expectedDeployerCalls)
			} else {
				mockDeployerTwirpClient.AssertNumberOfCalls(t, "WorkflowCancelAll", tt.expectedDeployerCalls)
			}
		})
	}
}

func deserializeAbuseClassificationHydroMessage(hydroMessage protoiface.MessageV1) ghschemas.AbuseClassification {
	encoder := hydro.NewDefaultEncoder(hydro.CP1IAD)
	hydroBytes, _ := encoder.Encode(hydroMessage)
	var envelope hydroschemas.Envelope
	proto.Unmarshal(hydroBytes, &envelope)

	var hydroMessageValue ghschemas.AbuseClassification
	proto.Unmarshal(envelope.Message, &hydroMessageValue)
	return hydroMessageValue
}

func nextIDFromGlobalID(globalID string) string {
	if strings.HasPrefix(globalID, nextIDPrefix) {
		// already a next id, return original argument
		return globalID
	}
	return fmt.Sprintf("%s%s", nextIDPrefix, globalID)
}
