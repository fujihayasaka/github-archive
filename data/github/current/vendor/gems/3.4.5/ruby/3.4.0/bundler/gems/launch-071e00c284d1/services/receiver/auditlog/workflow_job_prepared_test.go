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

func TestWorkflowJobPrepared(t *testing.T) {
	suite.Run(t, new(workflowJobPreparedTestSuite))
}

type workflowJobPreparedTestSuite struct {
	suite.Suite
	svc *Service

	hydro          *events.MockHydro
	azpResources   deployer.MockAzpResourcesLoader
	keyVaultClient *azp.MockKeyVaultClient
	verifier       *auth.MockVerifier
	twirpClient    *ghtwirp.MockClient
}

var (
	exampleWorkflowJopPrepared = workflowJobPrepared{
		CallingWorkflowRefs: []string{"owner2/repo3/.github/workflows/orchestrator.yml@refs/heads/main"},
		CallingWorkflowShas: []string{"e36a46136be580a51df0a284919663882b84d27e"},
		TenantID:            tenantID,
		WorkflowRunID:       234,
		JobName:             "a-job-name",
		JobWorkflowRef:      "owner/repo/.github/workflows/test.yml@v1.1",
		JobWorkflowSha:      "46e59c81e5f846e5adbd74e7ca9dda6c0742b2ff",
		RunnerLabels:        []string{"label1", "label2"},
		IsHostedRunner:      true,
		EnvironmentName:     "an-environment",
		SecretsPassed:       []string{"SECRET1", "SECRET2"},
	}

	exampleWorkflowJopPreparedWithRunnerGroup = workflowJobPrepared{
		CallingWorkflowRefs: []string{"owner2/repo3/.github/workflows/orchestrator.yml@refs/heads/main"},
		CallingWorkflowShas: []string{"e36a46136be580a51df0a284919663882b84d27e"},
		TenantID:            tenantID,
		WorkflowRunID:       234,
		JobName:             "a-job-name",
		JobWorkflowRef:      "owner/repo/.github/workflows/test.yml@refs/heads/main",
		JobWorkflowSha:      "46e59c81e5f846e5adbd74e7ca9dda6c0742b2ff",
		RunnerLabels:        []string{"label1", "label2"},
		IsHostedRunner:      true,
		EnvironmentName:     "an-environment",
		SecretsPassed:       []string{"SECRET1", "SECRET2"},
		RunnerTenantID:      runnerTenantID,
		RunnerGroupName:     "default",
		RunnerGroupID:       1,
		RunnerName:          "test",
		RunnerID:            123,
	}
)

