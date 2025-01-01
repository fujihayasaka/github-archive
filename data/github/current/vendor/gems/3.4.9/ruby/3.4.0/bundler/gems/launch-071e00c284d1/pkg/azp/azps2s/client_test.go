package azps2s

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"fmt"
	"io"
	mrand "math/rand"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/pkg/launchhttp/httpmock"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/azp/config"
)

var testGlobalID = types.GlobalID("R_lAHNJr8DAw")
var testCreationResult = &azptypes.CreationResult{
	TenantID:                 "f81d4fae-7dec-11d0-a765-00a0c91e6bf6",
	TenantName:               "org",
	PipelineID:               1,
	ProjectName:              AZPDefaultProjectName,
	PipelinesScaleUnitID:     "01234567-89ab-cdef-0123-456789abcdef",
	ArtifactCacheScaleUnitID: "deadbeef-1234-5678-9abc-def012345678",
	RunnerScaleUnitID:        "f00dcafe-0bad-c0de-dead-beefcafe0001",
}
var testCreatOrganizationResultSucceeded = &createOrganizationResponse{
	OperationStatus: "succeeded",
	OperationURL:    "http://org.pls",
	PipelineID:      1,
	Organization: organization{
		Name: "org",
		ID:   "f81d4fae-7dec-11d0-a765-00a0c91e6bf6",
		Properties: map[string]hostInstance{
			PipelineScaleUnitType:      {"type", "01234567-89ab-cdef-0123-456789abcdef"},
			ArtifactCacheScaleUnitType: {"type", "deadbeef-1234-5678-9abc-def012345678"},
			RunnerScaleUnitType:        {"type", "f00dcafe-0bad-c0de-dead-beefcafe0001"},
		},
	},
}
var testCreatOrganizationResultInProgress = &createOrganizationResponse{
	OperationStatus: "inProgress",
	OperationURL:    "http://org.pls",
	PipelineID:      1,
	Organization: organization{
		Name: "org",
		ID:   "f81d4fae-7dec-11d0-a765-00a0c91e6bf6",
		Properties: map[string]hostInstance{
			PipelineScaleUnitType:      {"type", "01234567-89ab-cdef-0123-456789abcdef"},
			ArtifactCacheScaleUnitType: {"type", "deadbeef-1234-5678-9abc-def012345678"},
			RunnerScaleUnitType:        {"type", "f00dcafe-0bad-c0de-dead-beefcafe0001"},
		},
	},
}
var testCreatOrganizationResultUnexpected = &createOrganizationResponse{
	OperationStatus: "birdsarentreal",
}
var pollOperationResultCompleted = &OperationResult{Operation: &OperationResponse{Status: OperationSucceeded}}
var pollOperationResultCanceled = &OperationResult{Operation: &OperationResponse{Status: OperationCancelled}}

var defaultOptions = []Option{
	func(o *Options) {
		o.pollInitialInterval = 0
		o.pollMaxInterval = 0
		o.pollMultiplier = 0
	},
}

