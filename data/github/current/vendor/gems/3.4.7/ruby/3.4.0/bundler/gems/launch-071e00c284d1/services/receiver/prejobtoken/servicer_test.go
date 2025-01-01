package prejobtoken

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"reflect"
	"testing"
	"time"

	"github.com/go-chi/chi"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/earthsmoke"
	"github.com/github/launch/clients/freno"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/clients/varz"
	"github.com/github/launch/constants"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/services/auth/hkdf"
	"github.com/github/launch/services/pb/deploy"
	tokenService "github.com/github/launch/services/pb/deploy/token"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild"
)

const (
	validWorkflowID                    = "c6138ef3-98fe-4a76-bd86-7c6045a3c141"
	validJobID                         = "fa5aabba-8868-4de2-aa56-0f0320489fe9"
	validWorkflowBuildDatabaseID int64 = 42
	validWorkflowRunID           int64 = 44
	timestamp                          = "2019-07-03T14:33:44Z"
	repoDatabaseID               int64 = 1234567
	validScope                         = "1234567" // RepoDatabaseID in string form
	integrationName                    = "GitHubCola"
	validJobName                       = "build"
	validIsHostedRunner                = true
)

var rawSignature = []byte("NewPhoneWhoDis")

type ServiceSuite struct {
	suite.Suite
	verifier            *hkdf.MockVerifier
	workflowbuildsRepo  *deployer.MockWorkflowBuildsRepository
	tokenService        *tokenService.MockLaunchTokenService
	deployerService     *deploy.MockLaunchDeploymentService
	kredzClient         *kredz.MockClient
	varzClient          *varz.MockClient
	earthsmokeDecryptor *earthsmoke.MockDecryptor
	servicer            *Servicer
	ghTwirpClient       *ghtwirp.MockClient
	frenoClient         *freno.MockClient
}

func TestServiceSuite(t *testing.T) {
	suite.Run(t, &ServiceSuite{})
}

func (s *ServiceSuite) SetupTest() {
	s.verifier = &hkdf.MockVerifier{}
	s.workflowbuildsRepo = &deployer.MockWorkflowBuildsRepository{}
	s.tokenService = &tokenService.MockLaunchTokenService{}
	s.deployerService = &deploy.MockLaunchDeploymentService{}
	s.kredzClient = &kredz.MockClient{}
	s.varzClient = &varz.MockClient{}
	s.earthsmokeDecryptor = &earthsmoke.MockDecryptor{}
	s.ghTwirpClient = &ghtwirp.MockClient{}
	s.frenoClient = &freno.MockClient{}

	s.servicer = NewServicer(
		observability.NewNullObservability(),
		logger.NullLogger(),
		statter.NullStatter(),
		s.verifier,
		s.workflowbuildsRepo,
		s.ghTwirpClient,
		s.tokenService,
		s.deployerService,
		"", false,
		s.kredzClient,
		s.varzClient,
		s.earthsmokeDecryptor,
		"",
		s.frenoClient,
		false,
	)
}

func (s *ServiceSuite) TearDownTest() {
	s.verifier.AssertExpectations(s.T())
	s.tokenService.AssertExpectations(s.T())
}

