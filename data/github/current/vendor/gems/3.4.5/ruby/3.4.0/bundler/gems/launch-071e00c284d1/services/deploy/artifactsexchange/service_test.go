package artifactsexchange

import (
	"context"
	"errors"
	fmt "fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	timestamp "github.com/golang/protobuf/ptypes/timestamp"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/azp/azpclient"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild/azp/azperrors"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/azp/config"
)

var (
	testRepoID       = types.GlobalID(testutils.EncodeGlobalID("Repository", 1))
	archivedRepoID   = types.GlobalID(testutils.EncodeGlobalID("Repository", 2))
	testCheckSuiteID = types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 1))
	defaultTime      = time.Date(2000, 1, 1, 10, 0, 0, 1, time.UTC)
)

func newMockResourcesRepository(result azptypes.CreationResult) *deployer.MockAzpResourcesRepository {
	repo := &deployer.MockAzpResourcesRepository{}

	repo.On(
		"TryGet",
		mock.Anything,
		nil,
	).Return(
		nil,
		errors.New("missing resource"),
	)
	repo.On(
		"TryGet",
		mock.Anything,
		testRepoID,
	).Return(
		&azptypes.BackingResources{
			CreationResult: result,
			Environment:    "test",
		},
		nil,
	)
	repo.On(
		"TryGet",
		mock.Anything,
		archivedRepoID,
	).Return(
		nil,
		deployer.NewGetAzpResourcesError(archivedRepoID),
	)

	return repo
}

func newMockWorkflowBuildsRepository(externalBuildID string) *deployer.MockWorkflowBuildsRepository {
	repo := &deployer.MockWorkflowBuildsRepository{}
	repo.On(
		"GetWorkflowBuildStateByCheckSuiteID",
		mock.Anything,
		testCheckSuiteID,
	).Return(
		&deployer.WorkflowBuildState{
			RepositoryID:    testRepoID,
			ExternalBuildID: externalBuildID,
		},
		true,
		nil,
	)

	return repo
}

func TestExchangeURLAlternate(t *testing.T) {
	server, teardown := setup(func(mux *http.ServeMux) {
		mux.HandleFunc("/test-org/test-project/_apis/Pipelines/1/runs/1/logs/1", func(w http.ResponseWriter, r *http.Request) {
			blob := `{
      "createdOn": "2019-06-12T23:39:15.8Z",
      "id": 1,
      "lastChangedOn": "2019-06-12T23:39:16.037Z",
      "lineCount": 122,
      "signedContent": {
        "url": "https://test.azure.com/test-org/test-project/_apis/Pipelines/1/runs/1/signedLogContent/1?urlExpires=2019-06-14T23%3A16%3A12.5640115Z&urlSigningMethod=HMACV1&urlSignature=UCor93VCO53rNCyD3AQ0zS61mvemTafcN8x%2FLG3pR%2Bc%3D",
        "signatureExpires": "2019-06-14T23:29:53.9317121Z"
      },
      "url": "https://dev.azure.com/test-org/test-project/_apis/Pipelines/1/runs/1/logs/1"
    }`

			w.Write([]byte(blob)) // nolint: errcheck
		})
	})
	defer teardown()

	resourcesRepo := newMockResourcesRepository(azptypes.CreationResult{
		TenantName: "test-org",
	})

	wbRepo := newMockWorkflowBuildsRepository("1")

	repoClient := newClient(server.URL)
	factory := azp.NewMockRepositoryClientFactory(t)
	factory.On("ClientFromResources", mock.Anything, mock.Anything).Return(repoClient)

	svc := New(
		logger.TestLogger(),
		statter.NullStatter(),
		factory,
		resourcesRepo,
		wbRepo,
	)

	requestURL := server.URL + "/test-org/test-project/_apis/Pipelines/1/runs/1/logs/1?$expand=SignedContent"
	want := &ExchangeURLResponse{
		AuthenticatedUrl: "https://test.azure.com/test-org/test-project/_apis/Pipelines/1/runs/1/signedLogContent/1?urlExpires=2019-06-14T23%3A16%3A12.5640115Z&urlSigningMethod=HMACV1&urlSignature=UCor93VCO53rNCyD3AQ0zS61mvemTafcN8x%2FLG3pR%2Bc%3D",
		ExpiresAt:        newTimestampFromString(t, "2019-06-14T23:29:53.9317121Z"),
	}
	res, err := svc.ExchangeURL(context.Background(), &ExchangeURLRequest{
		UnauthenticatedUrl: requestURL,
		RepositoryId:       types.IdentityFromGlobalID(testRepoID),
	})
	require.NoError(t, err)

	assert.Equal(t, res, want)
}

