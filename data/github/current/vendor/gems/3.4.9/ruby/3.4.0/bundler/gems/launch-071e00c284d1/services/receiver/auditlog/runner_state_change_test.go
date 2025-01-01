package auditlog

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/pkg/errors"
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
	"github.com/github/launch/utils/ghtenant"
)

func TestRunnerStateChange(t *testing.T) {
	suite.Run(t, new(runnerStateChangeTestSuite))
}

type runnerStateChangeTestSuite struct {
	suite.Suite
	svc *Service

	hydro          *events.MockHydro
	azpResources   deployer.MockAzpResourcesLoader
	keyVaultClient *azp.MockKeyVaultClient
	verifier       *auth.MockVerifier
	twirpClient    *ghtwirp.MockClient
}

func (s *runnerStateChangeTestSuite) EqualAuditLogDefaults(expected, actual auditLogDefaults) {
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
	s.True(actual.DocumentID != "")
}

func (s *runnerStateChangeTestSuite) setRequestVerificationResult(valid bool, keys ...[]byte) {
	for _, key := range keys {
		s.verifier.On("Verify",
			mock.Anything,
			mock.Anything,
			auth.NewKey(key),
		).Return(valid)
	}
}

func (s *runnerStateChangeTestSuite) postRequest(state, body, signature string) *http.Request {
	req := httptest.NewRequest(http.MethodPost, "/actions/runners/"+state, bytes.NewReader([]byte(body)))
	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte(signature))))
	req.Header.Add("Content-Type", "application/json")

	return req
}

var (
	exampleRunnerStateChange = runnerStateChange{
		TenantID:   tenantID,
		RunnerID:   234,
		RunnerName: "a-runner-name",
	}
)