func (s *ServiceSuite) getHandleJobCreateRequest(workflowID, jobID, jobName, environmentName string, permissions map[string]string, isHostedRunner bool, productSku string) *http.Request {
	bodyContent, _ := json.Marshal(prejobRequest{
		BareJobName:     jobName,
		EnvironmentName: environmentName,
		Permissions:     permissions,
		IsHostedRunner:  isHostedRunner,
		ProductSKU:      productSku,
	})
	body := bytes.NewReader((bodyContent))

	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("workflowID", workflowID)
	rctx.URLParams.Add("jobID", jobID)

	url := fmt.Sprintf("/actions/build/%s/jobs/%s/pre_job_tokens?timestamp=%s", workflowID, jobID, url.QueryEscape(timestamp))
	req := httptest.NewRequest(http.MethodPost, url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	ctx := measurehttp.WithThresholdLogging(req.Context())
	req = req.WithContext(ctx)

	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func (s *ServiceSuite) getAuthorizationHeader() string {
	return fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString(rawSignature))
}

func (s *ServiceSuite) TestGetToken_MissingSignature() {
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", nil, validIsHostedRunner, "")
	req.Header.Del("Authorization")
	s.verifier.ExpectedCalls = []*mock.Call{}
	s.frenoClient.On("Check", mock.Anything, "pretendcollab").Return(&freno.CheckResponse{}, nil)

	s.servicer.HandleTokenCreate(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *ServiceSuite) TestGetToken_InvalidSignatureEncoding() {
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", nil, validIsHostedRunner, "")
	req.Header.Set("Authorization", "😱")

	s.servicer.HandleTokenCreate(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *ServiceSuite) TestGetToken_Success() {
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", nil, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		IsBillingChecked: true,
	}
	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}
	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.servicer.HandleTokenCreate(res, req)
	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)
	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
	s.Equal(true, tokenRes.UsageCaps.BillingChecked)
}

func (s *ServiceSuite) TestGetToken_SuccessWithProductSku() {
	validProductSku := "test_sku"
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", nil, validIsHostedRunner, validProductSku)

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		IsBillingChecked: true,
	}
	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
		ProductSku:     validProductSku,
	}
	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	s.servicer.HandleTokenCreate(res, req)
	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)
	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
	s.Equal(true, tokenRes.UsageCaps.BillingChecked)
}

func (s *ServiceSuite) TestGetTokenWithPermission_Success() {
	res := httptest.NewRecorder()
	permissions := map[string]string{"Checks": "read"}
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", permissions, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: permissions,
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID && reflect.DeepEqual(getReq.Permissions, permissions))
	})).Return(&tok, nil)

	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
}

func (s *ServiceSuite) TestGetTokenWithWorkflowRunPermissions_Success() {
	res := httptest.NewRecorder()
	permissions := map[string]string{"Checks": "read"}
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", permissions, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: permissions,
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", repoDatabaseID))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Dynamic,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()

	dynamicEvent := flowevents.DynamicEvent{
		IntegrationName: constants.CodespacesIntegrationName,
	}
	b, _ := json.Marshal(dynamicEvent)
	s.workflowbuildsRepo.On("GetWorkflowBuildPayload", mock.Anything, wfb.WorkflowBuildDatabaseID, mock.Anything).Return(b, nil)
	workflowRunPermissions := map[string]string{"codespaces_prebuild": string(tokens.WriteAccess)}

	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		validWorkflowRunPermissions := true
		validWorkflowRunPermissions = reflect.DeepEqual(getReq.WorkflowRunPermissions, workflowRunPermissions)

		return getReq.WorkflowId == validWorkflowID &&
			getReq.JobId == validJobID &&
			reflect.DeepEqual(getReq.Permissions, permissions) &&
			validWorkflowRunPermissions
	})).Return(&tok, nil)
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	s.ghTwirpClient.On("GetIntegrationJobSecrets",
		mock.Anything, dynamicEvent.IntegrationName, mock.Anything, mock.Anything,
		mock.Anything, mock.Anything, mock.Anything, &dynamicEvent,
	).Return(map[string]string{}, nil)

	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
}

