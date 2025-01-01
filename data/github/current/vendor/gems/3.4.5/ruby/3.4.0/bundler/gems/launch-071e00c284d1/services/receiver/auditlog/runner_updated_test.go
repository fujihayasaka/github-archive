package auditlog

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/auth"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	auditLog "github.com/github/launch/hydro/schemas/audit_log/v2"
	entities "github.com/github/launch/hydro/schemas/audit_log/v2/entities"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/testutils"
)

func TestRunnerUpdated(t *testing.T) {
	suite.Run(t, new(runnerUpdatedTestSuite))
}

type runnerUpdatedTestSuite struct {
	suite.Suite
	svc *Service

	hydro          *events.MockHydro
	azpResources   deployer.MockAzpResourcesLoader
	keyVaultClient *azp.MockKeyVaultClient
	verifier       *auth.MockVerifier
	twirpClient    *ghtwirp.MockClient
}

var (
	tenantID                  = "a-tenant-id"
	runnerTenantID            = "b-tenant-id"
	authVaultName             = "some vault name"
	primaryHMACKey            = []byte("primary secret key")
	secondaryHMACKey          = []byte("secondary secret key")
	repoDbID            int64 = 123
	repoName                  = "a-repo"
	repoGlobalID              = types.GlobalID(testutils.EncodeGlobalID("Repository", repoDbID))
	userDbID            int64 = 777
	userName                  = "a-user"
	orgDbID             int64 = 456
	orgName                   = "an-org"
	orgGlobalID               = types.GlobalID(testutils.EncodeGlobalID("Organization", orgDbID))
	enterpriseDbID      int64 = 789
	enterpriseName            = "an-enterprise"
	enterpriseGlobalID        = types.GlobalID(testutils.EncodeGlobalID("Enterprise", enterpriseDbID))
	exampleRunnerUpdate       = runnerUpdate{
		TenantID:        tenantID,
		RunnerID:        234,
		RunnerName:      "a-runner-name",
		RequestTime:     "a-request-time",
		SourceVersion:   "2.3.4",
		TargetVersion:   "5.6.7",
		Reason:          "some-reason",
		Result:          "some-result",
		Details:         "some-details",
		OSDescription:   "some-os",
		RunnerGroupID:   987,
		RunnerGroupName: "a-runner-group",
	}
	exampleAuditLogDefaults = auditLogDefaults{
		Action:        "some-action",
		OperationType: "modify",
		CreatedAt:     time.Now().UnixNano() / int64(time.Millisecond),
		Timestamp:     time.Now().UnixNano() / int64(time.Millisecond),
		CategoryType:  "Resource Management",
	}
)

func makeKeyVaultSecret(pwd []byte) *azp.KeyVaultSecret {
	val := fmt.Sprintf(`{"Password":"%s"}`, base64.StdEncoding.EncodeToString(pwd))
	return &azp.KeyVaultSecret{
		Value: val,
	}
}

func (s *runnerUpdatedTestSuite) SetupTest() {
	s.hydro = &events.MockHydro{}

	s.azpResources = deployer.MockAzpResourcesLoader{}

	s.keyVaultClient = &azp.MockKeyVaultClient{}
	s.keyVaultClient.On("GetSecret", mock.Anything, authVaultName, primaryHMACKeyName).
		Return(makeKeyVaultSecret(primaryHMACKey), nil).
		Maybe()
	s.keyVaultClient.On("GetSecret", mock.Anything, authVaultName, secondaryHMACKeyName).
		Return(makeKeyVaultSecret(secondaryHMACKey), nil).
		Maybe()

	s.verifier = &auth.MockVerifier{}

	s.twirpClient = &ghtwirp.MockClient{}

	s.svc = NewService(
		&Config{},
		observability.NewNullObservability(),
		s.hydro,
		&s.azpResources,
		authVaultName,
		s.keyVaultClient,
		s.verifier,
		s.twirpClient)
}

func (s *runnerUpdatedTestSuite) TearDownTest() {
	s.hydro.AssertExpectations(s.T())
	s.azpResources.AssertExpectations(s.T())
	s.keyVaultClient.AssertExpectations(s.T())
	s.verifier.AssertExpectations(s.T())
	s.twirpClient.AssertExpectations(s.T())
}