func (s *runnerStateChangeTestSuite) SetupTest() {
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

func (s *runnerStateChangeTestSuite) TearDownTest() {
	s.hydro.AssertExpectations(s.T())
	s.azpResources.AssertExpectations(s.T())
	s.keyVaultClient.AssertExpectations(s.T())
	s.verifier.AssertExpectations(s.T())
	s.twirpClient.AssertExpectations(s.T())
}

func (s *runnerStateChangeTestSuite) TestNotVerified() {
	res := httptest.NewRecorder()
	req := s.postRequest("online", "{}", "bad-signature")
	s.setRequestVerificationResult(false, primaryHMACKey, secondaryHMACKey)

	s.svc.handleRunnerStateChange("foo", "metric")(res, req)
	s.Equal(http.StatusForbidden, res.Code)
}

func (s *runnerStateChangeTestSuite) TestBadJSON() {
	res := httptest.NewRecorder()
	req := s.postRequest("online", "{badjson}", "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.svc.handleRunnerUpdated(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *runnerStateChangeTestSuite) TestDBError() {
	res := httptest.NewRecorder()
	req := s.postRequest("online", fmt.Sprintf("{\"tenant_id\":\"%s\"}", tenantID), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(nil, false, errors.New("Some DB Error"))

	s.svc.handleRunnerStateChange("foo", "metric")(res, req)
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *runnerStateChangeTestSuite) TestNoTenantFoundInDB() {
	res := httptest.NewRecorder()
	req := s.postRequest("online", fmt.Sprintf("{\"tenant_id\":\"%s\"}", tenantID), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(nil, false, nil)

	s.svc.handleRunnerStateChange("foo", "metric")(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *runnerStateChangeTestSuite) TestRepoOwnerNotFound() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerStateChange)
	req := s.postRequest("online", string(data), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(&deployer.AzpResource{
			EntityID: repoGlobalID,
		}, true, nil)

	s.twirpClient.On("GetRepositoryOwners", mock.Anything, repoDbID).
		Return(nil, errors.Wrap(twirp.NotFoundError("not found"), "another error"))

	s.svc.handleRunnerStateChange("foo", "metric")(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *runnerStateChangeTestSuite) TestHydroEventPublishedForRepository() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerStateChange)
	req := s.postRequest("online", string(data), "signature")
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
		action := "repo.self_hosted_runner_foo"

		s.Equal("audit_log_event", eventType)
		s.Len(messages, 1)

		msg, ok := messages[0].(*auditLog.AuditEntry)
		s.True(ok)
		s.Equal(action, msg.Action.GetValue())
		s.Equal(entities.AuditLog_GITHUB, msg.AuditLog)

		var doc *repoRunnerStateChangeDocument
		s.NoError(json.Unmarshal([]byte(msg.Document.GetValue()), &doc))

		s.Equal(repoDbID, doc.RepoID)
		s.Equal(fmt.Sprintf("%s/%s", orgName, repoName), doc.Repo)
		s.Equal(orgDbID, doc.OrgID)
		s.Equal(orgName, doc.Org)
		s.Equal(enterpriseDbID, doc.BusinessID)
		s.Equal(enterpriseName, doc.Business)

		s.Equal(exampleRunnerStateChange, doc.runnerStateChange)

		exampleAuditLogDefaults.Action = action
		s.EqualAuditLogDefaults(exampleAuditLogDefaults, doc.auditLogDefaults)

		return true
	})).Once()

	s.svc.handleRunnerStateChange("foo", "metric")(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *runnerStateChangeTestSuite) TestOrgOwnerNotFound() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerStateChange)
	req := s.postRequest("online", string(data), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(&deployer.AzpResource{
			EntityID: orgGlobalID,
		}, true, nil)

	s.twirpClient.On("GetOrganizationOwner", mock.Anything, orgDbID).
		Return(nil, errors.Wrap(twirp.NotFoundError("not found"), "another error"))

	s.svc.handleRunnerStateChange("foo", "metric")(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *runnerStateChangeTestSuite) TestHydroEventPublishedForOrganization() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerStateChange)
	req := s.postRequest("online", string(data), "signature")
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
		action := "org.self_hosted_runner_foo"

		s.Equal("audit_log_event", eventType)
		s.Len(messages, 1)

		msg, ok := messages[0].(*auditLog.AuditEntry)
		s.True(ok)
		s.Equal(action, msg.Action.GetValue())
		s.Equal(entities.AuditLog_GITHUB, msg.AuditLog)

		var doc *orgRunnerStateChangeDocument
		s.NoError(json.Unmarshal([]byte(msg.Document.GetValue()), &doc))

		s.Equal(orgDbID, doc.OrgID)
		s.Equal(orgName, doc.Org)
		s.Equal(enterpriseDbID, doc.BusinessID)
		s.Equal(enterpriseName, doc.Business)

		s.Equal(exampleRunnerStateChange, doc.runnerStateChange)

		exampleAuditLogDefaults.Action = action
		s.EqualAuditLogDefaults(exampleAuditLogDefaults, doc.auditLogDefaults)

		return true
	})).Once()

	s.svc.handleRunnerStateChange("foo", "metric")(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *runnerStateChangeTestSuite) TestHydroEventPublishedForEnterprise() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerStateChange)
	req := s.postRequest("online", string(data), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(&deployer.AzpResource{
			EntityID: enterpriseGlobalID,
		}, true, nil)

	s.hydro.On("Emit", mock.MatchedBy(func(event events.Event) bool {
		messages := event.GetHydroMessages()
		eventType := event.GetEventType()
		action := "enterprise.self_hosted_runner_foo"
		s.Equal("audit_log_event", eventType)
		s.Len(messages, 1)

		msg, ok := messages[0].(*auditLog.AuditEntry)
		s.True(ok)
		s.Equal(action, msg.Action.GetValue())
		s.Equal(entities.AuditLog_GITHUB, msg.AuditLog)

		var doc *enterpriseRunnerStateChangeDocument
		s.NoError(json.Unmarshal([]byte(msg.Document.GetValue()), &doc))

		s.Equal(enterpriseDbID, doc.BusinessID)
		s.Equal(exampleRunnerStateChange, doc.runnerStateChange)

		exampleAuditLogDefaults.Action = action
		s.EqualAuditLogDefaults(exampleAuditLogDefaults, doc.auditLogDefaults)

		return true
	})).Once()

	s.svc.handleRunnerStateChange("foo", "metric")(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *runnerStateChangeTestSuite) TestHydroEvent_Repo_CheckEnterpriseRequirements() {
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

			data, _ := json.Marshal(exampleRunnerStateChange)
			req := s.postRequest("online", string(data), "signature")
			s.setRequestVerificationResult(true, primaryHMACKey)

			s.azpResources.On("GetByTenantID", mock.Anything, tenantID).Return(&deployer.AzpResource{EntityID: repoGlobalID}, true, nil)

			s.twirpClient.On("GetRepositoryOwners", mock.Anything, repoDbID).Return(tc.ownerResponse, nil).Maybe()

			if tc.emitted {
				s.hydro.On("Emit", mock.Anything).Once()
			}

			s.svc.handleRunnerStateChange("foo", "metric")(res, req)

			if !tc.emitted {
				s.hydro.AssertNumberOfCalls(s.T(), "Emit", 0)
			}

			s.Equal(http.StatusOK, res.Code)

			s.TearDownTest() // Need to assert expectations
		})
	}
}