func (s *ServiceSuite) TestGetTokenWithWorkflowRunPermissions_WithNonDynamicEvent() {
	res := httptest.NewRecorder()
	permissions := map[string]string{"Checks": "read"}
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", permissions, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: permissions,
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", repoDatabaseID))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Schedule,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()

	dynamicEvent := flowevents.DynamicEvent{
		IntegrationName: "something-else",
	}
	b, _ := json.Marshal(dynamicEvent)
	s.workflowbuildsRepo.On("GetWorkflowBuildPayload", mock.Anything, wfb.WorkflowBuildDatabaseID, mock.Anything).Return(b, nil)

	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		validWorkflowRunPermissions := true
		validWorkflowRunPermissions = len(getReq.WorkflowRunPermissions) == 0

		return getReq.WorkflowId == validWorkflowID &&
			getReq.JobId == validJobID &&
			reflect.DeepEqual(getReq.Permissions, permissions) &&
			validWorkflowRunPermissions
	})).Return(&tok, nil)
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	s.ghTwirpClient.On("GetIntegrationJobSecrets",
		mock.Anything, dynamicEvent.IntegrationName, mock.Anything, mock.Anything,
		mock.Anything, mock.Anything, mock.Anything, &dynamicEvent,
	).Return(map[string]string{}, nil)

	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
}
func (s *ServiceSuite) TestGetTokenWithWorkflowRunPermissions_WithNonCodespacesIntegration() {
	res := httptest.NewRecorder()
	permissions := map[string]string{"Checks": "read"}
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", permissions, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: permissions,
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", repoDatabaseID))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Dynamic,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()

	dynamicEvent := flowevents.DynamicEvent{
		IntegrationName: "something-else",
	}
	b, _ := json.Marshal(dynamicEvent)
	s.workflowbuildsRepo.On("GetWorkflowBuildPayload", mock.Anything, wfb.WorkflowBuildDatabaseID, mock.Anything).Return(b, nil)

	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		validWorkflowRunPermissions := true
		validWorkflowRunPermissions = len(getReq.WorkflowRunPermissions) == 0

		return getReq.WorkflowId == validWorkflowID &&
			getReq.JobId == validJobID &&
			reflect.DeepEqual(getReq.Permissions, permissions) &&
			validWorkflowRunPermissions
	})).Return(&tok, nil)
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	s.ghTwirpClient.On("GetIntegrationJobSecrets",
		mock.Anything, dynamicEvent.IntegrationName, mock.Anything, mock.Anything,
		mock.Anything, mock.Anything, mock.Anything, &dynamicEvent,
	).Return(map[string]string{}, nil)

	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
}

func (s *ServiceSuite) TestSpammyUser_NoUsage() {
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", nil, validIsHostedRunner, "")

	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsOwnerSpammy: true,
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	s.servicer.HandleTokenCreate(res, req)

	s.Equal(http.StatusNotFound, res.Code)
}

func (s *ServiceSuite) TestWithEnvironment_Success() {
	envName := "staging"
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, envName, nil, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", repoDatabaseID))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	securityDetailsResponse := &deploy.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:              true,
		AreActionsEnvironmentSecretsAllowed:   true,
		AreActionsEnvironmentVariablesAllowed: true,
	}
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(securityDetailsResponse, nil).Once()

	envID := types.GlobalID(testutils.EncodeGlobalID("Environment", 1234567))
	envNextID := types.GlobalID("next-env-id")

	env := &ghtwirp.Environment{
		GlobalID: envID,
	}
	s.ghTwirpClient.On("ResolveEnvironment", mock.Anything, envName, repoID).Return(env, nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

	envSecrets := map[string]string{
		"my_secret": "hello env",
	}

	secretsResponse := &kredz.ListSecretsResponse{
		Secrets: envSecrets,
	}

	encodedEnvVariable := base64.StdEncoding.EncodeToString([]byte("env_variable_value"))
	envVariables := map[string]string{
		"env_variable": encodedEnvVariable,
	}

	variablesResponse := &varz.ListVariablesResponse{
		Variables: envVariables,
	}

	s.kredzClient.On("ListSecretsForOwner", mock.Anything, mock.Anything, mock.Anything).Return(secretsResponse, nil)
	s.varzClient.On("ListVariablesForOwner", mock.Anything, mock.Anything, mock.Anything).Return(variablesResponse, nil)

	s.servicer.appRelayID = "secretsAppID"
	s.ghTwirpClient.On("GetNextGlobalID", mock.Anything, envID.String()).Return(envNextID, nil)
	s.ghTwirpClient.On("GetNextGlobalID", mock.Anything, "secretsAppID").Return(types.GlobalID("secretsAppNextID"), nil)
	s.earthsmokeDecryptor.On("DecryptSecretValue", mock.Anything, envSecrets["my_secret"], envNextID.String(), workflowbuild.ActionsSecretSource).Return(envSecrets["my_secret"], true, nil)

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
	s.Equal(1, len(tokenRes.Secrets))
	s.Equal(1, len(tokenRes.Variables))
	s.Equal("env_variable_value", tokenRes.Variables["env_variable"])
}

