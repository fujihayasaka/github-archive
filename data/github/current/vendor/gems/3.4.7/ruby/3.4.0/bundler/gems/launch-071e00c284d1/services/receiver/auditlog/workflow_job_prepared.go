package auditlog

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/hydro/events"
	auditLog "github.com/github/launch/hydro/schemas/audit_log/v2"
	entities "github.com/github/launch/hydro/schemas/audit_log/v2/entities"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/utils/ghtenant"
)

// Match this with AzDevNext:
// https://dev.azure.com/mseng/AzureDevOps/_git/AzDevNext?path=%2FActions%2FClient%2FWebApi%2FContracts%2FPreparedWorkflowJobEvent.cs&_a=contents&version=GBmaster
type workflowJobPrepared struct {
	CallingWorkflowRefs []string `json:"calling_workflow_refs,omitempty"`
	CallingWorkflowShas []string `json:"calling_workflow_shas,omitempty"`
	EnvironmentName     string   `json:"environment_name"`
	IsHostedRunner      bool     `json:"is_hosted_runner"`
	JobName             string   `json:"job_name"`
	JobWorkflowRef      string   `json:"job_workflow_ref"`
	JobWorkflowSha      string   `json:"job_workflow_sha"`
	RunnerGroupID       int64    `json:"runner_group_id"`
	RunnerGroupName     string   `json:"runner_group_name"`
	RunnerID            int64    `json:"runner_id"`
	RunnerLabels        []string `json:"runner_labels"`
	RunnerName          string   `json:"runner_name"`
	RunnerTenantID      string   `json:"runner_tenant_id"`
	SecretsPassed       []string `json:"secrets_passed"`
	TenantID            string   `json:"tenant_id"`
	WorkflowRunID       int64    `json:"workflow_run_id"`
	ImposerRepo         string   `json:"imposer_repo,omitempty"`
}

type workflowJobPreparedDocument struct {
	auditLogDefaults
	Business            string `json:"business,omitempty"`
	BusinessID          int64  `json:"business_id,omitempty"`
	OrgID               int64  `json:"org_id"`
	Org                 string `json:"org"`
	Repo                string `json:"repo"`
	RepoID              int64  `json:"repo_id"`
	RunnerOwnerType     string `json:"runner_owner_type,omitempty"`
	workflowJobPrepared        // Include all these fields too
}

const workflowJobPreparedMetric = "auditlog.handle_workflow_job_prepared"

// HandleWorkflowJobPrepared handles the workflow job prepared calls
func (s *Service) HandleWorkflowJobPrepared() http.HandlerFunc {
	return s.withThreshold(s.handleWorkflowJobPrepared, fmt.Sprintf("%s.threshold_missing", workflowJobPreparedMetric))
}

func (s *Service) handleWorkflowJobPrepared(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	respond := s.respond(resp, workflowJobPreparedMetric, span)

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: workflowJobPreparedRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	body, err := io.ReadAll(req.Body)
	if err != nil {
		respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not read http body"))
		return
	}
	defer req.Body.Close()

	if err := s.verifyRequestSignature(ctx, req, body); err != nil {
		respond(ctx, http.StatusForbidden, errors.Wrap(err, "not authorized"))
		return
	}

	var in *workflowJobPrepared
	if err = json.Unmarshal(body, &in); err != nil {
		respond(ctx, http.StatusBadRequest, errors.Wrap(err, "could not parse JSON body"))
		return
	}
	ctx = ctxstash.WithFields(ctx, kvp.String("gh.actions.tenant.id", in.TenantID), kvp.Int64("gh.actions.workflow_run.id", in.WorkflowRunID), kvp.String("gh.launch.job.name", in.JobName), kvp.String("gh.launch.job.workflow_sha", in.JobWorkflowSha), kvp.String("gh.launch.job.workflow_ref", in.JobWorkflowRef), kvp.Any("gh.launch.calling_workflow.refs", in.CallingWorkflowRefs), kvp.Any("gh.launch.calling_workflow.shas", in.CallingWorkflowShas))

	res, found, err := s.db.GetByTenantID(ctx, in.TenantID)
	if err != nil {
		respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not load azp_resource by tenant_id"))
		return
	}
	if !found {
		respond(ctx, http.StatusNotFound, errors.New("tenant_id not found"))
		return
	}
	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.entity.global_id", res.EntityID.String()))

	tenantType, tenantID, err := res.EntityID.Decode()
	if err != nil {
		respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not decode globalID"))
		return
	} else if tenantType != Repository {
		respond(ctx, http.StatusInternalServerError, errors.New("unsupported entity type in globalID"))
		return
	}

	// For audit log events in multi-tenant mode, we want to make sure we get the unsuffixed actor names back
	ctx, err = ghtenant.ContextWithSerializeLoginHeader(ctx, ghtenant.SerializeLoginDisplay, s.cfg.IsMultiTenant)
	if err != nil {
		respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not set serialize login header"))
		return
	}

	owners, err := s.ghTwirpClient.GetRepositoryOwners(ctx, tenantID)
	if err != nil {
		respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not get repository owners"))
		return
	}

	var runnerOwnerType string
	if in.RunnerTenantID != "" {
		runnerTenantRes, found, err := s.db.GetByTenantID(ctx, in.RunnerTenantID)
		if err != nil {
			respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not load azp_resource by runner_tenant_id"))
			return
		}
		if !found {
			respond(ctx, http.StatusNotFound, errors.New("runner_tenant_id not found"))
			return
		}
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.runner_tenant.entity.global_id", runnerTenantRes.EntityID.String()))

		runnerOwnerType, _, err = runnerTenantRes.EntityID.Decode()
		if err != nil {
			respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not decode globalID"))
			return
		}
	}

	if !owners.OnEnterprisePlan() {
		s.obs.Log(ctx, "skipping, repository owner is not on an enterprise plan", kvp.String("gh.launch.owner.plan_name", owners.OwnerPlanName))
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.auditlog_result", "skipped"))
		respond(ctx, http.StatusOK, nil)
		return
	}

	now := time.Now().UnixNano() / int64(time.Millisecond)
	defaults := auditLogDefaults{
		Action:        "workflows.prepared_workflow_job",
		DocumentID:    getDocumentID(ctx),
		CategoryType:  "Resource Management",
		OperationType: "modify",
		CreatedAt:     now,
		Timestamp:     now,
	}

	out := &workflowJobPreparedDocument{
		RepoID:              tenantID,
		Repo:                owners.Repository.Name,
		OrgID:               owners.Owner.ID,
		Org:                 owners.Owner.Name,
		RunnerOwnerType:     runnerOwnerType,
		workflowJobPrepared: *in,
		auditLogDefaults:    defaults,
	}

	if owners.Business != nil {
		out.BusinessID = owners.Business.ID
		out.Business = owners.Business.Name
	}

	outJSON, err := json.Marshal(&out)
	if err != nil {
		respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not marshal document"))
		return
	}

	entry := &auditLog.AuditEntry{
		Action:     stringValue(defaults.Action),
		Document:   stringValue(string(outJSON)),
		DocumentId: stringValue(defaults.DocumentID),
		EventTime:  timestamppb.Now(),
		AuditLog:   entities.AuditLog_GITHUB,
	}

	s.hydro.Emit(events.NewHydroEvent(events.AuditLogEvent, entry))

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.auditlog_result", "emitting"))
	respond(ctx, http.StatusOK, nil)
}