func (s *runnerUpdatedTestSuite) TestNotVerified() {
	res := httptest.NewRecorder()
	req := s.getRequest("{}", "bad-signature")
	s.setRequestVerificationResult(false, primaryHMACKey, secondaryHMACKey)

	s.svc.handleRunnerUpdated(res, req)
	s.Equal(http.StatusForbidden, res.Code)
}

func (s *runnerUpdatedTestSuite) TestBadJSON() {
	res := httptest.NewRecorder()
	req := s.getRequest("{BADJSON", "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.svc.handleRunnerUpdated(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *runnerUpdatedTestSuite) TestDBError() {
	res := httptest.NewRecorder()
	req := s.getRequest(fmt.Sprintf("{\"tenant_id\":\"%s\"}", tenantID), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(nil, false, errors.New("Some DB Error"))

	s.svc.handleRunnerUpdated(res, req)
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *runnerUpdatedTestSuite) TestNoTenantFoundInDB() {
	res := httptest.NewRecorder()
	req := s.getRequest(fmt.Sprintf("{\"tenant_id\":\"%s\"}", tenantID), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(nil, false, nil)

	s.svc.handleRunnerUpdated(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *runnerUpdatedTestSuite) TestHydroEventPublishedForRepository() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerUpdate)
	req := s.getRequest(string(data), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(&deployer.AzpResource{
			EntityID: repoGlobalID,
		}, true, nil)

	s.twirpClient.On("GetRepositoryOwners", mock.Anything, repoDbID).
		Return(&ghtwirp.RepositoryOwners{
			Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
			Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName, Type: ghtwirp.OrganizationType},
			OwnerPlanName: ghtwirp.EnterprisePlan,
			Business:      &ghtwirp.Entity{ID: enterpriseDbID, GlobalID: enterpriseGlobalID, Name: enterpriseName},
		}, nil)

	s.hydro.On("Emit", mock.MatchedBy(func(event events.Event) bool {
		messages := event.GetHydroMessages()
		eventType := event.GetEventType()
		action := "repo.self_hosted_runner_updated"

		s.Equal("audit_log_event", eventType)
		s.Len(messages, 1)

		msg, ok := messages[0].(*auditLog.AuditEntry)
		s.True(ok)
		s.Equal(action, msg.Action.GetValue())
		s.Equal(entities.AuditLog_GITHUB, msg.AuditLog)

		var doc *repoRunnerUpdateDocument
		s.NoError(json.Unmarshal([]byte(msg.Document.GetValue()), &doc))

		s.Equal(repoDbID, doc.RepoID)
		s.Equal(fmt.Sprintf("%s/%s", orgName, repoName), doc.Repo)
		s.Equal(orgDbID, doc.OrgID)
		s.Equal(orgName, doc.Org)
		s.Equal(enterpriseDbID, doc.BusinessID)
		s.Equal(enterpriseName, doc.Business)

		s.EqualRunnerUpdate(exampleRunnerUpdate, doc.runnerUpdate)

		exampleAuditLogDefaults.Action = action
		s.EqualAuditLogDefaults(exampleAuditLogDefaults, doc.auditLogDefaults)

		return true
	})).Once()

	s.svc.handleRunnerUpdated(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *runnerUpdatedTestSuite) TestHydroEventPublishedForOrganization() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerUpdate)
	req := s.getRequest(string(data), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(&deployer.AzpResource{
			EntityID: orgGlobalID,
		}, true, nil)

	s.twirpClient.On("GetOrganizationOwner", mock.Anything, orgDbID).
		Return(&ghtwirp.OrganizationOwner{
			Organization:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
			OrganizationPlanName: ghtwirp.EnterprisePlan,
			Business:             &ghtwirp.Entity{ID: enterpriseDbID, GlobalID: enterpriseGlobalID, Name: enterpriseName},
		}, nil)

	s.hydro.On("Emit", mock.MatchedBy(func(event events.Event) bool {
		messages := event.GetHydroMessages()
		eventType := event.GetEventType()
		action := "org.self_hosted_runner_updated"

		s.Equal("audit_log_event", eventType)
		s.Len(messages, 1)

		msg, ok := messages[0].(*auditLog.AuditEntry)
		s.True(ok)
		s.Equal(action, msg.Action.GetValue())
		s.Equal(entities.AuditLog_GITHUB, msg.AuditLog)

		var doc *orgRunnerUpdateDocument
		s.NoError(json.Unmarshal([]byte(msg.Document.GetValue()), &doc))

		s.Equal(orgDbID, doc.OrgID)
		s.Equal(orgName, doc.Org)
		s.Equal(enterpriseDbID, doc.BusinessID)
		s.Equal(enterpriseName, doc.Business)

		s.EqualRunnerUpdate(exampleRunnerUpdate, doc.runnerUpdate)

		exampleAuditLogDefaults.Action = action
		s.EqualAuditLogDefaults(exampleAuditLogDefaults, doc.auditLogDefaults)

		return true
	})).Once()

	s.svc.handleRunnerUpdated(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *runnerUpdatedTestSuite) TestHydroEventPublishedForEnterprise() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerUpdate)
	req := s.getRequest(string(data), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(&deployer.AzpResource{
			EntityID: enterpriseGlobalID,
		}, true, nil)

	s.hydro.On("Emit", mock.MatchedBy(func(event events.Event) bool {
		messages := event.GetHydroMessages()
		eventType := event.GetEventType()
		action := "enterprise.self_hosted_runner_updated"
		s.Equal("audit_log_event", eventType)
		s.Len(messages, 1)

		msg, ok := messages[0].(*auditLog.AuditEntry)
		s.True(ok)
		s.Equal(action, msg.Action.GetValue())
		s.Equal(entities.AuditLog_GITHUB, msg.AuditLog)

		var doc *enterpriseRunnerUpdateDocument
		s.NoError(json.Unmarshal([]byte(msg.Document.GetValue()), &doc))

		s.Equal(enterpriseDbID, doc.BusinessID)
		s.EqualRunnerUpdate(exampleRunnerUpdate, doc.runnerUpdate)

		exampleAuditLogDefaults.Action = action
		s.EqualAuditLogDefaults(exampleAuditLogDefaults, doc.auditLogDefaults)

		return true
	})).Once()

	s.svc.handleRunnerUpdated(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *runnerUpdatedTestSuite) TestHydroEvent_Repo_CheckEnterpriseRequirements() {
	tests := []struct {
		name          string
		ownerResponse *ghtwirp.RepositoryOwners
		emitted       bool
	}{
		{
			name: "Not if owner is user",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository: ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				// PlanName should gate out users so we are not actually checking for the user type
				Owner:         ghtwirp.Entity{ID: userDbID, Name: userName, Type: ghtwirp.UserType},
				OwnerPlanName: ghtwirp.FreePlan,
			},
			emitted: false,
		},
		{
			name: "Not if owner is on an unsupported plan",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName, Type: ghtwirp.OrganizationType},
				OwnerPlanName: ghtwirp.FreeOrganizationPlan,
			},
			emitted: false,
		},
		{
			name: "Emit if organization is on enterprise plan with no business",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName, Type: ghtwirp.OrganizationType},
				OwnerPlanName: ghtwirp.EnterprisePlan,
			},
			emitted: true,
		},
		{
			name: "Emit if organization is on business_plus plan with no business",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName, Type: ghtwirp.OrganizationType},
				OwnerPlanName: ghtwirp.EnterprisePlan,
			},
			emitted: true,
		},
		{
			name: "Emit if organization is on business_plus plan with a business",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName, Type: ghtwirp.OrganizationType},
				OwnerPlanName: ghtwirp.EnterprisePlan,
				Business:      &ghtwirp.Entity{ID: enterpriseDbID, GlobalID: enterpriseGlobalID, Name: enterpriseName},
			},
			emitted: true,
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			s.SetupTest() // Need to reset the mocks for this subtest

			res := httptest.NewRecorder()

			data, _ := json.Marshal(exampleRunnerUpdate)
			req := s.getRequest(string(data), "signature")
			s.setRequestVerificationResult(true, primaryHMACKey)

			s.azpResources.On("GetByTenantID", mock.Anything, tenantID).Return(&deployer.AzpResource{EntityID: repoGlobalID}, true, nil)

			s.twirpClient.ExpectedCalls = []*mock.Call{} // Clear out calls to add back the features enabled one
			s.twirpClient.On("GetRepositoryOwners", mock.Anything, repoDbID).Return(tc.ownerResponse, nil).Maybe()

			if tc.emitted {
				s.hydro.On("Emit", mock.Anything).Once()
			}

			s.svc.handleRunnerUpdated(res, req)

			if !tc.emitted {
				s.hydro.AssertNumberOfCalls(s.T(), "Emit", 0)
			}

			s.Equal(http.StatusOK, res.Code)

			s.TearDownTest() // Need to assert expectations
		})
	}
}