func (s *ServiceSuite) TestWithEnvironment_EnvironmentNotFound() {
	envName := "bogus-environment"
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, envName, nil, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	securityDetailsResponse := &deploy.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:              true,
		AreActionsEnvironmentSecretsAllowed:   true,
		AreActionsEnvironmentVariablesAllowed: true,
	}
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(securityDetailsResponse, nil).Once()

	s.ghTwirpClient.On("ResolveEnvironment", mock.Anything, envName, repoID).Return(nil, twirp.NotFoundError("environment not found"))

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	s.servicer.HandleTokenCreate(res, req)

	s.Equal(http.StatusNotFound, res.Code)
}

func (s *ServiceSuite) TestWithEnvironment_EnvSecretsNotAllowed() {
	envName := "staging"
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, envName, nil, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	securityDetailsResponse := &deploy.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:            true,
		AreActionsEnvironmentSecretsAllowed: false,
	}
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(securityDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	envID := types.GlobalID(testutils.EncodeGlobalID("Environment", 1234567))

	env := &ghtwirp.Environment{
		GlobalID: envID,
	}
	s.ghTwirpClient.On("ResolveEnvironment", mock.Anything, envName, repoID).Return(env, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
	s.Equal(0, len(tokenRes.Secrets))
}

func (s *ServiceSuite) TestIntegrationJobSecrets_Success() {
	envName := "staging"
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, envName, nil, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", repoDatabaseID))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	securityDetailsResponse := &deploy.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:            true,
		AreActionsEnvironmentSecretsAllowed: true,
	}
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(securityDetailsResponse, nil).Once()

	envID := types.GlobalID(testutils.EncodeGlobalID("Environment", 1234567))
	envNextID := types.GlobalID("env-next-id")

	env := &ghtwirp.Environment{
		GlobalID: envID,
	}
	s.ghTwirpClient.On("ResolveEnvironment", mock.Anything, envName, repoID).Return(env, nil)

	// As of December 2021, most dynamic workflows won't have access to Actions environment secrets,
	// but for better test coverage we'll test the combination of environment secrets and integration secrets here.
	envSecrets := map[string]string{
		"ENV_SECRET": "hello_encrypted",
	}

	secretsResponse := &kredz.ListSecretsResponse{
		Secrets: envSecrets,
	}

	s.kredzClient.On("ListSecretsForOwner", mock.Anything, mock.Anything, mock.Anything).Return(secretsResponse, nil)
	s.varzClient.On("ListVariablesForOwner", mock.Anything, mock.Anything, mock.Anything).Return(&varz.ListVariablesResponse{}, nil)

	s.servicer.appRelayID = "secretsAppID"
	s.ghTwirpClient.On("GetNextGlobalID", mock.Anything, envID.String()).Return(envNextID, nil)
	s.ghTwirpClient.On("GetNextGlobalID", mock.Anything, "secretsAppID").Return(types.GlobalID("secretsAppNextID"), nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.earthsmokeDecryptor.On("DecryptSecretValue", mock.Anything, "hello_encrypted", envNextID.String(), workflowbuild.ActionsSecretSource).Return("Hello env", true, nil)

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Dynamic,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()

	dynamicWorkflow := &flowevents.DynamicEvent{
		Ref:             "refs/heads/master",
		Workflow:        "name: some-workflow\n...",
		IntegrationName: integrationName,
		Inputs: map[string]string{
			"COLA_MIXIN": "cherry",
		},
		WorkflowName: "some-workflow",
		Slug:         "github_cola",
	}
	payload, _ := json.Marshal(dynamicWorkflow)
	s.workflowbuildsRepo.On("GetWorkflowBuildPayload", mock.Anything, validWorkflowBuildDatabaseID, mock.Anything).Return(payload, nil)

	integrationSecrets := map[string]string{
		"COLA_SECRET_FORMULA": "formula_encrypted",
	}
	s.ghTwirpClient.On("GetIntegrationJobSecrets", mock.Anything, integrationName, repoDatabaseID, validWorkflowRunID, validJobName, envName, validIsHostedRunner, dynamicWorkflow).Return(integrationSecrets, nil).Once()

	s.earthsmokeDecryptor.On("DecryptSecretValue", mock.Anything, "formula_encrypted", validScope, workflowbuild.ActionsSecretSource).Return("Mona's secret formula", true, nil)

	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)

	expectedSecrets := map[string]string{
		"ENV_SECRET":          "Hello env",
		"COLA_SECRET_FORMULA": "Mona's secret formula",
	}

	s.Equal(expectedSecrets, tokenRes.Secrets)
}

