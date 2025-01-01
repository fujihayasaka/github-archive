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

// Match this with AzDevNext: /Actions/Runtime/Service/Server/LaunchPayloads/LaunchRunnerUpdate.cs
type runnerUpdate struct {
	TenantID        string `json:"tenant_id"`
	RunnerID        int    `json:"runner_id"`
	RunnerName      string `json:"runner_name"`
	RequestTime     string `json:"request_time"`
	SourceVersion   string `json:"source_version"`
	TargetVersion   string `json:"target_version"`
	Reason          string `json:"reason"`
	Result          string `json:"result"`
	Details         string `json:"details"`
	OSDescription   string `json:"os_description"`
	RunnerGroupID   int    `json:"runner_group_id"`
	RunnerGroupName string `json:"runner_group_name"`
}

type repoRunnerUpdateDocument struct {
	RepoID       int64  `json:"repo_id"`
	Repo         string `json:"repo"`
	OrgID        int64  `json:"org_id"`
	Org          string `json:"org"`
	BusinessID   int64  `json:"business_id,omitempty"`
	Business     string `json:"business,omitempty"`
	runnerUpdate        // Include all these fields too
	auditLogDefaults
}

type orgRunnerUpdateDocument struct {
	OrgID        int64  `json:"org_id"`
	Org          string `json:"org"`
	BusinessID   int64  `json:"business_id,omitempty"`
	Business     string `json:"business,omitempty"`
	runnerUpdate        // Include all these fields too
	auditLogDefaults
}

type enterpriseRunnerUpdateDocument struct {
	BusinessID   int64 `json:"business_id"`
	runnerUpdate       // Include all these fields too
	auditLogDefaults
}

const runnerUpdatedMetric = "auditlog.handle_runner_updated"

// HandleRunnerUpdated handles the runner update calls
func (s *Service) HandleRunnerUpdated() http.HandlerFunc {
	return s.withThreshold(s.handleRunnerUpdated, fmt.Sprintf("%s.threshold_missing", runnerUpdatedMetric))
}

func (s *Service) handleRunnerUpdated(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	respond := s.respond(resp, runnerUpdatedMetric, span)

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: runnerUpdatedRoute})
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

	var in *runnerUpdate
	if err = json.Unmarshal(body, &in); err != nil {
		respond(ctx, http.StatusBadRequest, errors.Wrap(err, "could not parse JSON body"))
		return
	}
	ctx = ctxstash.WithFields(ctx, kvp.String("gh.actions.tenant.id", in.TenantID), kvp.Int("gh.actions.runner.id", in.RunnerID))

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
	}

	var out any
	now := time.Now().UnixNano() / int64(time.Millisecond)
	defaults := auditLogDefaults{
		DocumentID:    getDocumentID(ctx),
		CategoryType:  "Resource Management",
		OperationType: "modify",
		CreatedAt:     now,
		Timestamp:     now,
	}

	// For audit log events in multi-tenant mode, we want to make sure we get the unsuffixed actor names back
	ctx, err = ghtenant.ContextWithSerializeLoginHeader(ctx, ghtenant.SerializeLoginDisplay, s.cfg.IsMultiTenant)
	if err != nil {
		respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not set serialize login header"))
		return
	}

	switch tenantType {
	case Repository:
		defaults.Action = "repo.self_hosted_runner_updated"

		owners, err := s.ghTwirpClient.GetRepositoryOwners(ctx, tenantID)
		if err != nil {
			respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not get repository owners"))
			return
		}

		if !owners.OnEnterprisePlan() {
			s.obs.Log(ctx, "skipping, repository owner is not on an enterprise plan", kvp.String("gh.launch.owner.plan_name", owners.OwnerPlanName))
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.auditlog_result", "skipped"))
			respond(ctx, http.StatusOK, nil)
			return
		}

		doc := &repoRunnerUpdateDocument{
			RepoID:           tenantID,
			Repo:             owners.Repository.Name,
			OrgID:            owners.Owner.ID,
			Org:              owners.Owner.Name,
			runnerUpdate:     *in,
			auditLogDefaults: defaults,
		}

		if owners.Business != nil {
			doc.BusinessID = owners.Business.ID
			doc.Business = owners.Business.Name
		}
		out = doc

	case Organization:
		defaults.Action = "org.self_hosted_runner_updated"

		owner, err := s.ghTwirpClient.GetOrganizationOwner(ctx, tenantID)
		if err != nil {
			respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not get organization owner"))
			return
		}

		if !owner.OnEnterprisePlan() {
			s.obs.Log(ctx, "skipping, organization is not on an enterprise plan", kvp.String("gh.launch.owner.plan_name", owner.OrganizationPlanName))
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.auditlog_result", "skipped"))
			respond(ctx, http.StatusOK, nil)
			return
		}

		doc := &orgRunnerUpdateDocument{
			OrgID:            tenantID,
			Org:              owner.Organization.Name,
			runnerUpdate:     *in,
			auditLogDefaults: defaults,
		}
		if owner.Business != nil {
			doc.BusinessID = owner.Business.ID
			doc.Business = owner.Business.Name
		}
		out = doc

	case Enterprise:
		defaults.Action = "enterprise.self_hosted_runner_updated"
		out = &enterpriseRunnerUpdateDocument{
			BusinessID:       tenantID,
			runnerUpdate:     *in,
			auditLogDefaults: defaults,
		}

	default:
		respond(ctx, http.StatusInternalServerError, errors.New("unsupported entity type in globalID"))
		return
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