func TestExchangeURL(t *testing.T) {
	defaultTimeProto := timestamppb.New(defaultTime)

	tests := []struct {
		desc        string
		setup       func() *Service
		req         *ExchangeURLRequest
		want        *ExchangeURLResponse
		errExpected bool
	}{
		{
			desc:  "returns an authenticated url for a valid request",
			setup: defaultSetupFunc,
			req: &ExchangeURLRequest{
				UnauthenticatedUrl: "http://test-url.com",
				RepositoryId:       types.IdentityFromGlobalID(testRepoID),
			},
			want: &ExchangeURLResponse{
				AuthenticatedUrl: "http://test-authenticated-url.com",
				ExpiresAt:        defaultTimeProto,
			},
			errExpected: false,
		},
		{
			desc:        "returns an error when request is missing",
			setup:       defaultSetupFunc,
			req:         nil,
			want:        nil,
			errExpected: true,
		},
		{
			desc:  "returns an error when a blank url is provided",
			setup: defaultSetupFunc,
			req: &ExchangeURLRequest{
				UnauthenticatedUrl: "",
				RepositoryId:       types.IdentityFromGlobalID(testRepoID),
			},
			want:        nil,
			errExpected: true,
		},
		{
			desc:  "returns an error when repository id is missing",
			setup: defaultSetupFunc,
			req: &ExchangeURLRequest{
				UnauthenticatedUrl: "http://test-url.com",
				RepositoryId:       nil,
			},
			want:        nil,
			errExpected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			svc := tt.setup()
			got, err := svc.ExchangeURL(context.Background(), tt.req)
			if tt.errExpected {
				assert.Error(t, err)
			} else {
				require.NoError(t, err)
			}

			assert.Equal(t, tt.want, got, "response should match expected value")
		})
	}
}

func TestExchangeURLAZPErrorReporting(t *testing.T) {
	setupFunc := func(log *logger.MockLogger, status int, exceptionType, message string) *Service {
		result := azptypes.CreationResult{
			TenantName: "test-org",
		}
		resourcesRepo := &deployer.MockAzpResourcesRepository{}
		resourcesRepo.On(
			"TryGet",
			mock.Anything,
			testRepoID,
		).Return(
			&azptypes.BackingResources{
				CreationResult: result,
				Environment:    "test",
			},
			nil,
		)

		rc := &azp.MockRepositoryClient{}
		rc.On(
			"GetAuthenticatedURL", mock.Anything, "http://test-url.com",
		).Return(
			nil,
			&azperrors.AZPError{
				StatusCode:    status,
				ExceptionType: exceptionType,
				Message:       message,
			},
		)

		azpClientFactory := &azp.MockRepositoryClientFactory{}
		azpClientFactory.On("ClientFromResources", mock.Anything, mock.Anything).Return(
			rc, nil,
		)

		wbRepo := &deployer.MockWorkflowBuildsRepository{}

		svc := New(
			log,
			statter.NullStatter(),
			azpClientFactory,
			resourcesRepo,
			wbRepo,
		)

		return svc
	}

	tests := []struct {
		desc                        string
		setup                       func(*logger.MockLogger, int, string, string) *Service
		mockLog                     *logger.MockLogger
		status                      int
		exceptionType               string
		exceptionMessage            string
		req                         *ExchangeURLRequest
		expectedNumberOfReportCalls int
	}{
		{
			desc:             "does not report RunNotFound AZP Errors to Sentry",
			setup:            setupFunc,
			mockLog:          logger.NewMockLogger(t),
			status:           404,
			exceptionType:    azperrors.RunNotFoundException,
			exceptionMessage: "A run with id 8729 was not found.",
			req: &ExchangeURLRequest{
				UnauthenticatedUrl: "http://test-url.com",
				RepositoryId:       types.IdentityFromGlobalID(testRepoID),
			},
			expectedNumberOfReportCalls: 0,
		},
		{
			desc:             "reports generic AZP Errors to Sentry",
			setup:            setupFunc,
			mockLog:          logger.NewMockLogger(t),
			status:           404,
			exceptionType:    azperrors.Exception,
			exceptionMessage: "This is a generic exception",
			req: &ExchangeURLRequest{
				UnauthenticatedUrl: "http://test-url.com",
				RepositoryId:       types.IdentityFromGlobalID(testRepoID),
			},
			expectedNumberOfReportCalls: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			if tt.expectedNumberOfReportCalls > 0 {
				tt.mockLog.On("Report", mock.Anything, mock.Anything).Times(tt.expectedNumberOfReportCalls)
			}
			svc := tt.setup(tt.mockLog, tt.status, tt.exceptionType, tt.exceptionMessage)

			got, err := svc.ExchangeURL(context.Background(), tt.req)
			assert.Nil(t, got)
			assert.NotNil(t, err)
			assert.Equal(t, len(tt.mockLog.Calls), tt.expectedNumberOfReportCalls)
			tt.mockLog.AssertExpectations(t)
		})
	}
}

