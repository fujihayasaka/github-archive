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

	errutil "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"

	"github.com/github/launch/hydro/events"
	auditLog "github.com/github/launch/hydro/schemas/audit_log/v2"
	entities "github.com/github/launch/hydro/schemas/audit_log/v2/entities"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
)

type runnerStateChange struct {
	TenantID   string `json:"tenant_id"`
	RunnerID   int    `json:"runner_id"`
	RunnerName string `json:"runner_name"`
}

type repoRunnerStateChangeDocument struct {
	RepoID     int64  `json:"repo_id"`
	Repo       string `json:"repo"`
	OrgID      int64  `json:"org_id"`
	Org        string `json:"org"`
	BusinessID int64  `json:"business_id,omitempty"`
	Business   string `json:"business,omitempty"`
	runnerStateChange
	auditLogDefaults
}

type orgRunnerStateChangeDocument struct {
	OrgID      int64  `json:"org_id"`
	Org        string `json:"org"`
	BusinessID int64  `json:"business_id,omitempty"`
	Business   string `json:"business,omitempty"`
	runnerStateChange
	auditLogDefaults
}

type enterpriseRunnerStateChangeDocument struct {
	BusinessID int64  `json:"business_id,omitempty"`
	Business   string `json:"business,omitempty"`
	runnerStateChange
	auditLogDefaults
}

func (s *Service) HandleRunnerStateChange(state string) http.HandlerFunc {
	runnerStateChangeMetric := fmt.Sprintf("auditlog.handle_runner_%s", state)

	return s.withThreshold(
		s.handleRunnerStateChange(state, runnerStateChangeMetric),
		fmt.Sprintf("%s.threshold_missing", runnerStateChangeMetric))

}

func (s *Service) handleRunnerStateChange(state, runnerStateChangeMetric string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := tracing.Start(r.Context())
		defer span.End()

		respond := s.respond(w, runnerStateChangeMetric, span)
		azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

		body, err := io.ReadAll(r.Body)
		if err != nil {
			respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not read http body"))
			return
		}
		defer r.Body.Close()

		if err := s.verifyRequestSignature(ctx, r, body); err != nil {
			respond(ctx, http.StatusForbidden, errors.Wrap(err, "not authorized"))
			return
		}

		var in *runnerStateChange
		if err = json.Unmarshal(body, &in); err != nil {
			respond(ctx, http.StatusBadRequest, errors.Wrap(err, "could not parse JSON body"))
			return
		}
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.actions.tenant.id", in.TenantID), kvp.Int("gh.actions.runner.id", in.RunnerID))

		tenant, found, err := s.db.GetByTenantID(ctx, in.TenantID)
		if err != nil {
			respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not load azp_resource by tenant_id"))
			return
		}
		if !found {
			respond(ctx, http.StatusNotFound, errors.New("tenant_id not found"))
			return
		}
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.entity.global_id", tenant.EntityID.String()))

		tenantType, tenantID, err := tenant.EntityID.Decode()
		if err != nil {
			respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not decode globalID"))
			return
		}

		now := time.Now().UnixNano() / int64(time.Millisecond)
		defaults := auditLogDefaults{
			DocumentID:    getDocumentID(ctx),
			CategoryType:  "Resource Management",
			OperationType: "modify",
			CreatedAt:     now,
			Timestamp:     now,
		}
		var out any

		// For audit log events in multi-tenant mode, we want to make sure we get the unsuffixed actor names back
		ctx, err = ghtenant.ContextWithSerializeLoginHeader(ctx, ghtenant.SerializeLoginDisplay, s.cfg.IsMultiTenant)
		if err != nil {
			respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not set serialize login header"))
			return
		}

		switch tenantType {
		case Repository:
			defaults.Action = fmtAction("repo", state)

			owners, err := s.ghTwirpClient.GetRepositoryOwners(ctx, tenantID)
			if err != nil {
				if errutil.IsNotFoundError(err) {
					ctx = ctxstash.WithFields(ctx,
						kvp.String("gh.launch.auditlog_result", "skipped"),
						kvp.String("gh.launch.auditlog_result_reason", "repository_owner_not_found"))
					respond(ctx, http.StatusNotFound, nil)
				} else {
					respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not get repository owners"))
				}

				return
			}

			if !owners.OnEnterprisePlan() {
				s.obs.Log(ctx,
					"skipping, repository owner is not on an enterprise plan",
					kvp.String("gh.launch.owner.plan_name", owners.OwnerPlanName))
				ctx = ctxstash.WithFields(ctx,
					kvp.String("gh.launch.auditlog_result", "skipped"),
					kvp.String("gh.launch.auditlog_result_reason", "repo_owner_not_on_enterprise_plan"))
				respond(ctx, http.StatusOK, nil)
				return
			}

			doc := &repoRunnerStateChangeDocument{
				RepoID:            tenantID,
				Repo:              owners.Repository.Name,
				OrgID:             owners.Owner.ID,
				Org:               owners.Owner.Name,
				runnerStateChange: *in,
				auditLogDefaults:  defaults,
			}

			if owners.Business != nil {
				doc.BusinessID = owners.Business.ID
				doc.Business = owners.Business.Name
			}

			out = doc
		case Organization:
			defaults.Action = fmtAction("org", state)

			owner, err := s.ghTwirpClient.GetOrganizationOwner(ctx, tenantID)
			if err != nil {
				if errutil.IsNotFoundError(err) {
					ctx = ctxstash.WithFields(ctx,
						kvp.String("gh.launch.auditlog_result", "skipped"),
						kvp.String("gh.launch.auditlog_result_reason", "organization_owner_not_found"))
					respond(ctx, http.StatusNotFound, nil)
				} else {
					respond(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not get organization owner"))
				}

				return
			}

			if !owner.OnEnterprisePlan() {
				s.obs.Log(ctx, "skipping, organization is not on an enterprise plan",
					kvp.String("gh.launch.owner.plan_name", owner.OrganizationPlanName))
				ctx = ctxstash.WithFields(ctx,
					kvp.String("gh.launch.auditlog_result", "skipped"),
					kvp.String("gh.launch.auditlog_result_reason", "org_not_on_enterprise_plan"))
				respond(ctx, http.StatusOK, nil)
				return
			}

			doc := &orgRunnerStateChangeDocument{
				OrgID:             tenantID,
				Org:               owner.Organization.Name,
				runnerStateChange: *in,
				auditLogDefaults:  defaults,
			}
			if owner.Business != nil {
				doc.BusinessID = owner.Business.ID
				doc.Business = owner.Business.Name
			}

			out = doc
		case Enterprise:
			defaults.Action = fmtAction("enterprise", state)

			out = &enterpriseRunnerStateChangeDocument{
				BusinessID:        tenantID,
				runnerStateChange: *in,
				auditLogDefaults:  defaults,
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
}

func fmtAction(owner, state string) string {
	return fmt.Sprintf("%v.self_hosted_runner_%v", owner, state)
}
