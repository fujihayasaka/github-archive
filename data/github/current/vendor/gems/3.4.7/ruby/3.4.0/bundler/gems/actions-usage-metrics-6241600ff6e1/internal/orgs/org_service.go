package orgs

import (
	"context"
	"time"

	"github.com/github/actions-usage-metrics/internal/projections/org_names"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
)

type orgService struct {
	OrgService
	telem *telemetry.Telemetry
}

func successTags() stats.Tags { return stats.Tags{telemetry.StatusKey: telemetry.SuccessStatus} }
func failTags() stats.Tags    { return stats.Tags{telemetry.StatusKey: telemetry.FailedStatus} }

type OrgService interface {
	// Returns a map of ID to name
	GetOrgNames(ctx context.Context, scope *proto.Scope, orgIds []int64) (map[int64]string, error)
}

var service *orgService = nil

func SetOrgService(telem *telemetry.Telemetry) {
	service = &orgService{telem: telem}
}

func GetOrgService() OrgService {
	return service
}

func (r *orgService) GetOrgNames(ctx context.Context, scope *proto.Scope, ids []int64) (map[int64]string, error) {
	ctx, span := telemetry.Trace(ctx, "orgService.GetOrgNames")
	defer span.End()
	logger := r.telem.Logger.WithContext(ctx)

	distinctIds := utils.RemoveDuplicates(ids)

	if scope.ScopeType != proto.ScopeType_SCOPE_TYPE_ENTERPRISE {
		// if this is not enterprise level then we don't need to resolve any orgs because org names are not included in any output

		// return empty map
		return make(map[int64]string), nil
	}

	kustoOrgs, err := getAllOrgsKusto(ctx, r.telem, scope)
	if err != nil {
		r.telem.Logger.WithError(err)
		return nil, err
	}

	result := make(map[int64]string)

	for _, id := range distinctIds {
		name, ok := kustoOrgs[id]
		if ok {
			result[id] = name
		} else {
			// org creation + set up repo + set up workflows to run => this seems like it would happen more rarely than repos
			// just leave a note in case it does happen for now
			result[id] = "UNKNOWN - Please allow up to 72 hours after org creation for name to appear"
			logger.Warn("Failed to find org id", kvp.Int64(telemetry.OTelKeyOrgId, id))
			r.telem.Stats.Counter(telemetry.OrgsFindByIdMissingCount_StatsKey, nil, 1)
		}
	}

	return result, nil
}

// Fetch all orgs from kusto and return map of id -> name. For org scope only returns 1 result
func getAllOrgsKusto(ctx context.Context, telem *telemetry.Telemetry, scope *proto.Scope) (map[int64]string, error) {
	ctx, span := telemetry.Trace(ctx, "orgService.getAllOrgsKusto")
	defer span.End()
	logger := telem.Logger.WithContext(ctx)
	start := time.Now()
	kusto_result, err := org_names.QueryOrgNames(ctx, scope)
	if err != nil {
		return nil, err
	}

	logger.Info("orgService.getAllOrgsKusto received orgs from kusto:", kvp.Int(telemetry.OTelKeyLength, len(kusto_result.Items)))

	result := make(map[int64]string)

	for _, org := range kusto_result.Items {
		result[org.Id] = org.Name
	}

	duration := time.Since(start)
	logger.Info("orgService.getAllOrgsKusto total duration", kvp.Duration(telemetry.OTelKeyDuration, duration))
	telem.Stats.DistributionMs(telemetry.OrgsGetAllDuration_StatsKey, nil, duration)

	return result, nil
}
