package refactortests

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/azp/azpclient"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/azp/config"
)

type httpResponse struct {
	code   int
	body   string
	header map[string]string
}

type httpRequest struct {
	header map[string]string
	body   string
	uri    string
	method string
}

func assertReq(t *testing.T, want httpRequest, req *http.Request) {
	if !(req.Method == http.MethodGet || req.Method == http.MethodDelete) {
		c := req.Header.Get("Content-Type")
		require.NotEmpty(t, c)
	}
	require.Contains(t, req.URL.RequestURI(), want.uri)
	require.Equal(t, want.method, req.Method)
	for wantK, wantV := range want.header {
		gotV := req.Header.Get(wantK)
		require.NotEmpty(t, gotV, fmt.Sprintf("expected value for key %s", wantK))
		require.Contains(t, gotV, wantV)
	}
	if want.body != "" {
		body, err := io.ReadAll(req.Body)
		require.NoError(t, err)
		require.Equal(t, want.body, string(body))
	}
}

type fakeTokenSource struct{}

const DefaultToken = "fakeToken"

func (f *fakeTokenSource) Get(context.Context) (string, error) {
	return DefaultToken, nil
}

func toBytes(v any, t *testing.T) []byte {
	e, err := json.Marshal(&v)
	if err != nil {
		t.Fatal(errors.Wrap(err, "expected no error"))
	}
	return e
}

var testResources = &azptypes.BackingResources{
	Environment: "testEnvironment",
	CreationResult: azptypes.CreationResult{
		TenantName:  "testTenant",
		ProjectName: "testProject",
	},
}

func newClientWithFlags(url string, flags map[string]bool) azp.RepositoryClient {
	var testClientOpts = func(o *httpclient.ClientOptions) {
		o.ReqRetryDelay = 1 * time.Millisecond
		o.ReqRetryMultiplier = 0.0
		o.ReqRetryRandFactor = 0.0
		o.ReqMaxRetries = 3
	}
	ghTwirpMock := &ghtwirp.MockClient{}
	for flag, enabled := range flags {
		ghTwirpMock.EXPECT().IsFeatureEnabledForActor(mock.Anything, flag, mock.Anything).Return(enabled)
	}

	obsMock, log, _ := observability.NewMockedObservability()
	log.EXPECT().Log(context.TODO(), mock.Anything, mock.Anything, mock.Anything).Return()

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

func newClient(url string) azp.RepositoryClient {
	return newClientWithFlags(url, map[string]bool{
		github.ConstructScaleUnitURL: true,
		github.PlumbRunnerHostURL:    true,
	})
}