func (s *runnerUpdatedTestSuite) TestHydroEvent_Org_CheckEnterpriseRequirements() {
	tests := []struct {
		name        string
		orgResponse *ghtwirp.OrganizationOwner
		emitted     bool
	}{
		{
			name: "Not if organization is on an unsupported plan",
			orgResponse: &ghtwirp.OrganizationOwner{
				Organization:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
				OrganizationPlanName: ghtwirp.FreeOrganizationPlan,
			},
			emitted: false,
		},
		{
			name: "Emit if organization is on trial enterprise plan",
			orgResponse: &ghtwirp.OrganizationOwner{
				Organization:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
				OrganizationPlanName: ghtwirp.EnterpriseTrialPlan,
			},
			emitted: true,
		},
		{
			name: "Emit if organization is on enterprise plan with no business",
			orgResponse: &ghtwirp.OrganizationOwner{
				Organization:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
				OrganizationPlanName: ghtwirp.EnterprisePlan,
			},
			emitted: true,
		},
		{
			name: "Emit if organization is on business_plus plan with no business",
			orgResponse: &ghtwirp.OrganizationOwner{
				Organization:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
				OrganizationPlanName: ghtwirp.EnterprisePlan,
			},
			emitted: true,
		},
		{
			name: "Emit if organization is on business_plus plan with a business",
			orgResponse: &ghtwirp.OrganizationOwner{
				Organization:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
				OrganizationPlanName: ghtwirp.EnterprisePlan,
				Business:             &ghtwirp.Entity{ID: enterpriseDbID, GlobalID: enterpriseGlobalID, Name: enterpriseName},
			},
			emitted: true,
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			s.SetupTest() // Need to reset the mocks for this subtest

			res := httptest.NewRecorder()

			data, _ := json.Marshal(exampleRunnerUpdate)
			req := s.getRequest(string(data), "signature")
			s.setRequestVerificationResult(true, primaryHMACKey)

			s.azpResources.On("GetByTenantID", mock.Anything, tenantID).Return(&deployer.AzpResource{EntityID: orgGlobalID}, true, nil)

			s.twirpClient.ExpectedCalls = []*mock.Call{} // Clear out calls to add back the features enabled one
			s.twirpClient.On("GetOrganizationOwner", mock.Anything, orgDbID).Return(tc.orgResponse, nil).Maybe()

			if tc.emitted {
				s.hydro.On("Emit", mock.Anything).Once()
			}

			s.svc.handleRunnerUpdated(res, req)

			if !tc.emitted {
				s.hydro.AssertNumberOfCalls(s.T(), "Emit", 0)
			}

			s.Equal(http.StatusOK, res.Code)

			s.TearDownTest() // Need to assert expectations
		})
	}
}