func TestClient_CreateTenantWithResources(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 32)
	require.NoError(t, err)

	type args struct {
		ctx           context.Context
		globalID      types.GlobalID
		ownerGlobalID types.GlobalID
		name          types.RepositoryFullName
		key           *rsa.PublicKey
		planSku       string
		createdAt     time.Time
	}

	defaultArgs := args{
		ctx:           context.TODO(),
		globalID:      testGlobalID,
		ownerGlobalID: testGlobalID,
		name:          types.RepositoryFullName{},
		key:           &key.PublicKey,
		planSku:       "",
		createdAt:     time.Time{},
	}

	type httpResponse struct {
		resp *http.Response
		err  error
	}

	defaultMock := func(m *httpmock.Client, _ *testing.T, create, _ *httpResponse) {
		m.EXPECT().Do(mock.Anything).Return(create.resp, create.err).Once()
	}
	defaultGhTwirpMock := func(m *ghtwirp.MockClient) {
		m.EXPECT().IsFeatureEnabledForActor(mock.Anything, github.PipelineRoundRobin, mock.Anything).Return(false)
	}

	tests := []struct {
		name                         string
		options                      []Option
		createResponse, pollResponse httpResponse
		mock                         func(m *httpmock.Client, t *testing.T, create, poll *httpResponse)
		mockGhTwirp                  func(m *ghtwirp.MockClient)
		args                         args
		want                         *azptypes.CreationResult
		wantErr                      bool
	}{
		{
			name:    "instant creation",
			options: defaultOptions,
			createResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testCreatOrganizationResultSucceeded, t)))},
			},
			args:        defaultArgs,
			mock:        defaultMock,
			mockGhTwirp: defaultGhTwirpMock,
			want:        testCreationResult,
			wantErr:     false,
		},
		{
			name:    "delayed creation",
			options: defaultOptions,
			createResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testCreatOrganizationResultInProgress, t)))},
			},
			pollResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&pollOperationResultCompleted, t)))},
			},
			args: defaultArgs,
			mock: func(m *httpmock.Client, _ *testing.T, create, poll *httpResponse) {
				m.EXPECT().Do(mock.Anything).Return(create.resp, create.err).Once()
				m.EXPECT().Do(mock.Anything).Return(poll.resp, poll.err)
			},
			mockGhTwirp: defaultGhTwirpMock,
			want:        testCreationResult,
			wantErr:     false,
		},
		{
			name:    "unexpected operation status",
			options: defaultOptions,
			createResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testCreatOrganizationResultUnexpected, t)))},
			},
			args:        defaultArgs,
			mock:        defaultMock,
			mockGhTwirp: defaultGhTwirpMock,
			wantErr:     true,
		},
		{
			name:    "cancelled operation",
			options: defaultOptions,
			createResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testCreatOrganizationResultInProgress.Application.ClientID, t)))},
			},
			pollResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&pollOperationResultCanceled, t)))},
			},
			args: defaultArgs,
			mock: func(m *httpmock.Client, _ *testing.T, create, poll *httpResponse) {
				m.EXPECT().Do(mock.Anything).Return(create.resp, create.err).Once()
				m.EXPECT().Do(mock.Anything).Return(poll.resp, poll.err)
			},
			mockGhTwirp: defaultGhTwirpMock,
			wantErr:     true,
		},
		{
			name:    "instant creation with pipeline round robin",
			options: defaultOptions,
			createResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testCreatOrganizationResultSucceeded, t)))},
			},
			args: defaultArgs,
			mock: defaultMock,
			mockGhTwirp: func(m *ghtwirp.MockClient) {
				m.EXPECT().IsFeatureEnabledForActor(mock.Anything, github.PipelineRoundRobin, mock.Anything).Return(true)
			},
			want:    testCreationResult,
			wantErr: false,
		},
		{
			name:    "delayed creation with pipeline round robin",
			options: defaultOptions,
			createResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testCreatOrganizationResultInProgress, t)))},
			},
			pollResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&pollOperationResultCompleted, t)))},
			},
			args: defaultArgs,
			mock: func(m *httpmock.Client, _ *testing.T, create, poll *httpResponse) {
				m.EXPECT().Do(mock.Anything).Return(create.resp, create.err).Once()
				m.EXPECT().Do(mock.Anything).Return(poll.resp, poll.err)
			},
			mockGhTwirp: func(m *ghtwirp.MockClient) {
				m.EXPECT().IsFeatureEnabledForActor(mock.Anything, github.PipelineRoundRobin, mock.Anything).Return(true)
			},
			want:    testCreationResult,
			wantErr: false,
		},
		{
			name:    "unexpected operation status with pipeline round robin",
			options: defaultOptions,
			createResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testCreatOrganizationResultUnexpected, t)))},
			},
			args: defaultArgs,
			mock: defaultMock,
			mockGhTwirp: func(m *ghtwirp.MockClient) {
				m.EXPECT().IsFeatureEnabledForActor(mock.Anything, github.PipelineRoundRobin, mock.Anything).Return(true)
			},
			wantErr: true,
		},
		{
			name:    "cancelled operation with pipeline round robin",
			options: defaultOptions,
			createResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testCreatOrganizationResultInProgress.Application.ClientID, t)))},
			},
			pollResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&pollOperationResultCanceled, t)))},
			},
			args: defaultArgs,
			mock: func(m *httpmock.Client, _ *testing.T, create, poll *httpResponse) {
				m.EXPECT().Do(mock.Anything).Return(create.resp, create.err).Once()
				m.EXPECT().Do(mock.Anything).Return(poll.resp, poll.err)
			},
			mockGhTwirp: func(m *ghtwirp.MockClient) {
				m.EXPECT().IsFeatureEnabledForActor(mock.Anything, github.PipelineRoundRobin, mock.Anything).Return(true)
			},
			wantErr: true,
		},
		{
			name:    "instant creation with plansku and createdAt timestamp",
			options: defaultOptions,
			createResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testCreatOrganizationResultSucceeded, t)))},
			},
			args: args{
				ctx:           context.TODO(),
				globalID:      testGlobalID,
				ownerGlobalID: testGlobalID,
				name:          types.RepositoryFullName{},
				key:           &key.PublicKey,
				planSku:       "pro",
				createdAt:     time.Now(),
			},
			mock:        defaultMock,
			mockGhTwirp: defaultGhTwirpMock,
			want:        testCreationResult,
			wantErr:     false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c, httpMock, ghTwirpMock := newClientWithMocks(t, tt.options...)
			tt.mock(httpMock, t, &tt.createResponse, &tt.pollResponse)
			tt.mockGhTwirp(ghTwirpMock)

			got, err := c.CreateTenantWithResources(tt.args.ctx, tt.args.globalID, tt.args.ownerGlobalID, tt.args.name, tt.args.key, tt.args.planSku, tt.args.createdAt)
			if (err != nil) != tt.wantErr {
				t.Errorf("Client.CreateTenantWithResources() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("Client.CreateTenantWithResources() = %v, want %v", got, tt.want)
			}
		})
	}
}

