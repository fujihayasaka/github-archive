package scheduled

import (
	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/schedules"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/services/deploy/scheduled/config"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/workerpool"
)

type service struct {
	clientFactory     github.Factory
	githubTwirpClient ghtwirp.Client
	log               logger.Logger
	statter           statter.Statter
	cfg               config.ScheduledConfig
	store             schedules.Store
	worker            *worker
	isEnterprise      bool
}

func New(
	scheduleCfg config.ScheduledConfig,
	store schedules.Store,
	log logger.Logger,
	factory github.Factory,
	githubTwirpClient ghtwirp.Client,
	aqueductClient aqueduct.Client,
	statter statter.Statter,
	hostname string,
	metadata appcontext.ApplicationMetadata,
	isEnterprise bool,
	isMultiTenant bool,
	launchDependencyCache launchcache.LaunchDependencyCache,
) SubService {
	return &service{
		clientFactory:     factory,
		githubTwirpClient: githubTwirpClient,
		statter:           statter,
		log:               log,
		cfg:               scheduleCfg,
		store:             store,
		isEnterprise:      isEnterprise,
		worker: newWorker(
			hostname,
			store,
			log,
			scheduleCfg,
			statter,
			metadata,
			githubTwirpClient,
			aqueductClient,
			scheduleCfg.AqueductQueueScheduled,
			scheduleCfg.AqueductApp,
			isEnterprise,
			scheduleCfg.IsLab(),
			isMultiTenant,
			launchDependencyCache,
		),
	}
}

type SubService interface {
	RegisterWorkers(periodicWorker workerpool.Workers)
}

func (s *service) RegisterWorkers(periodicWorker workerpool.Workers) {
	periodicWorker.Periodically(s.cfg.LoopSleepDuration, "scheduleWorkerTick", s.worker.getTick())
	periodicWorker.Periodically(s.cfg.ReassignWorkAfterDuration, "scheduleUnlockStale", s.store.UnlockStale)
}