func (s *workflowJobPreparedTestSuite) SetupTest() {
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

func (s *workflowJobPreparedTestSuite) TearDownTest() {
	s.hydro.AssertExpectations(s.T())
	s.azpResources.AssertExpectations(s.T())
	s.keyVaultClient.AssertExpectations(s.T())
	s.verifier.AssertExpectations(s.T())
	s.twirpClient.AssertExpectations(s.T())
}

func (s *workflowJobPreparedTestSuite) TestNotVerified() {
	res := httptest.NewRecorder()
	req := s.getRequest("{}", "bad-signature")
	s.setRequestVerificationResult(false, primaryHMACKey, secondaryHMACKey)

	s.svc.handleWorkflowJobPrepared(res, req)
	s.Equal(http.StatusForbidden, res.Code)
}

func (s *workflowJobPreparedTestSuite) TestBadJSON() {
	res := httptest.NewRecorder()
	req := s.getRequest("{BADJSON", "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.svc.handleWorkflowJobPrepared(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *workflowJobPreparedTestSuite) TestDBError() {
	res := httptest.NewRecorder()
	req := s.getRequest(fmt.Sprintf("{\"tenant_id\":\"%s\"}", tenantID), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(nil, false, errors.New("Some DB Error"))

	s.svc.handleWorkflowJobPrepared(res, req)
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *workflowJobPreparedTestSuite) TestNoTenantFoundInDB() {
	res := httptest.NewRecorder()
	req := s.getRequest(fmt.Sprintf("{\"tenant_id\":\"%s\"}", tenantID), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(nil, false, nil)

	s.svc.handleWorkflowJobPrepared(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *workflowJobPreparedTestSuite) TestHydroEventPublishedForRepository() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleWorkflowJopPrepared)
	req := s.getRequest(string(data), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(&deployer.AzpResource{
			EntityID: repoGlobalID,
		}, true, nil)

	s.twirpClient.On("GetRepositoryOwners", mock.Anything, repoDbID).
		Return(&ghtwirp.RepositoryOwners{
			Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
			Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
			OwnerPlanName: ghtwirp.EnterprisePlan,
			Business:      &ghtwirp.Entity{ID: enterpriseDbID, GlobalID: enterpriseGlobalID, Name: enterpriseName},
		}, nil)

	s.hydro.On("Emit", mock.MatchedBy(func(event events.Event) bool {
		messages := event.GetHydroMessages()
		eventType := event.GetEventType()
		action := "workflows.prepared_workflow_job"

		s.Equal("audit_log_event", eventType)
		s.Len(messages, 1)

		msg, ok := messages[0].(*auditLog.AuditEntry)
		s.True(ok)
		s.Equal(action, msg.Action.GetValue())
		s.Equal(entities.AuditLog_GITHUB, msg.AuditLog)

		var doc *workflowJobPreparedDocument
		s.NoError(json.Unmarshal([]byte(msg.Document.GetValue()), &doc))

		s.Equal(repoDbID, doc.RepoID)
		s.Equal(fmt.Sprintf("%s/%s", orgName, repoName), doc.Repo)
		s.Equal(orgDbID, doc.OrgID)
		s.Equal(orgName, doc.Org)
		s.Equal("owner/repo/.github/workflows/test.yml@v1.1", doc.JobWorkflowRef)
		s.Equal(enterpriseDbID, doc.BusinessID)
		s.Equal(enterpriseName, doc.Business)

		s.EqualWorkflowJobPrepared(exampleWorkflowJopPrepared, doc.workflowJobPrepared)

		exampleAuditLogDefaults.Action = action
		s.EqualAuditLogDefaults(exampleAuditLogDefaults, doc.auditLogDefaults)

		return true
	})).Once()

	s.svc.handleWorkflowJobPrepared(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *workflowJobPreparedTestSuite) TestHydroEventPublishedForRepositoryWithRunnerGroup() {
	res := httptest.NewRecorder()

	data, _ := json.Marshal(exampleWorkflowJopPreparedWithRunnerGroup)
	req := s.getRequest(string(data), "signature")
	s.setRequestVerificationResult(true, primaryHMACKey)

	s.azpResources.On("GetByTenantID", mock.Anything, tenantID).
		Return(&deployer.AzpResource{
			EntityID: repoGlobalID,
		}, true, nil)

	s.azpResources.On("GetByTenantID", mock.Anything, runnerTenantID).
		Return(&deployer.AzpResource{
			EntityID: enterpriseGlobalID,
		}, true, nil)

	s.twirpClient.On("GetRepositoryOwners", mock.Anything, repoDbID).
		Return(&ghtwirp.RepositoryOwners{
			Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
			Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
			OwnerPlanName: ghtwirp.EnterprisePlan,
			Business:      &ghtwirp.Entity{ID: enterpriseDbID, GlobalID: enterpriseGlobalID, Name: enterpriseName},
		}, nil)

	s.hydro.On("Emit", mock.MatchedBy(func(event events.Event) bool {
		messages := event.GetHydroMessages()
		eventType := event.GetEventType()
		action := "workflows.prepared_workflow_job"

		s.Equal("audit_log_event", eventType)
		s.Len(messages, 1)

		msg, ok := messages[0].(*auditLog.AuditEntry)
		s.True(ok)
		s.Equal(action, msg.Action.GetValue())
		s.Equal(entities.AuditLog_GITHUB, msg.AuditLog)

		var doc *workflowJobPreparedDocument
		s.NoError(json.Unmarshal([]byte(msg.Document.GetValue()), &doc))

		s.Equal(repoDbID, doc.RepoID)
		s.Equal(fmt.Sprintf("%s/%s", orgName, repoName), doc.Repo)
		s.Equal(orgDbID, doc.OrgID)
		s.Equal(orgName, doc.Org)
		s.Equal("owner/repo/.github/workflows/test.yml@refs/heads/main", doc.JobWorkflowRef)
		s.Equal(enterpriseDbID, doc.BusinessID)
		s.Equal(enterpriseName, doc.Business)
		s.Equal("Enterprise", doc.RunnerOwnerType)

		s.EqualWorkflowJobPrepared(exampleWorkflowJopPreparedWithRunnerGroup, doc.workflowJobPrepared)

		exampleAuditLogDefaults.Action = action
		s.EqualAuditLogDefaults(exampleAuditLogDefaults, doc.auditLogDefaults)

		return true
	})).Once()

	s.svc.handleWorkflowJobPrepared(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *workflowJobPreparedTestSuite) TestHydroEvent_Repo_CheckEnterpriseRequirements() {
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
				Owner:         ghtwirp.Entity{ID: userDbID, Name: userName},
				OwnerPlanName: ghtwirp.FreePlan,
			},
			emitted: false,
		},
		{
			name: "Not if owner is on an unsupported plan",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
				OwnerPlanName: ghtwirp.FreeOrganizationPlan,
			},
			emitted: false,
		},
		{
			name: "Emit if organization is on a trial enterprise plan",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
				OwnerPlanName: ghtwirp.EnterpriseTrialPlan,
			},
			emitted: true,
		},
		{
			name: "Emit if organization is on enterprise plan with no business",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
				OwnerPlanName: ghtwirp.EnterprisePlan,
			},
			emitted: true,
		},
		{
			name: "Emit if organization is on business_plus plan with no business",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
				OwnerPlanName: ghtwirp.EnterprisePlan,
			},
			emitted: true,
		},
		{
			name: "Emit if organization is on business_plus plan with a business",
			ownerResponse: &ghtwirp.RepositoryOwners{
				Repository:    ghtwirp.Entity{ID: repoDbID, GlobalID: repoGlobalID, Name: fmt.Sprintf("%s/%s", orgName, repoName)},
				Owner:         ghtwirp.Entity{ID: orgDbID, GlobalID: orgGlobalID, Name: orgName},
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

			data, _ := json.Marshal(exampleWorkflowJopPrepared)
			req := s.getRequest(string(data), "signature")
			s.setRequestVerificationResult(true, primaryHMACKey)

			s.azpResources.On("GetByTenantID", mock.Anything, tenantID).Return(&deployer.AzpResource{EntityID: repoGlobalID}, true, nil)

			s.twirpClient.ExpectedCalls = []*mock.Call{} // Clear out calls
			s.twirpClient.On("GetRepositoryOwners", mock.Anything, repoDbID).Return(tc.ownerResponse, nil)

			if tc.emitted {
				s.hydro.On("Emit", mock.Anything).Once()
			}

			s.svc.handleWorkflowJobPrepared(res, req)

			if !tc.emitted {
				s.hydro.AssertNumberOfCalls(s.T(), "Emit", 0)
			}

			s.Equal(http.StatusOK, res.Code)

			s.TearDownTest() // Need to assert expectations
		})
	}
}