func newClientWithMocks(t *testing.T, options ...Option) (*Client, *httpmock.Client, *ghtwirp.MockClient) {
	var testClientOpts = func(o *httpclient.ClientOptions) {
		o.ReqRetryDelay = 1 * time.Millisecond
		o.ReqRetryMultiplier = 0.0
		o.ReqRetryRandFactor = 0.0
		o.ReqMaxRetries = 3
	}
	mockHTTP := httpmock.NewClient(t)
	mockGhTwirpClient := ghtwirp.NewMockClient(t)

	client, _ := New(
		httpclient.New(mockHTTP, testClientOpts),
		mockGhTwirpClient,
		config.AzureProviderConfig{},
		options...,
	)
	return client, mockHTTP, mockGhTwirpClient
}

func toBytes(v any, t *testing.T) []byte {
	e, err := json.Marshal(&v)
	if err != nil {
		t.Fatal(errors.Wrap(err, "expected no error"))
	}
	return e
}

func Test_TenantNameIsNotReused(t *testing.T) {
	handler := func() http.HandlerFunc {
		previousTenantName := ""
		return func(w http.ResponseWriter, r *http.Request) {
			bs, err := io.ReadAll(r.Body)
			require.NoError(t, err)

			var req *requestBody
			err = json.Unmarshal(bs, &req)
			require.NoError(t, err)

			currentTenantName := req.Organization.Name
			require.NotEmpty(t, currentTenantName)

			if previousTenantName != "" {
				require.NotEqual(t, currentTenantName, previousTenantName)
			} else {
				previousTenantName = currentTenantName
				http.Error(w, "do it again", 503)
				return
			}

			json.NewEncoder(w).Encode(testCreatOrganizationResultSucceeded)
		}
	}()

	ts := httptest.NewServer(handler)

	var testClientOpts = func(o *httpclient.ClientOptions) {
		o.ReqRetryDelay = 1 * time.Millisecond
		o.ReqRetryMultiplier = 0.1
		o.ReqRetryRandFactor = 0.1
		o.ReqMaxRetries = 3
	}

	mockGhTwirpClient := ghtwirp.NewMockClient(t)
	mockGhTwirpClient.EXPECT().IsFeatureEnabledForActor(mock.Anything, github.PipelineRoundRobin, mock.Anything).Return(false)

	client, _ := New(
		httpclient.New(ts.Client(), testClientOpts),
		mockGhTwirpClient,
		config.AzureProviderConfig{
			OrgCreateBaseURL: ts.URL,
		},
		defaultOptions...,
	)

	key, err := rsa.GenerateKey(rand.Reader, 32)
	require.NoError(t, err)

	res, err := client.CreateTenantWithResources(context.Background(), testGlobalID, testGlobalID, types.RepositoryFullName{}, &key.PublicKey, "", time.Time{})
	require.NoError(t, err)
	require.NotNil(t, res)
}

func Test_PipeLineURLNotReused(t *testing.T) {
	handler := func() http.HandlerFunc {
		previousUrl := ""
		return func(w http.ResponseWriter, r *http.Request) {
			currentUrl := r.Host
			require.NotEmpty(t, currentUrl)

			if previousUrl != "" {
				require.NotEqual(t, currentUrl, previousUrl)
			} else {
				previousUrl = currentUrl
				http.Error(w, "do it again", 503)
				return
			}

			json.NewEncoder(w).Encode(testCreatOrganizationResultSucceeded)
		}
	}()

	ts1 := httptest.NewServer(handler)
	ts2 := httptest.NewServer(handler)

	var testClientOpts = func(o *httpclient.ClientOptions) {
		o.ReqRetryDelay = 1 * time.Millisecond
		o.ReqRetryMultiplier = 0.1
		o.ReqRetryRandFactor = 0.1
		o.ReqMaxRetries = 3
	}

	mockGhTwirpClient := ghtwirp.NewMockClient(t)
	mockGhTwirpClient.EXPECT().IsFeatureEnabledForActor(mock.Anything, github.PipelineRoundRobin, mock.Anything).Return(true)

	client, _ := New(
		httpclient.New(ts1.Client(), testClientOpts),
		mockGhTwirpClient,
		config.AzureProviderConfig{
			OrgCreateBaseURL: ts1.URL,
			PipelineBaseUrls: fmt.Sprintf("%s\n%s", ts1.URL, ts2.URL),
		},
		defaultOptions...,
	)
	client.rand = mrand.New(mrand.NewSource(3))

	key, err := rsa.GenerateKey(rand.Reader, 32)
	require.NoError(t, err)

	res, err := client.CreateTenantWithResources(context.Background(), testGlobalID, testGlobalID, types.RepositoryFullName{}, &key.PublicKey, "", time.Time{})
	require.NoError(t, err)
	require.NotNil(t, res)
}