func (s *ServiceSuite) TestIntegrationJobSecrets_TwirpNotFoundError() {
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", nil, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", repoDatabaseID))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Dynamic,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()

	dynamicWorkflow := &flowevents.DynamicEvent{
		Ref:             "refs/heads/master",
		Workflow:        "name: some-workflow\n...",
		IntegrationName: integrationName,
		Inputs: map[string]string{
			"COLA_MIXIN": "cherry",
		},
		WorkflowName: "some-workflow",
		Slug:         "github_cola",
	}
	payload, _ := json.Marshal(dynamicWorkflow)
	s.workflowbuildsRepo.On("GetWorkflowBuildPayload", mock.Anything, validWorkflowBuildDatabaseID, mock.Anything).Return(payload, nil)

	s.ghTwirpClient.On("GetIntegrationJobSecrets", mock.Anything, integrationName, repoDatabaseID, validWorkflowRunID, validJobName, "", validIsHostedRunner, dynamicWorkflow).Return(nil, twirp.NotFoundError("workflow run not found")).Once()

	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusNotFound, res.Code)
}

func (s *ServiceSuite) TestIntegrationJobSecrets_TwirpInternalError() {
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", nil, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", repoDatabaseID))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Dynamic,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()

	dynamicWorkflow := &flowevents.DynamicEvent{
		Ref:             "refs/heads/master",
		Workflow:        "name: some-workflow\n...",
		IntegrationName: integrationName,
		Inputs: map[string]string{
			"COLA_MIXIN": "cherry",
		},
		WorkflowName: "some-workflow",
		Slug:         "github_cola",
	}
	payload, _ := json.Marshal(dynamicWorkflow)
	s.workflowbuildsRepo.On("GetWorkflowBuildPayload", mock.Anything, validWorkflowBuildDatabaseID, mock.Anything).Return(payload, nil)

	s.ghTwirpClient.On("GetIntegrationJobSecrets", mock.Anything, integrationName, repoDatabaseID, validWorkflowRunID, validJobName, "", validIsHostedRunner, dynamicWorkflow).Return(nil, twirp.InternalError("failed to encrypt integration secrets")).Once()

	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *ServiceSuite) TestSendIdToken_SecretsNotAllowed() {
	res := httptest.NewRecorder()
	permissions := map[string]string{"id_token": "write"}
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", permissions, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	securityDetailsResponse := &deploy.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:            false,
		AreActionsEnvironmentSecretsAllowed: false,
		IsIDTokenGenerationAllowed:          true,
	}
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(securityDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
	s.Equal(true, tokenRes.SendIDToken)
}

