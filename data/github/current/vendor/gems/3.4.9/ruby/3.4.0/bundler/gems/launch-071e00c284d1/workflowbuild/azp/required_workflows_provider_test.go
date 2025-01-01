package azp

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"

	ghactions "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/utils/requiredworkflowutils"

	authzpb "github.com/github/authzd/pkg/proto"
	"github.com/github/spokes-proto/gen/go/v1/objects"

	stypes "github.com/github/spokes-proto/gen/go/v1/types"

	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/spokesd"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
)

func TestGetRequiredWorkflowFiles(t *testing.T) {
	invokingRepoID := int64(1234)
	invokingActorID := int64(5678)
	testInputRequiredWorkflows := []*ghtwirp.RequiredWorkflow{
		{
			RepoID:         "R_lAHNJr8DAw",
			OwnerID:        "test-org-id",
			RepoNwo:        "test-org/test-repo-1",
			Path:           ".github/required/test.yml",
			Ref:            "refs/head/main",
			RepoDatabaseID: 3,
			RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
		},
		{
			RepoID:         "R_mgA-Pz4_Pj8-Pz4",
			OwnerID:        "test-org-id",
			RepoNwo:        "test-org/test-repo-2",
			Path:           ".github/required/sample.yml",
			Ref:            "refs/head/master",
			RepoDatabaseID: 62,
			RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
		},
		{
			RepoID:         "R_kgAB",
			OwnerID:        "test-org-id",
			RepoNwo:        "test-org/test-repo-3",
			Path:           ".github/required/sampleworkflow.yml",
			Ref:            "refs/head/master",
			RepoDatabaseID: 1,
			RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
		},
	}

	type args struct {
		requiredWorkflows func() []*ghtwirp.RequiredWorkflow
		invokingEventName string
	}
	tests := []struct {
		name             string
		args             args
		setupAuthzMocks  func() authzd.Client
		setupSpokesMocks func() spokesd.Client
		want             []types.ResolvedFile
	}{
		{
			name: "Returns no pipeline files when the requiredWorkflows input is empty",
			setupAuthzMocks: func() authzd.Client {
				return &authzd.MockClient{}
			},
			setupSpokesMocks: func() spokesd.Client {
				return &spokesd.MockClient{}
			},
			args: args{
				invokingEventName: flowevents.PullRequest,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow { return []*ghtwirp.RequiredWorkflow{} },
			},
			want: nil,
		},
		{
			name: "Returns no pipeline files when the batch authorize call to authz fails with some error",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(nil, errors.New("internal authz error"))
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				return &spokesd.MockClient{}
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow { return testInputRequiredWorkflows },
			},
			want: nil,
		},
		{
			name: "Returns no pipeline files when all required workflows are filtered based on authz policy",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_DENY, Reason: "inaccessible"},
							{Result: authzpb.Result_DENY, Reason: "inaccessible"},
							{Result: authzpb.Result_DENY, Reason: "inaccessible"},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				return &spokesd.MockClient{}
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow { return testInputRequiredWorkflows },
			},
			want: nil,
		},
		{
			name: "Returns no pipeline files when we fail to resolve refs for all required workflows",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveObjectsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sample.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveObjectsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Error{
									Error: "missing",
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Error{
									Error: "missing",
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Error{
									Error: "missing",
								},
							},
						},
					},
				}

				for i, req := range resolveObjectsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveObjectsResponse[i], nil)
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow { return testInputRequiredWorkflows },
			},
			want: nil,
		},
		{
			name: "Returns no pipeline files when fail to resolve commits for all the required workflows",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sample.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveRefsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-1",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-2",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-3",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-1",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sample.yml",
								Ref:  "refs/head/master",
								SHA:  "resolved-commit-id-2",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
								SHA:  "resolved-commit-id-3",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Error{
									Error: "missing",
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Error{
									Error: "missing",
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Error{
									Error: "missing",
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow { return testInputRequiredWorkflows },
			},
			want: nil,
		},
		{
			name: "Returns no pipeline file when spokes fails to resolve all the blobs",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sample.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveRefsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-1",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-2",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-3",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-1",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sample.yml",
								Ref:  "refs/head/master",
								SHA:  "resolved-commit-id-2",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
								SHA:  "resolved-commit-id-3",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-2",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-3",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				resolveBlobsRequests := []*spokesd.GetBlobContentsBatchRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-1",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-2",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-3",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				for _, req := range resolveBlobsRequests {
					mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(nil, errors.New("failed to resolve blobs"))
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow { return testInputRequiredWorkflows },
			},
			want: nil,
		},
		{
			name: "Returns additional resolved files when we all calls succeed",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sample.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveRefsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-1",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-2",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-3",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-1",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sample.yml",
								Ref:  "refs/head/master",
								SHA:  "resolved-commit-id-2",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
								SHA:  "resolved-commit-id-3",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-2",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-3",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				resolveBlobsRequests := []*spokesd.GetBlobContentsBatchRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-1",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-2",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-3",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveBlobsResponseMap1 := make(map[string]spokesd.Blob, 0)
				resolveBlobsResponseMap2 := make(map[string]spokesd.Blob, 0)
				resolveBlobsResponseMap3 := make(map[string]spokesd.Blob, 0)

				resolveBlobsResponseMap1["resolved-object-id-1"] = spokesd.Blob("blob_file_contents_1")
				resolveBlobsResponseMap2["resolved-object-id-2"] = spokesd.Blob("blob_file_contents_2")
				resolveBlobsResponseMap3["resolved-object-id-3"] = spokesd.Blob("blob_file_contents_3")

				blobContentsBatchResponse := []*spokesd.GetBlobContentsBatchResponse{
					{
						RepositoryID:     3,
						BlobContentsByID: resolveBlobsResponseMap1,
					},
					{
						RepositoryID:     62,
						BlobContentsByID: resolveBlobsResponseMap2,
					},
					{
						RepositoryID:     1,
						BlobContentsByID: resolveBlobsResponseMap3,
					},
				}

				for i, req := range resolveBlobsRequests {
					mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(blobContentsBatchResponse[i], nil)
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow { return testInputRequiredWorkflows },
			},
			want: []types.ResolvedFile{
				{
					Path:          "required/3/.github/required/test.yml",
					Ref:           "refs/head/main",
					IsTruncated:   false,
					Text:          "blob_file_contents_1",
					SHA:           "resolved-commit-id-1",
					RepositoryNwo: "test-org/test-repo-1",
					RepositoryID:  "R_lAHNJr8DAw",
				},
				{
					Path:          "required/62/.github/required/sample.yml",
					Ref:           "refs/head/master",
					IsTruncated:   false,
					Text:          "blob_file_contents_2",
					SHA:           "resolved-commit-id-2",
					RepositoryNwo: "test-org/test-repo-2",
					RepositoryID:  "R_mgA-Pz4_Pj8-Pz4",
				},
				{
					Path:          "required/1/.github/required/sampleworkflow.yml",
					Ref:           "refs/head/master",
					IsTruncated:   false,
					Text:          "blob_file_contents_3",
					SHA:           "resolved-commit-id-3",
					RepositoryNwo: "test-org/test-repo-3",
					RepositoryID:  "R_kgAB",
				},
			},
		},
		{
			name: "Returns additional resolved files when we all calls succeed and required workflow ref is a SHA",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "ad33a40b3c95381d094f0005885b98f4eb396771",
								SHA:  "ad33a40b3c95381d094f0005885b98f4eb396771",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				resolveBlobsRequests := []*spokesd.GetBlobContentsBatchRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-1",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveBlobsResponseMap1 := make(map[string]spokesd.Blob, 0)

				resolveBlobsResponseMap1["resolved-object-id-1"] = spokesd.Blob("blob_file_contents_1")

				blobContentsBatchResponse := []*spokesd.GetBlobContentsBatchResponse{
					{
						RepositoryID:     3,
						BlobContentsByID: resolveBlobsResponseMap1,
					},
				}

				for i, req := range resolveBlobsRequests {
					mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(blobContentsBatchResponse[i], nil)
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow {
					return []*ghtwirp.RequiredWorkflow{
						{
							RepoID:         "R_lAHNJr8DAw",
							OwnerID:        "test-org-id",
							RepoNwo:        "test-org/test-repo-1",
							Path:           ".github/required/test.yml",
							Ref:            "ad33a40b3c95381d094f0005885b98f4eb396771",
							RepoDatabaseID: 3,
							RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL,
						},
					}
				},
			},
			want: []types.ResolvedFile{
				{
					Path:          "required/3/.github/required/test.yml",
					Ref:           "ad33a40b3c95381d094f0005885b98f4eb396771",
					IsTruncated:   false,
					Text:          "blob_file_contents_1",
					SHA:           "ad33a40b3c95381d094f0005885b98f4eb396771",
					RepositoryNwo: "test-org/test-repo-1",
					RepositoryID:  "R_lAHNJr8DAw",
				},
			},
		},
		{
			name: "Returns a separate additional resolved file for each unique ruleset configuration when object id is the same",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 62, Name: "test-org/test-repo-2"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							// same workflow pinned to different ref
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "",
							},
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/branch-name",
								SHA:  "",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							// same workflow pinned to different SHA
							{
								Path: ".github/required/sample.yml",
								Ref:  "",
								SHA:  "resolved-commit-id-3",
							},
							{
								Path: ".github/required/sample.yml",
								Ref:  "",
								SHA:  "resolved-commit-id-4",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveRefsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-1",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-2",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-3",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-4",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-1",
							},
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/branch-name",
								SHA:  "resolved-commit-id-2",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sample.yml",
								SHA:  "resolved-commit-id-3",
							},
							{
								Path: ".github/required/sample.yml",
								SHA:  "resolved-commit-id-4",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-2",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-2",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				resolveBlobsRequests := []*spokesd.GetBlobContentsBatchRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-1",
							"resolved-object-id-1",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 62,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-2",
							"resolved-object-id-2",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveBlobsResponseMap1 := make(map[string]spokesd.Blob, 0)
				resolveBlobsResponseMap2 := make(map[string]spokesd.Blob, 0)

				resolveBlobsResponseMap1["resolved-object-id-1"] = spokesd.Blob("blob_file_contents_1")
				resolveBlobsResponseMap2["resolved-object-id-2"] = spokesd.Blob("blob_file_contents_2")

				blobContentsBatchResponse := []*spokesd.GetBlobContentsBatchResponse{
					{
						RepositoryID:     3,
						BlobContentsByID: resolveBlobsResponseMap1,
					},
					{
						RepositoryID:     62,
						BlobContentsByID: resolveBlobsResponseMap2,
					},
				}

				for i, req := range resolveBlobsRequests {
					mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(blobContentsBatchResponse[i], nil)
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow {
					return []*ghtwirp.RequiredWorkflow{
						{
							RepoID:         "R_lAHNJr8DAw",
							OwnerID:        "test-org-id",
							RepoNwo:        "test-org/test-repo-1",
							Path:           ".github/required/test.yml",
							Ref:            "refs/head/main",
							RepoDatabaseID: 3,
							RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
						},
						{
							RepoID:         "R_lAHNJr8DAw",
							OwnerID:        "test-org-id",
							RepoNwo:        "test-org/test-repo-1",
							Path:           ".github/required/test.yml",
							Ref:            "refs/head/branch-name",
							RepoDatabaseID: 3,
							RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
						},
						{
							RepoID:          "R_mgA-Pz4_Pj8-Pz4",
							OwnerID:         "test-org-id",
							RepoNwo:         "test-org/test-repo-2",
							Path:            ".github/required/sample.yml",
							WorkflowFileSha: "resolved-commit-id-3",
							RepoDatabaseID:  62,
							RepoVisibility:  ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
						},
						{
							RepoID:          "R_mgA-Pz4_Pj8-Pz4",
							OwnerID:         "test-org-id",
							RepoNwo:         "test-org/test-repo-2",
							Path:            ".github/required/sample.yml",
							WorkflowFileSha: "resolved-commit-id-4",
							RepoDatabaseID:  62,
							RepoVisibility:  ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
						},
					}
				},
			},
			want: []types.ResolvedFile{
				{
					Path:          "required/3/.github/required/test.yml",
					Ref:           "refs/head/main",
					IsTruncated:   false,
					Text:          "blob_file_contents_1",
					SHA:           "resolved-commit-id-1",
					RepositoryNwo: "test-org/test-repo-1",
					RepositoryID:  "R_lAHNJr8DAw",
				},
				{
					Path:          "required/3/.github/required/test.yml",
					Ref:           "refs/head/branch-name",
					IsTruncated:   false,
					Text:          "blob_file_contents_1",
					SHA:           "resolved-commit-id-2",
					RepositoryNwo: "test-org/test-repo-1",
					RepositoryID:  "R_lAHNJr8DAw",
				},
				{
					Path:          "required/62/.github/required/sample.yml",
					Ref:           "",
					IsTruncated:   false,
					Text:          "blob_file_contents_2",
					SHA:           "resolved-commit-id-3",
					RepositoryNwo: "test-org/test-repo-2",
					RepositoryID:  "R_mgA-Pz4_Pj8-Pz4",
				},
				{
					Path:          "required/62/.github/required/sample.yml",
					Ref:           "",
					IsTruncated:   false,
					Text:          "blob_file_contents_2",
					SHA:           "resolved-commit-id-4",
					RepositoryNwo: "test-org/test-repo-2",
					RepositoryID:  "R_mgA-Pz4_Pj8-Pz4",
				},
			},
		},
		{
			name: "Returns only some additional resolved files which succeeded the authz policy check",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
					{ID: 2, Name: "test-org/test-repo-4"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_DENY},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_DENY},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveRefsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-1",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-3",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-1",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
								SHA:  "resolved-commit-id-3",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-3",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				resolveBlobsRequests := []*spokesd.GetBlobContentsBatchRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-1",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-3",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveBlobsResponseMap1 := make(map[string]spokesd.Blob, 0)
				resolveBlobsResponseMap2 := make(map[string]spokesd.Blob, 0)

				resolveBlobsResponseMap1["resolved-object-id-1"] = spokesd.Blob("blob_file_contents_1")
				resolveBlobsResponseMap2["resolved-object-id-3"] = spokesd.Blob("blob_file_contents_3")

				blobContentsBatchResponse := []*spokesd.GetBlobContentsBatchResponse{
					{
						RepositoryID:     3,
						BlobContentsByID: resolveBlobsResponseMap1,
					},
					{
						RepositoryID:     1,
						BlobContentsByID: resolveBlobsResponseMap2,
					},
				}

				for i, req := range resolveBlobsRequests {
					mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(blobContentsBatchResponse[i], nil)
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow {
					modifiedTestInputRequiredWorkflows := make([]*ghtwirp.RequiredWorkflow, 0)
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, testInputRequiredWorkflows...)
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, &ghtwirp.RequiredWorkflow{
						RepoID:         "R_kgAC",
						OwnerID:        "test-org-id",
						RepoNwo:        "test-org/test-repo-4",
						Path:           ".github/workflows/required/abc.yml",
						Ref:            "refs/head/prod",
						RepoDatabaseID: 2,
						RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
					})

					return modifiedTestInputRequiredWorkflows
				},
			},
			want: []types.ResolvedFile{
				{
					Path:          "required/3/.github/required/test.yml",
					Ref:           "refs/head/main",
					IsTruncated:   false,
					Text:          "blob_file_contents_1",
					SHA:           "resolved-commit-id-1",
					RepositoryNwo: "test-org/test-repo-1",
					RepositoryID:  "R_lAHNJr8DAw",
				},
				{
					Path:          "required/1/.github/required/sampleworkflow.yml",
					Ref:           "refs/head/master",
					IsTruncated:   false,
					Text:          "blob_file_contents_3",
					SHA:           "resolved-commit-id-3",
					RepositoryNwo: "test-org/test-repo-3",
					RepositoryID:  "R_kgAB",
				},
			},
		},
		{
			name: "Returns only some additional resolved files which passed the authz policy check and object resolution for them was successful",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
					{ID: 2, Name: "test-org/test-repo-4"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_DENY},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/prod",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveRefsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-1",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-3",
										},
										Type: stypes.Object_TYPE_INVALID,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-4",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-1",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/prod",
								SHA:  "resolved-commit-id-4",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-4",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				resolveBlobsRequests := []*spokesd.GetBlobContentsBatchRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-1",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-4",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveBlobsResponseMap1 := make(map[string]spokesd.Blob, 0)
				resolveBlobsResponseMap2 := make(map[string]spokesd.Blob, 0)

				resolveBlobsResponseMap1["resolved-object-id-1"] = spokesd.Blob("blob_file_contents_1")
				resolveBlobsResponseMap2["resolved-object-id-4"] = spokesd.Blob("blob_file_contents_4")

				blobContentsBatchResponse := []*spokesd.GetBlobContentsBatchResponse{
					{
						RepositoryID:     3,
						BlobContentsByID: resolveBlobsResponseMap1,
					},
					{
						RepositoryID:     2,
						BlobContentsByID: resolveBlobsResponseMap2,
					},
				}

				for i, req := range resolveBlobsRequests {
					mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(blobContentsBatchResponse[i], nil)
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow {
					modifiedTestInputRequiredWorkflows := make([]*ghtwirp.RequiredWorkflow, 0)
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, testInputRequiredWorkflows...)
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, &ghtwirp.RequiredWorkflow{
						RepoID:         "R_kgAC",
						OwnerID:        "test-org-id",
						RepoNwo:        "test-org/test-repo-4",
						Path:           ".github/workflows/required/abc.yml",
						Ref:            "refs/head/prod",
						RepoDatabaseID: 2,
						RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC,
					})

					return modifiedTestInputRequiredWorkflows
				},
			},
			want: []types.ResolvedFile{
				{
					Path:          "required/3/.github/required/test.yml",
					Ref:           "refs/head/main",
					IsTruncated:   false,
					Text:          "blob_file_contents_1",
					SHA:           "resolved-commit-id-1",
					RepositoryNwo: "test-org/test-repo-1",
					RepositoryID:  "R_lAHNJr8DAw",
				},
				{
					Path:          "required/2/.github/workflows/required/abc.yml",
					Ref:           "refs/head/prod",
					IsTruncated:   false,
					Text:          "blob_file_contents_4",
					SHA:           "resolved-commit-id-4",
					RepositoryNwo: "test-org/test-repo-4",
					RepositoryID:  "R_kgAC",
				},
			},
		},
		{
			name: "Returns additional resolved files when some of them passed the authz policy check and some of them failed in commit resolution because of non blob objects",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
					{ID: 2, Name: "test-org/test-repo-4"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_DENY},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/prod",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveRefsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-1",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-3",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-4",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-1",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
								SHA:  "resolved-commit-id-3",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/prod",
								SHA:  "resolved-commit-id-4",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-3",
										},
										Type: stypes.Object_TYPE_INVALID,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-4",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				resolveBlobsRequests := []*spokesd.GetBlobContentsBatchRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-1",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-4",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveBlobsResponseMap1 := make(map[string]spokesd.Blob, 0)
				resolveBlobsResponseMap2 := make(map[string]spokesd.Blob, 0)

				resolveBlobsResponseMap1["resolved-object-id-1"] = spokesd.Blob("blob_file_contents_1")
				resolveBlobsResponseMap2["resolved-object-id-4"] = spokesd.Blob("blob_file_contents_4")

				blobContentsBatchResponse := []*spokesd.GetBlobContentsBatchResponse{
					{
						RepositoryID:     3,
						BlobContentsByID: resolveBlobsResponseMap1,
					},
					{
						RepositoryID:     2,
						BlobContentsByID: resolveBlobsResponseMap2,
					},
				}

				for i, req := range resolveBlobsRequests {
					mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(blobContentsBatchResponse[i], nil)
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow {
					modifiedTestInputRequiredWorkflows := make([]*ghtwirp.RequiredWorkflow, 0)
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, testInputRequiredWorkflows...)
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, &ghtwirp.RequiredWorkflow{
						RepoID:         "R_kgAC",
						OwnerID:        "test-org-id",
						RepoNwo:        "test-org/test-repo-4",
						Path:           ".github/workflows/required/abc.yml",
						Ref:            "refs/head/prod",
						RepoDatabaseID: 2,
						RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
					})

					return modifiedTestInputRequiredWorkflows
				},
			},
			want: []types.ResolvedFile{
				{
					Path:          "required/3/.github/required/test.yml",
					Ref:           "refs/head/main",
					IsTruncated:   false,
					Text:          "blob_file_contents_1",
					SHA:           "resolved-commit-id-1",
					RepositoryNwo: "test-org/test-repo-1",
					RepositoryID:  "R_lAHNJr8DAw",
				},
				{
					Path:          "required/2/.github/workflows/required/abc.yml",
					Ref:           "refs/head/prod",
					IsTruncated:   false,
					Text:          "blob_file_contents_4",
					SHA:           "resolved-commit-id-4",
					RepositoryNwo: "test-org/test-repo-4",
					RepositoryID:  "R_kgAC",
				},
			},
		},
		{
			name: "Returns additional resolved files when some of them passed the authz policy check and some of them failed in ref and commit resolution",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
					{ID: 2, Name: "test-org/test-repo-4"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_DENY},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/prod",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveRefsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-1",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Error{
									Error: "internal spokes error when resolving object",
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-4",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-1",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/prod",
								SHA:  "resolved-commit-id-4",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-4",
										},
										Type: stypes.Object_TYPE_INVALID,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				resolveBlobsRequests := []*spokesd.GetBlobContentsBatchRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-1",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveBlobsResponseMap1 := make(map[string]spokesd.Blob, 0)

				resolveBlobsResponseMap1["resolved-object-id-1"] = spokesd.Blob("blob_file_contents_1")

				blobContentsBatchResponse := []*spokesd.GetBlobContentsBatchResponse{
					{
						RepositoryID:     3,
						BlobContentsByID: resolveBlobsResponseMap1,
					},
				}
				for i, req := range resolveBlobsRequests {
					mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(blobContentsBatchResponse[i], nil)
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow {
					modifiedTestInputRequiredWorkflows := make([]*ghtwirp.RequiredWorkflow, 0)
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, testInputRequiredWorkflows...)
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, &ghtwirp.RequiredWorkflow{
						RepoID:         "R_kgAC",
						OwnerID:        "test-org-id",
						RepoNwo:        "test-org/test-repo-4",
						Path:           ".github/workflows/required/abc.yml",
						Ref:            "refs/head/prod",
						RepoDatabaseID: 2,
						RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
					})

					return modifiedTestInputRequiredWorkflows
				},
			},
			want: []types.ResolvedFile{
				{
					Path:          "required/3/.github/required/test.yml",
					Ref:           "refs/head/main",
					IsTruncated:   false,
					Text:          "blob_file_contents_1",
					SHA:           "resolved-commit-id-1",
					RepositoryNwo: "test-org/test-repo-1",
					RepositoryID:  "R_lAHNJr8DAw",
				},
			},
		},
		{
			name: "Returns additional workflows when some of them failed the authz check, some of them failed in commit resolution and some of them failed in blob resolution",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
					{ID: 2, Name: "test-org/test-repo-4"},
					{ID: 4, Name: "test-org/test-repo-5"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_DENY},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/prod",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 4,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/linter/xyz.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveRefsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-1",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-3",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-4",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-5",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-1",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
								SHA:  "resolved-commit-id-3",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/prod",
								SHA:  "resolved-commit-id-4",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 4,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/linter/xyz.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-5",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Error{
									Error: "error while hitting the spokesD endpoint",
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-4",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-5",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				resolveBlobsRequests := []*spokesd.GetBlobContentsBatchRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-1",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-4",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 4,
						ActorID:      invokingActorID,
						ObjectIDs: []string{
							"resolved-object-id-5",
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveBlobsResponseMap1 := make(map[string]spokesd.Blob, 0)
				resolveBlobsResponseMap2 := make(map[string]spokesd.Blob, 0)

				resolveBlobsResponseMap1["resolved-object-id-1"] = spokesd.Blob("blob_file_contents_1")
				resolveBlobsResponseMap2["resolved-object-id-4"] = spokesd.Blob("blob_file_contents_4")

				blobContentsBatchResponse := []*spokesd.GetBlobContentsBatchResponse{
					{
						RepositoryID:     3,
						BlobContentsByID: resolveBlobsResponseMap1,
					},
					{
						RepositoryID:     2,
						BlobContentsByID: resolveBlobsResponseMap2,
					},
				}

				for i, req := range resolveBlobsRequests {
					if i == 2 {
						mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(nil, errors.New("error resolving blob"))
					} else {
						mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(blobContentsBatchResponse[i], nil)
					}
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow {
					modifiedTestInputRequiredWorkflows := make([]*ghtwirp.RequiredWorkflow, 0)
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, testInputRequiredWorkflows...)
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, &ghtwirp.RequiredWorkflow{
						RepoID:         "R_kgAC",
						OwnerID:        "test-org-id",
						RepoNwo:        "test-org/test-repo-4",
						Path:           ".github/workflows/required/abc.yml",
						Ref:            "refs/head/prod",
						RepoDatabaseID: 2,
						RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
					})
					modifiedTestInputRequiredWorkflows = append(modifiedTestInputRequiredWorkflows, &ghtwirp.RequiredWorkflow{
						RepoID:         "R_kgAE",
						OwnerID:        "test-org-id",
						RepoNwo:        "test-org/test-repo-5",
						Path:           ".github/workflows/linter/xyz.yml",
						Ref:            "refs/head/main",
						RepoDatabaseID: 4,
						RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
					})

					return modifiedTestInputRequiredWorkflows
				},
			},
			want: []types.ResolvedFile{
				{
					Path:          "required/3/.github/required/test.yml",
					Ref:           "refs/head/main",
					IsTruncated:   false,
					Text:          "blob_file_contents_1",
					SHA:           "resolved-commit-id-1",
					RepositoryNwo: "test-org/test-repo-1",
					RepositoryID:  "R_lAHNJr8DAw",
				},
				{
					Path:          "required/2/.github/workflows/required/abc.yml",
					Ref:           "refs/head/prod",
					IsTruncated:   false,
					Text:          "blob_file_contents_4",
					SHA:           "resolved-commit-id-4",
					RepositoryNwo: "test-org/test-repo-4",
					RepositoryID:  "R_kgAC",
				},
			},
		},
		{
			name: "Returns additional workflows where some of them belong to the same source repo and some of them failed the authz check, some of them failed in object resolution and some of them failed in blob resolution",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams := []*authzd.RepositoryParam{
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 3, Name: "test-org/test-repo-1"},
					{ID: 62, Name: "test-org/test-repo-2"},
					{ID: 1, Name: "test-org/test-repo-3"},
					{ID: 1, Name: "test-org/test-repo-3"},
					{ID: 2, Name: "test-org/test-repo-4"},
					{ID: 2, Name: "test-org/test-repo-4"},
					{ID: 4, Name: "test-org/test-repo-5"},
				}
				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: []*authzpb.Decision{
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_DENY},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
							{Result: authzpb.Result_ALLOW},
						},
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
							},
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/main",
							},
							{
								Path: ".github/workflows/required/cde.yml",
								Ref:  "refs/head/main",
							},
							{
								Path: ".github/workflows/required/xyz.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/sampleworkflow.yml",
								Ref:  "refs/head/master",
							},
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/master",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/prod",
							},
							{
								Path: ".github/workflows/required/xyz.yml",
								Ref:  "refs/head/prod",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 4,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/linter/xyz.yml",
								Ref:  "refs/head/main",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveRefsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-1",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-10",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-11",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-12",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Error{
									Error: "internal spokes error when resolving object",
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-13",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-4",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-14",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-commit-id-5",
										},
										Type: stypes.Object_TYPE_COMMIT,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests := []*spokesd.ResolveObjectsRequest{
					{
						RepositoryID: 3,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-1",
							},
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-10",
							},
							{
								Path: ".github/workflows/required/cde.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-11",
							},
							{
								Path: ".github/workflows/required/xyz.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-12",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 1,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/required/test.yml",
								Ref:  "refs/head/master",
								SHA:  "resolved-commit-id-13",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 2,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/required/abc.yml",
								Ref:  "refs/head/prod",
								SHA:  "resolved-commit-id-4",
							},
							{
								Path: ".github/workflows/required/xyz.yml",
								Ref:  "refs/head/prod",
								SHA:  "resolved-commit-id-14",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
					{
						RepositoryID: 4,
						ActorID:      invokingActorID,
						ObjectIdentifierList: []*spokesd.ObjectIdentifier{
							{
								Path: ".github/workflows/linter/xyz.yml",
								Ref:  "refs/head/main",
								SHA:  "resolved-commit-id-5",
							},
						},
						QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
					},
				}

				resolveCommitsResponse := []*objects.ResolveObjectsResponse{
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-1",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-10",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-11",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-12",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-13",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-4",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-14",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
					{
						Items: []*objects.ResolveObjectsResponse_ResolvedItem{
							{
								Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
									Object: &stypes.Object{
										Oid: &stypes.ObjectID{
											Id: "resolved-object-id-5",
										},
										Type: stypes.Object_TYPE_BLOB,
									},
								},
							},
						},
					},
				}

				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				failFast := stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST
				resolveBlobsRequests := []*spokesd.GetBlobContentsBatchRequest{
					{RepositoryID: 3, ActorID: invokingActorID, ObjectIDs: []string{"resolved-object-id-1", "resolved-object-id-10", "resolved-object-id-11", "resolved-object-id-12"}, QualityOfService: failFast},
					{RepositoryID: 1, ActorID: invokingActorID, ObjectIDs: []string{"resolved-object-id-13"}, QualityOfService: failFast},
					{RepositoryID: 2, ActorID: invokingActorID, ObjectIDs: []string{"resolved-object-id-4", "resolved-object-id-14"}, QualityOfService: failFast},
					{RepositoryID: 4, ActorID: invokingActorID, ObjectIDs: []string{"resolved-object-id-5"}, QualityOfService: failFast},
				}

				resolveBlobsResponseMap1 := make(map[string]spokesd.Blob, 0)
				resolveBlobsResponseMap2 := make(map[string]spokesd.Blob, 0)
				resolveBlobsResponseMap3 := make(map[string]spokesd.Blob, 0)

				resolveBlobsResponseMap1["resolved-object-id-1"] = spokesd.Blob("blob_file_contents_1")
				resolveBlobsResponseMap1["resolved-object-id-10"] = spokesd.Blob("blob_file_contents_10")
				resolveBlobsResponseMap1["resolved-object-id-11"] = spokesd.Blob("blob_file_contents_11")
				resolveBlobsResponseMap1["resolved-object-id-12"] = spokesd.Blob("blob_file_contents_12")
				resolveBlobsResponseMap2["resolved-object-id-13"] = spokesd.Blob("blob_file_contents_13")
				resolveBlobsResponseMap3["resolved-object-id-5"] = spokesd.Blob("blob_file_contents_5")

				blobContentsBatchResponse := []*spokesd.GetBlobContentsBatchResponse{
					{
						RepositoryID:     3,
						BlobContentsByID: resolveBlobsResponseMap1,
					},
					{
						RepositoryID:     1,
						BlobContentsByID: resolveBlobsResponseMap2,
					},
					nil,
					{
						RepositoryID:     4,
						BlobContentsByID: resolveBlobsResponseMap3,
					},
				}

				for i, req := range resolveBlobsRequests {
					if i == 2 {
						mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(nil, errors.New("error resolving blob"))
					} else {
						mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(blobContentsBatchResponse[i], nil)
					}
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequestTarget,
				requiredWorkflows: func() []*ghtwirp.RequiredWorkflow {
					return []*ghtwirp.RequiredWorkflow{
						{RepoID: "R_lAHNJr8DAw", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-1", Path: ".github/required/test.yml", Ref: "refs/head/main", RepoDatabaseID: 3, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
						{RepoID: "R_lAHNJr8DAw", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-1", Path: ".github/workflows/required/abc.yml", Ref: "refs/head/main", RepoDatabaseID: 3, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
						{RepoID: "R_lAHNJr8DAw", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-1", Path: ".github/workflows/required/cde.yml", Ref: "refs/head/main", RepoDatabaseID: 3, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
						{RepoID: "R_lAHNJr8DAw", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-1", Path: ".github/workflows/required/xyz.yml", Ref: "refs/head/main", RepoDatabaseID: 3, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
						{RepoID: "R_mgA-Pz4_Pj8-Pz4", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-2", Path: ".github/required/sample.yml", Ref: "refs/head/master", RepoDatabaseID: 62, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
						{RepoID: "R_kgAB", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-3", Path: ".github/required/sampleworkflow.yml", Ref: "refs/head/master", RepoDatabaseID: 1, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
						{RepoID: "R_kgAB", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-3", Path: ".github/required/test.yml", Ref: "refs/head/master", RepoDatabaseID: 1, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
						{RepoID: "R_kgAC", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-4", Path: ".github/workflows/required/abc.yml", Ref: "refs/head/prod", RepoDatabaseID: 2, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
						{RepoID: "R_kgAC", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-4", Path: ".github/workflows/required/xyz.yml", Ref: "refs/head/prod", RepoDatabaseID: 2, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
						{RepoID: "R_kgAE", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-5", Path: ".github/workflows/linter/xyz.yml", Ref: "refs/head/main", RepoDatabaseID: 4, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
					}
				},
			},
			want: []types.ResolvedFile{
				{Path: "required/3/.github/required/test.yml", Ref: "refs/head/main", IsTruncated: false, Text: "blob_file_contents_1", SHA: "resolved-commit-id-1", RepositoryNwo: "test-org/test-repo-1", RepositoryID: "R_lAHNJr8DAw"},
				{Path: "required/3/.github/workflows/required/abc.yml", Ref: "refs/head/main", IsTruncated: false, Text: "blob_file_contents_10", SHA: "resolved-commit-id-10", RepositoryNwo: "test-org/test-repo-1", RepositoryID: "R_lAHNJr8DAw"},
				{Path: "required/3/.github/workflows/required/cde.yml", Ref: "refs/head/main", IsTruncated: false, Text: "blob_file_contents_11", SHA: "resolved-commit-id-11", RepositoryNwo: "test-org/test-repo-1", RepositoryID: "R_lAHNJr8DAw"},
				{Path: "required/3/.github/workflows/required/xyz.yml", Ref: "refs/head/main", IsTruncated: false, Text: "blob_file_contents_12", SHA: "resolved-commit-id-12", RepositoryNwo: "test-org/test-repo-1", RepositoryID: "R_lAHNJr8DAw"},
				{Path: "required/1/.github/required/test.yml", Ref: "refs/head/master", IsTruncated: false, Text: "blob_file_contents_13", SHA: "resolved-commit-id-13", RepositoryNwo: "test-org/test-repo-3", RepositoryID: "R_kgAB"},
				{Path: "required/4/.github/workflows/linter/xyz.yml", Ref: "refs/head/main", IsTruncated: false, Text: "blob_file_contents_5", SHA: "resolved-commit-id-5", RepositoryNwo: "test-org/test-repo-5", RepositoryID: "R_kgAE"},
			},
		},
		{
			name: "load test for returning required workflows",
			setupAuthzMocks: func() authzd.Client {
				mockAuthzClient := &authzd.MockClient{}
				repoParams, decisionsResponse := getLoadTestAuthzDRequestAndResponse()

				mockAuthzClient.EXPECT().BatchAuthorize(mock.Anything, uint64(invokingRepoID), repoParams).Return(
					&authzpb.BatchDecision{
						Decisions: decisionsResponse,
					},
					nil)
				return mockAuthzClient
			},
			setupSpokesMocks: func() spokesd.Client {
				mockSpokesClient := &spokesd.MockClient{}
				resolveRefsRequests, resolveRefsResponse := getLoadTestSpokesRefResolutionRequestAndResponse()
				for i, req := range resolveRefsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByRef(mock.Anything, req).Return(resolveRefsResponse[i], nil)
				}

				resolveCommitsRequests, resolveCommitsResponse := getLoadTestSpokesCommitResolutionRequestAndResponse()
				for i, req := range resolveCommitsRequests {
					mockSpokesClient.EXPECT().ResolveObjectsByCommitShaAndPath(mock.Anything, req).Return(resolveCommitsResponse[i], nil)
				}

				resolveBlobsRequests, resolveBlobsResponse := getLoadTestSpokesBlobResolutionRequestAndResponse()
				for i, req := range resolveBlobsRequests {
					mockSpokesClient.EXPECT().GetBlobContentsBatch(mock.Anything, req).Return(resolveBlobsResponse[i], nil)
				}

				return mockSpokesClient
			},
			args: args{
				invokingEventName: flowevents.PullRequest,
				requiredWorkflows: getLoadTestRequiredWorkflowsInput,
			},
			want: getLoadTestResolvedFilesResponse(),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := &requiredWorkflowsProvider{
				obs: observability.NewNullObservability(),
			}

			w.authzClient = tt.setupAuthzMocks()
			w.spokesClient = tt.setupSpokesMocks()

			got := w.GetRequiredWorkflowFiles(context.Background(), tt.args.requiredWorkflows(), tt.args.invokingEventName, invokingRepoID, invokingActorID)
			if tt.want == nil {
				assert.Nil(t, got)
			} else {
				assert.Equal(t, len(tt.want), len(got))
				gotAllExpectedFiles := true

				// Iterating it like this, because there is no
				// guarantee that we will get the files in the
				// expected order.
				for _, resolvedPipelineFile := range got {
					found := false
					for _, wantedPipelineFile := range tt.want {
						if reflect.DeepEqual(resolvedPipelineFile, wantedPipelineFile) {
							found = true
							break
						}
					}

					if !found {
						gotAllExpectedFiles = false
						break
					}
				}

				assert.True(t, gotAllExpectedFiles)
			}
		})
	}
}

func getLoadTestRequiredWorkflowsInput() []*ghtwirp.RequiredWorkflow {
	loadTestInput := make([]*ghtwirp.RequiredWorkflow, 0)

	requiredWorkflowTestInputs := getTestRequiredWorkflowInputsFormat()

	for _, input := range requiredWorkflowTestInputs {
		// We populate workflow file names like `A.yml`, `B.yml` and so on
		for i := 65; i <= 90; i++ {
			loadTestInput = append(loadTestInput, &ghtwirp.RequiredWorkflow{
				RepoID:         input.RepoID,
				OwnerID:        input.OwnerID,
				RepoNwo:        input.RepoNwo,
				Ref:            input.Ref,
				Path:           fmt.Sprintf(input.Path, fmt.Sprint(i)),
				RepoDatabaseID: input.RepoDatabaseID,
				RepoVisibility: input.RepoVisibility,
			})
		}

		// We populate workflow file names like `a.yml`, `b.yml` and so on
		for i := 97; i <= 122; i++ {
			loadTestInput = append(loadTestInput, &ghtwirp.RequiredWorkflow{
				RepoID:         input.RepoID,
				OwnerID:        input.OwnerID,
				RepoNwo:        input.RepoNwo,
				Ref:            input.Ref,
				Path:           fmt.Sprintf(input.Path, fmt.Sprint(i)),
				RepoDatabaseID: input.RepoDatabaseID,
				RepoVisibility: input.RepoVisibility,
			})
		}
	}

	return loadTestInput
}

func getTestRequiredWorkflowInputsFormat() []*ghtwirp.RequiredWorkflow {
	// For each entry in this array we generate 52 required workflow entities covering
	// workflow names from `a.yml` to `z.yml` and `A.yml`to `Z.yml`
	return []*ghtwirp.RequiredWorkflow{
		{RepoID: "R_kgAB", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-1", Path: ".github/linter/workflows/%s.yml", Ref: "refs/head/master", RepoDatabaseID: 1, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAC", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-2", Path: "codescanning/workflows/%s.yaml", Ref: "refs/tags/v1", RepoDatabaseID: 2, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAD", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-3", Path: "codescanning/workflows/%s.yaml", Ref: "refs/tags/v2", RepoDatabaseID: 3, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAE", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-4", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 4, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAF", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-5", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 5, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAG", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-6", Path: ".github/required/%s.yml", Ref: "refs/head/master", RepoDatabaseID: 6, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAH", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-7", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 7, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAI", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-8", Path: ".github/required/%s.yml", Ref: "refs/head/prod", RepoDatabaseID: 8, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAJ", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-9", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 9, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAK", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-10", Path: ".github/workflows/required/%s.yml", Ref: "532aa5ec70b450052ca61de1621ad5feb5e22a19", RepoDatabaseID: 10, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAL", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-11", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 11, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAM", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-12", Path: ".github/required/%s.yml", Ref: "refs/head/master", RepoDatabaseID: 12, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAN", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-13", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 13, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAO", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-14", Path: ".github/required/%s.yml", Ref: "refs/head/prod", RepoDatabaseID: 14, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAP", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-15", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 15, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAQ", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-16", Path: ".github/workflows/required/%s.yml", Ref: "refs/head/default", RepoDatabaseID: 16, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAR", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-17", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 17, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAS", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-18", Path: ".github/required/%s.yml", Ref: "refs/head/master", RepoDatabaseID: 18, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAT", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-19", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 19, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAU", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-20", Path: ".github/required/%s.yml", Ref: "ad33a40b3c95381d094f0005885b98f4eb396771", RepoDatabaseID: 20, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAV", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-21", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 21, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAW", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-22", Path: ".github/workflows/required/%s.yml", Ref: "refs/head/default", RepoDatabaseID: 22, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAX", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-23", Path: "required/%s.yml", Ref: "refs/head/prod", RepoDatabaseID: 23, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAY", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-24", Path: ".github/workflows/%s.yml", Ref: "refs/head/main", RepoDatabaseID: 24, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
		{RepoID: "R_kgAZ", OwnerID: "test-org-id", RepoNwo: "test-org/test-repo-25", Path: "workflows/required/%s.yml", Ref: "refs/head/default", RepoDatabaseID: 25, RepoVisibility: ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE},
	}
}

func getLoadTestAuthzDRequestAndResponse() ([]*authzd.RepositoryParam, []*authzpb.Decision) {
	loadTestInputsCount := len(getTestRequiredWorkflowInputsFormat()) * 52
	authzLoadTestInputs := make([]*authzd.RepositoryParam, 0)
	authzLoadTestResponse := make([]*authzpb.Decision, 0)
	repoID := 0
	repoNameFormat := "test-org/test-repo-%d"
	for i := 0; i < loadTestInputsCount; i++ {
		if i%52 == 0 {
			repoID++
		}
		authzLoadTestInputs = append(authzLoadTestInputs, &authzd.RepositoryParam{
			ID:   uint64(repoID),
			Name: fmt.Sprintf(repoNameFormat, repoID),
		})

		authzLoadTestResponse = append(authzLoadTestResponse, &authzpb.Decision{
			Result: authzpb.Result_ALLOW,
		})
	}

	return authzLoadTestInputs, authzLoadTestResponse
}

func getLoadTestSpokesRefResolutionRequestAndResponse() ([]*spokesd.ResolveObjectsRequest, []*objects.ResolveObjectsResponse) {
	objectIdentifierByRepoID := make(map[int64][]*spokesd.ObjectIdentifier)
	resolvedObjectItemByRepoID := make(map[int64][]*objects.ResolveObjectsResponse_ResolvedItem)

	loadTestReqWorkflowsInput := getLoadTestRequiredWorkflowsInput()
	for i, input := range loadTestReqWorkflowsInput {
		_, repoID, _ := input.RepoID.Decode()
		if types.IsCommitSha(input.Ref) {
			continue
		}

		objectIdentifierByRepoID[repoID] = append(objectIdentifierByRepoID[repoID], &spokesd.ObjectIdentifier{
			Ref:  input.Ref,
			Path: input.Path,
		})

		resolvedObjectItemByRepoID[repoID] = append(resolvedObjectItemByRepoID[repoID], &objects.ResolveObjectsResponse_ResolvedItem{
			Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
				Object: &stypes.Object{
					Oid: &stypes.ObjectID{
						Id: fmt.Sprintf("resolved-commit-id-%d", i+1),
					},
					Type: stypes.Object_TYPE_COMMIT,
				},
			},
		})
	}

	resolveRefsInput := make([]*spokesd.ResolveObjectsRequest, 0)
	resolveRefsResponse := make([]*objects.ResolveObjectsResponse, 0)
	for i := 1; i <= len(getTestRequiredWorkflowInputsFormat()); i++ {
		resolveRefsInput = append(resolveRefsInput, &spokesd.ResolveObjectsRequest{
			RepositoryID:         int64(i),
			ActorID:              5678,
			ObjectIdentifierList: objectIdentifierByRepoID[int64(i)],
			QualityOfService:     stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
		})

		resolveRefsResponse = append(resolveRefsResponse, &objects.ResolveObjectsResponse{
			Items: resolvedObjectItemByRepoID[int64(i)],
		})
	}

	return resolveRefsInput, resolveRefsResponse
}

func getLoadTestSpokesCommitResolutionRequestAndResponse() ([]*spokesd.ResolveObjectsRequest, []*objects.ResolveObjectsResponse) {
	objectIdentifierByRepoID := make(map[int64][]*spokesd.ObjectIdentifier)
	resolvedObjectItemByRepoID := make(map[int64][]*objects.ResolveObjectsResponse_ResolvedItem)

	loadTestReqWorkflowsInput := getLoadTestRequiredWorkflowsInput()
	for i, input := range loadTestReqWorkflowsInput {
		_, repoID, _ := input.RepoID.Decode()
		sha := fmt.Sprintf("resolved-commit-id-%d", i+1)
		if types.IsCommitSha(input.Ref) {
			sha = input.Ref
		}

		objectIdentifierByRepoID[repoID] = append(objectIdentifierByRepoID[repoID], &spokesd.ObjectIdentifier{
			Ref:  input.Ref,
			Path: input.Path,
			SHA:  sha,
		})

		resolvedObjectItemByRepoID[repoID] = append(resolvedObjectItemByRepoID[repoID], &objects.ResolveObjectsResponse_ResolvedItem{
			Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
				Object: &stypes.Object{
					Oid: &stypes.ObjectID{
						Id: fmt.Sprintf("resolved-object-id-%d", i+1),
					},
					Type: stypes.Object_TYPE_BLOB,
				},
			},
		})
	}

	resolveCommitsInput := make([]*spokesd.ResolveObjectsRequest, 0)
	resolveCommitsResponse := make([]*objects.ResolveObjectsResponse, 0)
	for i := 1; i <= len(getTestRequiredWorkflowInputsFormat()); i++ {
		resolveCommitsInput = append(resolveCommitsInput, &spokesd.ResolveObjectsRequest{
			RepositoryID:         int64(i),
			ActorID:              5678,
			ObjectIdentifierList: objectIdentifierByRepoID[int64(i)],
			QualityOfService:     stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
		})

		resolveCommitsResponse = append(resolveCommitsResponse, &objects.ResolveObjectsResponse{
			Items: resolvedObjectItemByRepoID[int64(i)],
		})
	}

	return resolveCommitsInput, resolveCommitsResponse
}

func getLoadTestSpokesBlobResolutionRequestAndResponse() ([]*spokesd.GetBlobContentsBatchRequest, []*spokesd.GetBlobContentsBatchResponse) {
	objectIdentifierByRepoID := make(map[int64][]string)
	resolvedBlobsMapByRepoID := make(map[int64]spokesd.BlobContentsByID)

	loadTestReqWorkflowsInput := getLoadTestRequiredWorkflowsInput()
	for i, input := range loadTestReqWorkflowsInput {
		_, repoID, _ := input.RepoID.Decode()
		resolvedObjectID := fmt.Sprintf("resolved-object-id-%d", i+1)
		objectIdentifierByRepoID[repoID] = append(objectIdentifierByRepoID[repoID], resolvedObjectID)

		_, ok := resolvedBlobsMapByRepoID[repoID]
		if !ok {
			resolvedBlobsMapByRepoID[repoID] = make(spokesd.BlobContentsByID)
			resolvedBlobsMapByRepoID[repoID][resolvedObjectID] = []byte(fmt.Sprintf("resolved_file_contents_%d", i+1))
		} else {
			resolvedBlobsMapByRepoID[repoID][resolvedObjectID] = []byte(fmt.Sprintf("resolved_file_contents_%d", i+1))
		}
	}

	resolveBlobsInput := make([]*spokesd.GetBlobContentsBatchRequest, 0)
	resolveBlobsResponse := make([]*spokesd.GetBlobContentsBatchResponse, 0)
	for i := 1; i <= len(getTestRequiredWorkflowInputsFormat()); i++ {
		resolveBlobsInput = append(resolveBlobsInput, &spokesd.GetBlobContentsBatchRequest{
			RepositoryID:     int64(i),
			ActorID:          5678,
			ObjectIDs:        objectIdentifierByRepoID[int64(i)],
			QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
		})

		resolveBlobsResponse = append(resolveBlobsResponse, &spokesd.GetBlobContentsBatchResponse{
			RepositoryID:     int64(i),
			BlobContentsByID: resolvedBlobsMapByRepoID[int64(i)],
		})
	}

	return resolveBlobsInput, resolveBlobsResponse
}

func getLoadTestResolvedFilesResponse() []types.ResolvedFile {
	inputRequiredWorkflows := getLoadTestRequiredWorkflowsInput()
	response := make([]types.ResolvedFile, 0)
	for i, input := range inputRequiredWorkflows {
		_, repoDatabaseID, _ := input.RepoID.Decode()
		path := requiredworkflowutils.ConstructRequiredWorkflowPath(
			input.Path,
			repoDatabaseID)
		expectedSHA := fmt.Sprintf("resolved-commit-id-%d", i+1)
		if types.IsCommitSha(input.Ref) {
			expectedSHA = input.Ref
		}

		response = append(response, types.ResolvedFile{
			Path:          path,
			Ref:           input.Ref,
			IsTruncated:   false,
			Text:          fmt.Sprintf("resolved_file_contents_%d", i+1),
			SHA:           expectedSHA,
			RepositoryNwo: input.RepoNwo,
			RepositoryID:  input.RepoID,
		})
	}

	return response
}