func TestDeleteArtifact(t *testing.T) {
	tests := []struct {
		desc               string
		errExpected        bool
		artifactName       string
		externalBuildID    string
		checkSuiteID       *pbtypes.Identity
		repositoryID       *pbtypes.Identity
		executionID        string
		skipFactoryMocking bool
	}{
		{
			desc:            "returns empty response for deleting an artifact that exists",
			artifactName:    "test-artifact",
			externalBuildID: "1",
			checkSuiteID:    types.IdentityFromGlobalID(testCheckSuiteID),
			errExpected:     false,
		},
		{
			desc:            "deletes artifact with space in name",
			artifactName:    "test artifact",
			externalBuildID: "1",
			checkSuiteID:    types.IdentityFromGlobalID(testCheckSuiteID),
			errExpected:     false,
		},
		{
			desc:            "deletes artifact with emoji in name",
			artifactName:    "artifact📦",
			externalBuildID: "1",
			checkSuiteID:    types.IdentityFromGlobalID(testCheckSuiteID),
			errExpected:     false,
		},
		{
			desc:            "returns error when artifact name is missing",
			artifactName:    "",
			externalBuildID: "1",
			checkSuiteID:    types.IdentityFromGlobalID(testCheckSuiteID),
			errExpected:     true,
		},
		{
			desc:               "returns error when check suite is nil",
			artifactName:       "test-artifact",
			externalBuildID:    "1",
			checkSuiteID:       nil,
			errExpected:        true,
			skipFactoryMocking: true,
		},
		{
			desc:            "deletes artifact by externalbuildID",
			artifactName:    "artifact",
			externalBuildID: "1",
			checkSuiteID:    types.IdentityFromGlobalID(testCheckSuiteID),
			repositoryID:    types.IdentityFromGlobalID(testRepoID),
			errExpected:     false,
		},
		{
			desc:         "deletes artifact by executionID",
			artifactName: "artifact",
			repositoryID: types.IdentityFromGlobalID(testRepoID),
			executionID:  "test-guid",
			errExpected:  false,
		},
		{
			desc:         "deletes artifact with name having escape characters",
			artifactName: "artifact / test",
			repositoryID: types.IdentityFromGlobalID(testRepoID),
			executionID:  "test-guid",
			errExpected:  false,
		},
		{
			desc:         "deletes mulitple artifacts by executionID when artifactName is missing",
			repositoryID: types.IdentityFromGlobalID(testRepoID),
			executionID:  "test-guid",
			errExpected:  false,
		},
		{
			desc:               "does not delete artifact or error if azp_resources are archived (repository was deleted)",
			repositoryID:       types.IdentityFromGlobalID(archivedRepoID),
			executionID:        "test-guid",
			errExpected:        false,
			skipFactoryMocking: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			server, teardown := setup(func(mux *http.ServeMux) {
				route1 := fmt.Sprintf("/test-org/test-project/_apis/pipelines/1/runs/%s/artifacts", tt.externalBuildID)
				mux.HandleFunc(route1, func(w http.ResponseWriter, r *http.Request) {
					artifactName := r.URL.Query().Get("artifactName")
					if r.Method != http.MethodDelete || artifactName == "" {
						w.WriteHeader(http.StatusBadRequest)
						return
					}

					assert.Equal(t, tt.artifactName, artifactName)
					w.WriteHeader(http.StatusNoContent)
				})

				route2 := fmt.Sprintf("/test-org/_apis/pipelines/plans/%s/artifacts", tt.executionID)
				mux.HandleFunc(route2, func(w http.ResponseWriter, r *http.Request) {
					if r.Method != http.MethodDelete {
						w.WriteHeader(http.StatusBadRequest)
						return
					}
					w.WriteHeader(http.StatusNoContent)
				})
			})
			defer teardown()

			resourceRepo := newMockResourcesRepository(azptypes.CreationResult{
				TenantName:  "test-org",
				ProjectName: "test-project",
				PipelineID:  1,
			})

			wbRepo := newMockWorkflowBuildsRepository(tt.externalBuildID)

			repoClient := newClient(server.URL)
			factory := azp.NewMockRepositoryClientFactory(t)

			if !tt.skipFactoryMocking {
				factory.On("ClientFromResources", mock.Anything, mock.Anything).Return(repoClient)
			}

			svc := New(
				logger.TestLogger(),
				statter.NullStatter(),
				factory,
				resourceRepo,
				wbRepo,
			)

			_, err := svc.DeleteArtifact(context.Background(), &DeleteArtifactRequest{
				CheckSuiteId: tt.checkSuiteID,
				ArtifactName: tt.artifactName,
				RepositoryId: tt.repositoryID,
				ExecutionId:  tt.executionID,
			})
			if tt.errExpected {
				assert.Error(t, err)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestDeleteBuildLogs(t *testing.T) {
	tests := []struct {
		desc               string
		errExpected        bool
		repositoryID       *pbtypes.Identity
		checkSuiteID       *pbtypes.Identity
		executionID        string
		skipFactoryMocking bool
	}{
		{
			desc:         "returns empty response for deleting logs that exist using only checkSuiteID",
			errExpected:  false,
			checkSuiteID: types.IdentityFromGlobalID(testCheckSuiteID),
		},
		{
			desc:         "returns empty if azp_resources are archived (repository was deleted)",
			errExpected:  false,
			repositoryID: types.IdentityFromGlobalID(archivedRepoID),
			checkSuiteID: types.IdentityFromGlobalID(testCheckSuiteID),
		},
		{
			desc:               "returns empty response for deleting logs that exist using executionID if repository was deleted",
			errExpected:        false,
			repositoryID:       types.IdentityFromGlobalID(archivedRepoID),
			checkSuiteID:       types.IdentityFromGlobalID(testCheckSuiteID),
			executionID:        "test-guid",
			skipFactoryMocking: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			externalBuildID := "1"
			if tt.executionID != "" {
				externalBuildID = tt.executionID
			}

			server, teardown := setup(func(mux *http.ServeMux) {
				route := fmt.Sprintf("/test-org/_apis/pipelines/plans/%v/logs", externalBuildID)
				mux.HandleFunc(route, func(w http.ResponseWriter, r *http.Request) {
					if r.Method != http.MethodDelete {
						w.WriteHeader(http.StatusBadRequest)
						return
					}

					apiVersion := r.URL.Query().Get("api-version")
					assert.Equal(t, "6.0-preview", apiVersion)

					w.WriteHeader(http.StatusNoContent)
				})
			})
			defer teardown()

			resourceRepo := newMockResourcesRepository(azptypes.CreationResult{
				TenantName:  "test-org",
				ProjectName: "test-project",
				PipelineID:  1,
			})
			wbRepo := newMockWorkflowBuildsRepository(externalBuildID)

			repoClient := newClient(server.URL)
			factory := azp.NewMockRepositoryClientFactory(t)
			if !tt.skipFactoryMocking {
				factory.On("ClientFromResources", mock.Anything, mock.Anything).Return(repoClient)
			}

			svc := New(
				logger.TestLogger(),
				statter.NullStatter(),
				factory,
				resourceRepo,
				wbRepo,
			)

			_, err := svc.DeleteBuildLogs(context.Background(), &DeleteBuildLogsRequest{
				CheckSuiteId: tt.checkSuiteID,
				RepositoryId: tt.repositoryID,
				ExecutionId:  tt.executionID,
			})

			if tt.errExpected {
				assert.Error(t, err)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestDeleteBuildLogsNeverQueued(t *testing.T) {
	resourceRepo := newMockResourcesRepository(azptypes.CreationResult{
		TenantName:  "test-org",
		ProjectName: "test-project",
		PipelineID:  1,
	})

	wbRepo := newMockWorkflowBuildsRepository("")

	factory := azp.NewMockRepositoryClientFactory(t)

	svc := New(
		logger.TestLogger(),
		statter.NullStatter(),
		factory,
		resourceRepo,
		wbRepo,
	)

	_, err := svc.DeleteBuildLogs(context.Background(), &DeleteBuildLogsRequest{
		CheckSuiteId: types.IdentityFromGlobalID(testCheckSuiteID),
	})
	require.NoError(t, err)
}

func TestDeleteBuildLogsNotFound(t *testing.T) {
	externalBuildID := "1"

	server, teardown := setup(func(mux *http.ServeMux) {
		route := fmt.Sprintf("/test-org/test-project/_apis/pipelines/1/runs/%v/logs", externalBuildID)
		mux.HandleFunc(route, func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodDelete {
				w.WriteHeader(http.StatusBadRequest)
				return
			}

			apiVersion := r.URL.Query().Get("api-version")
			assert.Equal(t, "5.1-preview", apiVersion)

			w.WriteHeader(http.StatusNotFound)
		})
	})
	defer teardown()

	resourceRepo := newMockResourcesRepository(azptypes.CreationResult{
		TenantName:  "test-org",
		ProjectName: "test-project",
		PipelineID:  1,
	})

	wbRepo := newMockWorkflowBuildsRepository(externalBuildID)

	repoClient := newClient(server.URL)
	factory := azp.NewMockRepositoryClientFactory(t)
	factory.On("ClientFromResources", mock.Anything, mock.Anything).Return(repoClient)

	svc := New(
		logger.TestLogger(),
		statter.NullStatter(),
		factory,
		resourceRepo,
		wbRepo,
	)

	_, err := svc.DeleteBuildLogs(context.Background(), &DeleteBuildLogsRequest{
		CheckSuiteId: types.IdentityFromGlobalID(testCheckSuiteID),
	})
	require.NoError(t, err)
}

func setup(config func(*http.ServeMux)) (*httptest.Server, func()) {
	mux := http.NewServeMux()
	config(mux)
	server := httptest.NewServer(mux)

	return server, func() {
		server.Close()
	}
}

func defaultSetupFunc() *Service {
	result := azptypes.CreationResult{
		TenantName: "test-org",
	}

	resourcesRepo := &deployer.MockAzpResourcesRepository{}
	resourcesRepo.On(
		"TryGet",
		mock.Anything,
		testRepoID,
	).Return(
		&azptypes.BackingResources{
			CreationResult: result,
			Environment:    "test",
		},
		nil,
	)

	rc := &azp.MockRepositoryClient{}
	rc.On(
		"GetAuthenticatedURL", mock.Anything, "http://test-url.com",
	).Return(
		&azp.GetAuthenticatedURLResponse{
			SignedContent: &azp.SignedContent{
				URL:              "http://test-authenticated-url.com",
				SignatureExpires: defaultTime,
			},
		}, nil,
	)
	azpClientFactory := &azp.MockRepositoryClientFactory{}

	wbRepo := &deployer.MockWorkflowBuildsRepository{}

	azpClientFactory.On("ClientFromResources", mock.Anything, mock.Anything).Return(
		rc, nil,
	)
	svc := New(
		logger.TestLogger(),
		statter.NullStatter(),
		azpClientFactory,
		resourcesRepo,
		wbRepo,
	)

	return svc
}

func newTimestampFromString(t *testing.T, str string) *timestamp.Timestamp {
	time, err := time.Parse(time.RFC3339, str)
	require.NoError(t, err)
	stamp := timestamppb.New(time)
	require.NoError(t, err)
	return stamp
}

var testResources = &azptypes.BackingResources{
	Environment: "testEnvironment",
	CreationResult: azptypes.CreationResult{
		TenantName:  "test-org",
		ProjectName: "test-project",
		PipelineID:  1,
	},
}

func newClient(url string) azp.RepositoryClient {
	var testClientOpts = func(o *httpclient.ClientOptions) {
		o.ReqRetryDelay = 1 * time.Millisecond
		o.ReqRetryMultiplier = 0.0
		o.ReqRetryRandFactor = 0.0
		o.ReqMaxRetries = 3
	}
	ghTwirpMock := &ghtwirp.MockClient{}
	ghTwirpMock.On("IsFeatureEnabledForActor", mock.Anything, github.ConstructScaleUnitURL, mock.Anything).Return(true)
	ghTwirpMock.On("IsFeatureEnabledForActor", mock.Anything, github.PlumbRunnerHostURL, mock.Anything).Return(true)
	obsMock, log, _ := observability.NewMockedObservability()
	log.On("Log", context.TODO(), mock.Anything, mock.Anything, mock.Anything).Return()
	return azpclient.New(
		context.TODO(),
		httpclient.New(apphttp.NewClient(apphttp.WithIgnoreRedirects()), testClientOpts),
		ghTwirpMock,
		obsMock,
		config.AzureProviderConfig{
			RepoAPIsBaseURL:         url,
			RunnerServiceBaseURL:    url,
			ExternalRepoAPIsBaseURL: url,
		},
		testResources,
		azpclient.WithTokenSource(&fakeTokenSource{}),
	)
}

type fakeTokenSource struct{}

func (f *fakeTokenSource) Get(context.Context) (string, error) {
	return "fakeToken", nil
}