func (s *ServiceSuite) TestSendIdToken_NotRequested() {
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", nil, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	securityDetailsResponse := &deploy.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:            true,
		AreActionsEnvironmentSecretsAllowed: false,
		IsIDTokenGenerationAllowed:          true,
	}
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(securityDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
	s.Equal(false, tokenRes.SendIDToken)
}

func (s *ServiceSuite) TestSendIdToken_Allowed() {
	res := httptest.NewRecorder()
	permissions := map[string]string{"id_token": "write"}
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", permissions, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	securityDetailsResponse := &deploy.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:            true,
		AreActionsEnvironmentSecretsAllowed: false,
		IsIDTokenGenerationAllowed:          true,
	}
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(securityDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
	s.Equal(true, tokenRes.SendIDToken)
}

func (s *ServiceSuite) TestSendIdToken_WrongPermission() {
	res := httptest.NewRecorder()
	permissions := map[string]string{"id_token": "read"}
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, "", permissions, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	securityDetailsResponse := &deploy.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:            true,
		AreActionsEnvironmentSecretsAllowed: false,
		IsIDTokenGenerationAllowed:          false,
	}
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(securityDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
	s.Equal(false, tokenRes.SendIDToken)
}

func (s *ServiceSuite) TestSendIdToken_WithEnvironment() {
	envName := "staging"
	permissions := map[string]string{"id_token": "write"}
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, envName, permissions, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
		IsBillingChecked: false,
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	securityDetailsResponse := &deploy.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:              true,
		AreActionsEnvironmentSecretsAllowed:   true,
		AreActionsEnvironmentVariablesAllowed: true,
		IsIDTokenGenerationAllowed:            true,
	}
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(securityDetailsResponse, nil).Once()

	envID := types.GlobalID(testutils.EncodeGlobalID("Environment", 1234567))
	envNextID := types.GlobalID("env-next-id")

	env := &ghtwirp.Environment{
		GlobalID: envID,
	}
	s.ghTwirpClient.On("ResolveEnvironment", mock.Anything, envName, repoID).Return(env, nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

	envSecrets := map[string]string{
		"my_secret": "hello env",
	}

	secretsResponse := &kredz.ListSecretsResponse{
		Secrets: envSecrets,
	}

	encodedEnvVariable := base64.StdEncoding.EncodeToString([]byte("env_variable_value"))
	envVariables := map[string]string{
		"env_variable": encodedEnvVariable,
	}

	variablesResponse := &varz.ListVariablesResponse{
		Variables: envVariables,
	}

	s.kredzClient.On("ListSecretsForOwner", mock.Anything, mock.Anything, mock.Anything).Return(secretsResponse, nil)
	s.varzClient.On("ListVariablesForOwner", mock.Anything, mock.Anything, mock.Anything).Return(variablesResponse, nil)

	s.servicer.appRelayID = "secretsAppID"
	s.ghTwirpClient.On("GetNextGlobalID", mock.Anything, envID.String()).Return(envNextID, nil)
	s.ghTwirpClient.On("GetNextGlobalID", mock.Anything, "secretsAppID").Return(types.GlobalID("secretsAppNextID"), nil)
	s.earthsmokeDecryptor.On("DecryptSecretValue", mock.Anything, envSecrets["my_secret"], envNextID.String(), workflowbuild.ActionsSecretSource).Return(envSecrets["my_secret"], true, nil)

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
	s.Equal(false, tokenRes.UsageCaps.BillingChecked)
	s.Equal(1, len(tokenRes.Secrets))
	s.Equal(true, tokenRes.SendIDToken)
	s.Equal(1, len(tokenRes.Variables))
	s.Equal("env_variable_value", tokenRes.Variables["env_variable"])
}

func (s *ServiceSuite) TestFetchEnvironment_EnvNotFound() {
	envName := "test-env"
	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	reqStartTimestamp := time.Now().UTC()

	s.frenoClient.On("Check", mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)
	s.ghTwirpClient.On("ResolveEnvironment", mock.Anything, envName, repoID).Return(nil, twirp.NotFoundError("environment not found"))
	env, err := s.servicer.fetchEnvironment(context.Background(), envName, repoID, reqStartTimestamp)

	s.Nil(env)
	s.NotNil(err)
}