func (s *runnerStateChangeTestSuite) TestHydroEvent_Org_CheckEnterpriseRequirements() {
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

			data, _ := json.Marshal(exampleRunnerStateChange)
			req := s.postRequest("online", string(data), "signature")
			s.setRequestVerificationResult(true, primaryHMACKey)

			s.azpResources.On("GetByTenantID", mock.Anything, tenantID).Return(&deployer.AzpResource{EntityID: orgGlobalID}, true, nil)

			s.twirpClient.On("GetOrganizationOwner", mock.Anything, orgDbID).Return(tc.orgResponse, nil).Maybe()

			if tc.emitted {
				s.hydro.On("Emit", mock.Anything).Once()
			}

			s.svc.handleRunnerStateChange("foo", "metric")(res, req)

			if !tc.emitted {
				s.hydro.AssertNumberOfCalls(s.T(), "Emit", 0)
			}

			s.Equal(http.StatusOK, res.Code)

			s.TearDownTest() // Need to assert expectations
		})
	}
}

func (s *runnerStateChangeTestSuite) TestHydroEvent_NotPublishedForRepositoryWithNoEnterprise() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerStateChange)
	req := s.postRequest("online", string(data), "signature")
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

	s.svc.handleRunnerStateChange("foo", "metric")(res, req)

	s.hydro.AssertNotCalled(s.T(), "Emit", mock.Anything)
	s.Equal(http.StatusOK, res.Code)
}

func (s *runnerStateChangeTestSuite) TestHydroEvent_NotPublishedForOrganizationWithNoEnterprise() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleRunnerStateChange)
	req := s.postRequest("online", string(data), "signature")
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

	s.svc.handleRunnerStateChange("foo", "metric")(res, req)

	s.hydro.AssertNotCalled(s.T(), "Emit", mock.Anything)
	s.Equal(http.StatusOK, res.Code)
}

func (s *runnerStateChangeTestSuite) TestMultiTenantModes() {
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

			data, _ := json.Marshal(exampleRunnerStateChange)
			req := s.postRequest("online", string(data), "signature")
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

			s.svc.handleRunnerStateChange("foo", "metric")(res, req)

			if !tc.emitted {
				s.hydro.AssertNumberOfCalls(s.T(), "Emit", 0)
			}

			s.Equal(http.StatusOK, res.Code)

			s.TearDownTest() // Need to assert expectations
		})
	}
}