func (s *workflowJobPreparedTestSuite) setRequestVerificationResult(valid bool, keys ...[]byte) {
	for _, key := range keys {
		s.verifier.On("Verify",
			mock.Anything,
			mock.Anything,
			auth.NewKey(key),
		).Return(valid)
	}
}

func (s *workflowJobPreparedTestSuite) getRequest(body, signature string) *http.Request {
	req := httptest.NewRequest(http.MethodGet, "/actions/workflow_job/prepared", bytes.NewReader([]byte(body)))
	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte(signature))))
	req.Header.Add("Content-Type", "application/json")

	return req
}

func (s *workflowJobPreparedTestSuite) EqualWorkflowJobPrepared(expected, actual workflowJobPrepared) {
	s.Equal(expected.CallingWorkflowRefs, actual.CallingWorkflowRefs)
	s.Equal(expected.CallingWorkflowShas, actual.CallingWorkflowShas)
	s.Equal(expected.TenantID, actual.TenantID)
	s.Equal(expected.WorkflowRunID, actual.WorkflowRunID)
	s.Equal(expected.JobName, actual.JobName)
	s.Equal(expected.JobWorkflowRef, actual.JobWorkflowRef)
	s.Equal(expected.JobWorkflowSha, actual.JobWorkflowSha)
	s.Equal(expected.RunnerLabels, actual.RunnerLabels)
	s.Equal(expected.IsHostedRunner, actual.IsHostedRunner)
	s.Equal(expected.EnvironmentName, actual.EnvironmentName)
	s.Equal(expected.SecretsPassed, actual.SecretsPassed)
	s.Equal(expected.RunnerTenantID, actual.RunnerTenantID)
	s.Equal(expected.RunnerGroupID, actual.RunnerGroupID)
	s.Equal(expected.RunnerGroupName, actual.RunnerGroupName)
	s.Equal(expected.RunnerName, actual.RunnerName)
	s.Equal(expected.RunnerID, actual.RunnerID)
}

func (s *workflowJobPreparedTestSuite) EqualAuditLogDefaults(expected, actual auditLogDefaults) {
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

func (s *workflowJobPreparedTestSuite) TestMultiTenantModes() {
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

			data, _ := json.Marshal(exampleWorkflowJopPrepared)
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

			s.svc.handleWorkflowJobPrepared(res, req)

			if !tc.emitted {
				s.hydro.AssertNumberOfCalls(s.T(), "Emit", 0)
			}

			s.Equal(http.StatusOK, res.Code)

			s.TearDownTest() // Need to assert expectations
		})
	}
}