func (s *ServiceSuite) TestWithEnvironment_EnvVariablesNotAllowed() {
	envName := "staging"
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, envName, nil, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}

	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}

	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	securityDetailsResponse := &deploy.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:              true,
		AreActionsEnvironmentSecretsAllowed:   false,
		AreActionsEnvironmentVariablesAllowed: false,
	}
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(securityDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()
	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

	envID := types.GlobalID(testutils.EncodeGlobalID("Environment", 1234567))

	env := &ghtwirp.Environment{
		GlobalID: envID,
	}
	s.ghTwirpClient.On("ResolveEnvironment", mock.Anything, envName, repoID).Return(env, nil)

	s.servicer.HandleTokenCreate(res, req)

	var tokenRes ServiceResponse
	_ = json.NewDecoder(res.Body).Decode(&tokenRes)

	s.Equal(http.StatusCreated, res.Code)
	s.Equal(tok.Token, tokenRes.Token)
	s.Equal(tok.Permissions, tokenRes.Permissions)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(true, tokenRes.UsageCaps.CanRunJob)
	s.Equal(true, tokenRes.UsageCaps.CanCreateArtifact)
	s.Equal(0, len(tokenRes.Secrets))
	s.Equal(0, len(tokenRes.Variables))
}

func (s *ServiceSuite) TestGetWorkflowSecurityDetails_NotFound() {
	envName := "staging"
	res := httptest.NewRecorder()
	req := s.getHandleJobCreateRequest(validWorkflowID, validJobID, validJobName, envName, nil, validIsHostedRunner, "")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", repoDatabaseID))
	billingDetailsReq := &deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     validWorkflowID,
		JobID:          validJobID,
		IsHostedRunner: validIsHostedRunner,
	}
	billingDetailsResponse := &deploy.WorkflowBillingDetailsResponse{
		IsStorageAllowed: true,
		IsOwnerSpammy:    false,
		IsUsageAllowed:   true,
		RepositoryId:     types.IdentityFromGlobalID(repoID),
	}
	s.deployerService.On("GetWorkflowBillingDetails", mock.Anything, billingDetailsReq).Return(billingDetailsResponse, nil).Once()

	wfb := &deployer.DataForPrejobtoken{
		WorkflowBuildDatabaseID: validWorkflowBuildDatabaseID,
		WorkflowRunID:           validWorkflowRunID,
		Event:                   flowevents.Push,
	}
	s.workflowbuildsRepo.On("GetDataForPrejobtoken", mock.Anything, mock.Anything, mock.Anything).Return(wfb, true, nil).Once()

	s.frenoClient.On("Check", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&freno.CheckResponse{}, nil)

	tok := tokenService.GetTokenResponse{
		Token:       "abc123",
		Permissions: map[string]string{"Checks": "read"},
		ExpiresAt:   pbNow,
	}
	s.tokenService.On("GetToken", mock.Anything, mock.MatchedBy(func(getReq *tokenService.GetTokenRequest) bool {
		return (getReq.WorkflowId == validWorkflowID && getReq.JobId == validJobID)
	})).Return(&tok, nil)

	securityDetailsReq := &deploy.GetWorkflowSecurityDetailsRequest{
		WorkflowID: validWorkflowID,
	}
	twirpNotFoundErr := twirp.NotFoundError("Could not retrieve ForkPRWorkflowsPolicy and CanUseEnvironments from GraphQL")
	s.deployerService.On("GetWorkflowSecurityDetails", mock.Anything, securityDetailsReq).Return(nil, twirpNotFoundErr).Once()

	s.servicer.HandleTokenCreate(res, req)

	s.Equal(http.StatusNotFound, res.Code)
}