func (s *runnerUpdatedTestSuite) TestHydroEvent_NotPublishedForRepositoryWithNoEnterprise() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerUpdate)
	req := s.getRequest(string(data), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(&deployer.AzpResource{
			EntityID: repoGlobalID,
		}, true, nil)

	s.twirpClient.On("GetRepositoryOwners", mock.Anything, repoDbID).
		Return(&ghtwirp.RepositoryOwners{
			Repository: ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
			Owner:      ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
		}, nil)

	s.svc.handleRunnerUpdated(res, req)

	s.hydro.AssertNotCalled(s.T(), "Emit", mock.Anything)
	s.Equal(http.StatusOK, res.Code)
}

func (s *runnerUpdatedTestSuite) TestHydroEvent_NotPublishedForOrganizationWithNoEnterprise() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerUpdate)
	req := s.getRequest(string(data), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(&deployer.AzpResource{
			EntityID: orgGlobalID,
		}, true, nil)

	s.twirpClient.On("GetOrganizationOwner", mock.Anything, orgDbID).
		Return(&ghtwirp.OrganizationOwner{
			Organization:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
			OrganizationPlanName: ghtwirp.FreeOrganizationPlan,
		}, nil)

	s.svc.handleRunnerUpdated(res, req)

	s.hydro.AssertNotCalled(s.T(), "Emit", mock.Anything)
	s.Equal(http.StatusOK, res.Code)
}

func (s *runnerUpdatedTestSuite) setRequestVerificationResult(valid bool, keys ...[]byte) {
	for _, key := range keys {
		s.verifier.On("Verify",
			mock.Anything,
			mock.Anything,
			auth.NewKey(key),
		).Return(valid)
	}
}

