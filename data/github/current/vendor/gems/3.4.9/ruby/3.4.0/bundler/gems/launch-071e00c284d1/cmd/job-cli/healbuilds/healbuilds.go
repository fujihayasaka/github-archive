package healbuilds

import (
	"context"
	"fmt"
	"runtime/debug"
	"sync/atomic"
	"time"

	errs "github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/freno"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/buildhealer"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/workerpool"
)

const (
	Success        = 0
	Failure        = 1
	Timeout        = time.Minute * 30
	WorkerPoolSize = 8
)

type Runner struct {
	from                time.Duration
	to                  time.Duration
	postbackGracePeriod time.Duration
	obs                 *observability.Observability
	wfbRepo             deployer.WorkflowBuildsRepository
	wfbRepoRO           deployer.WorkflowBuildsRepositoryReadOnly

	githubClientFactory  github.Factory
	ghTwirpClient        ghtwirp.Client
	serviceClientFactory azp.RepositoryClientFactory
	cacheClient          launchcache.HealingJobCache
	frenoClient          freno.Client
}

type HealCommandClients struct {
	GithubClientFactory  github.Factory
	GhTwirpClient        ghtwirp.Client
	ServiceClientFactory azp.RepositoryClientFactory
	FrenoClient          freno.Client
	CacheClient          launchcache.HealingJobCache
}

func New(from, to, postbackGracePeriod time.Duration, obs *observability.Observability, wfbRepo deployer.WorkflowBuildsRepository, wfbRepoRO deployer.WorkflowBuildsRepositoryReadOnly, clients *HealCommandClients) *Runner {
	return &Runner{
		from:                 from,
		to:                   to,
		postbackGracePeriod:  postbackGracePeriod,
		obs:                  obs,
		wfbRepo:              wfbRepo,
		wfbRepoRO:            wfbRepoRO,
		githubClientFactory:  clients.GithubClientFactory,
		ghTwirpClient:        clients.GhTwirpClient,
		serviceClientFactory: clients.ServiceClientFactory,
		frenoClient:          clients.FrenoClient,
		cacheClient:          clients.CacheClient,
	}
}

func (r *Runner) Run(ctx context.Context) int {
	defer func() {
		if rvr := recover(); rvr != nil {
			err, ok := rvr.(error)
			if !ok {
				err = fmt.Errorf("%v", rvr)
			}
			r.obs.Report(ctx, errs.Wrap(err, "panicked in healbuilds"), kvp.String("exception_detail", string(debug.Stack())))
		}
	}()

	ctx, cancel := context.WithTimeout(ctx, Timeout)
	defer cancel()

	if !r.canWriteToDatabases(ctx) {
		return Failure
	}

	workflows, err := r.getWorkflowsToHeal(ctx)
	if err != nil {
		r.obs.Error(ctx, "Failed to get workflows from the DB to heal", kvp.Err(err))
		return Failure
	}

	r.obs.Log(ctx, "Received workflows from getWorkflowsToHeal",
		kvp.Int("gh.launch.workflows.count", len(workflows)),
		kvp.Duration("gh.launch.from_seconds", r.from),
		kvp.Duration("gh.launch.to_seconds", r.to),
	)

	healCount, err := r.healWorkflows(ctx, workflows)
	if err != nil {
		r.obs.Error(ctx, "Failed to heal workflows", kvp.Err(err))
		return Failure
	}

	r.obs.Gauge(ctx, "healing.incomplete_workflows_count", statter.Tags{}, int64(len(workflows)))
	r.obs.Log(ctx, "heal_workflows",
		kvp.Int("gh.launch.workflows.count", len(workflows)),
		kvp.Int64("gh.launch.healed_workflows.count", healCount),
		kvp.Duration("gh.launch.from_seconds", r.from),
		kvp.Duration("gh.launch.to_seconds", r.to),
	)

	return Success
}

func (r *Runner) getWorkflowsToHeal(ctx context.Context) ([]deployer.DataForHealer, error) {
	result, ok, err := r.wfbRepoRO.GetWorkflowsToHeal(ctx, r.from, r.to)

	if err != nil {
		return nil, err
	}
	if !ok {
		return []deployer.DataForHealer{}, nil
	}

	return result, nil
}

func (r *Runner) healWorkflows(ctx context.Context, workflows []deployer.DataForHealer) (int64, error) {
	count := int64(0)
	healer := buildhealer.New(r.obs, r.githubClientFactory, r.ghTwirpClient, r.wfbRepo)
	workers := workerpool.NewPool(WorkerPoolSize, len(workflows), r.obs.Logger, r.obs.Statter)

	for _, w := range workflows {
		w := w // Create copy local to this loop
		err := workers.Run(ctx, "healbuild", func(jobCtx context.Context) error {
			ctx := appcontext.CopyRequestMetadata(jobCtx)

			var tenantID int64
			if w.GitHubTenantID != nil {
				tenantID = *w.GitHubTenantID
			}
			ctx, err := ghtenant.ContextWithTenantID(ctx, tenantID, launchconfig.IsMultiTenant())
			if err != nil {
				return errs.Wrap(err, "error creating tenant context")
			}

			if r.healWorkflow(ctx, buildhealer.WorkflowInfo(w), &healer, r.postbackGracePeriod) {
				atomic.AddInt64(&count, 1)
			}
			return nil
		})
		if err != nil {
			return 0, errs.Wrap(err, "error running workers")
		}
	}

	workers.Stop()
	return count, nil
}

func (r *Runner) canWriteToDatabases(ctx context.Context) bool {
	clustersCanWrite, err := r.frenoClient.CanWriteToClusters(ctx, freno.ChecksDBCluster, freno.LaunchDBCluster)
	if err != nil {
		r.obs.Error(ctx, "Failed to check Freno for clusters", kvp.Err(err))
		return false
	}

	for cluster, canWrite := range clustersCanWrite {
		if !canWrite {
			r.obs.Error(ctx, "Received do not write response from Freno for database cluster", kvp.String("cluster", cluster))
			return false
		}
	}

	return true
}