func (s *runnerUpdatedTestSuite) getRequest(body, signature string) *http.Request {
	req := httptest.NewRequest(http.MethodGet, "/actions/runner/updated", bytes.NewReader([]byte(body)))
	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte(signature))))
	req.Header.Add("Content-Type", "application/json")

	return req
}

func (s *runnerUpdatedTestSuite) EqualRunnerUpdate(expected, actual runnerUpdate) {
	s.Equal(expected.TenantID, actual.TenantID)
	s.Equal(expected.RunnerID, actual.RunnerID)
	s.Equal(expected.RunnerName, actual.RunnerName)
	s.Equal(expected.RequestTime, actual.RequestTime)
	s.Equal(expected.SourceVersion, actual.SourceVersion)
	s.Equal(expected.TargetVersion, actual.TargetVersion)
	s.Equal(expected.Reason, actual.Reason)
	s.Equal(expected.Result, actual.Result)
	s.Equal(expected.Details, actual.Details)
	s.Equal(expected.OSDescription, actual.OSDescription)
	s.Equal(expected.RunnerGroupID, actual.RunnerGroupID)
	s.Equal(expected.RunnerGroupName, actual.RunnerGroupName)
}

func (s *runnerUpdatedTestSuite) EqualAuditLogDefaults(expected, actual auditLogDefaults) {
	s.Equal(expected.Action, actual.Action)
	s.Equal(expected.CategoryType, actual.CategoryType)
	s.Equal(expected.OperationType, actual.OperationType)

	diff := actual.CreatedAt - expected.CreatedAt
	if diff < 0 {
		diff = -diff
	}
	s.LessOrEqual(diff, int64(1000))

	// Timestamp and CreatedAt are equal to each other
	s.Equal(actual.CreatedAt, actual.Timestamp)
}

func (s *runnerUpdatedTestSuite) TestMultiTenantModes() {
	tests := []struct {
		name          string
		isMultiTenant bool
		ownerResponse interface{}
		emitted       bool
	}{
		{
			name: "non-multi-tenant",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName, Type: ghtwirp.OrganizationType},
				OwnerPlanName: ghtwirp.EnterprisePlan,
				Business:      &ghtwirp.Entity{ID: enterpriseDbID, GlobalID: enterpriseGlobalID, Name: enterpriseName},
			},
			emitted: true,
		},
		{
			name:          "multi-tenant",
			isMultiTenant: true,
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName, Type: ghtwirp.OrganizationType},
				OwnerPlanName: ghtwirp.EnterprisePlan,
				Business:      &ghtwirp.Entity{ID: enterpriseDbID, GlobalID: enterpriseGlobalID, Name: enterpriseName},
			},
			emitted: true,
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			s.SetupTest() // Need to reset the mocks for this subtest

			res := httptest.NewRecorder()
			s.svc.cfg.IsMultiTenant = tc.isMultiTenant

			data, _ := json.Marshal(exampleRunnerUpdate)
			req := s.getRequest(string(data), "signature")
			s.setRequestVerificationResult(true, primaryHMACKey)

			s.azpResources.On("GetByTenantID", mock.Anything, tenantID).Return(&deployer.AzpResource{EntityID: repoGlobalID}, true, nil)

			s.twirpClient.ExpectedCalls = []*mock.Call{} // Clear out calls
			s.twirpClient.On("GetRepositoryOwners", mock.Anything, repoDbID).Run(
				func(args mock.Arguments) {
					ctx := args.Get(0).(context.Context)
					header, ok := twirp.HTTPRequestHeaders(ctx)

					if tc.isMultiTenant {
						if !ok {
							s.T().Error("No twirp headers found in context when getting owners")
						}

						s.Equal(ghtenant.SerializeLoginDisplay, header.Get(ghtenant.SerializeLoginHeader))
					}

					if !tc.isMultiTenant {
						if ok {
							// If another twirp header is set, make sure its not the serialize login header
							s.Equal("", header.Get(ghtenant.SerializeLoginHeader))
						}
					}

				},
			).Return(tc.ownerResponse, nil)

			if tc.emitted {
				s.hydro.On("Emit", mock.Anything).Once()
			}

			s.svc.handleRunnerUpdated(res, req)

			if !tc.emitted {
				s.hydro.AssertNumberOfCalls(s.T(), "Emit", 0)
			}

			s.Equal(http.StatusOK, res.Code)

			s.TearDownTest() // Need to assert expectations
		})
	}
}
