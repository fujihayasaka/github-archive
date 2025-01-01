package deploy

import (
	"database/sql"

	"github.com/github/launch/auth"
	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/billingplatform"
	"github.com/github/launch/clients/ghinternal"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/clients/varz"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/resolver"
	"github.com/github/launch/pkg/schedulemanager"
	"github.com/github/launch/services/deploy/adminevents"
	"github.com/github/launch/services/deploy/workflowcanceler"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/workerpool"
	"github.com/github/launch/workflowbuild"
	azpbuild "github.com/github/launch/workflowbuild/azp"
	azpconf "github.com/github/launch/workflowbuild/azp/config"
)

// Config is the arguments passed to deploy.New.
type config struct {
	Hostname                   string
	DB                         *sql.DB
	Credz                      kredz.Client
	Varz                       varz.Client
	WorkflowBuilds             deployer.WorkflowBuildsRepository
	AZPResources               deployer.AzpResourcesRepository
	AZPResourcesLoader         deployer.AzpResourcesLoader
	Log                        logger.Logger
	Obs                        *observability.Observability
	Stats                      statter.Statter
	Events                     *events.Emitter
	ClientFactory              github.Factory
	Workers                    workerpool.Workers
	WorkflowCanceler           workflowcanceler.Canceler
	WorkflowSourceFactory      workflowinvoker.WorkflowSourceFactory
	AdminEventsReporter        adminevents.Reporter
	CustomersFolderID          string
	WorkflowFilePath           string
	AppID                      int64
	ScheduleManager            schedulemanager.Manager
	AppEnv                     launchconfig.AppEnv
	GithubTwirpClient          ghtwirp.Client
	GithubTwirpBillingClient   ghtwirp.Client
	AqueductClient             aqueduct.Client
	AqueductQueue              string
	AqueductApp                string
	InternalClientFactory      ghinternal.Factory
	Hydro                      events.Hydro
	Verifier                   auth.Verifier
	AzpClient                  azp.S2SClient
	KeyVaultClient             azp.KeyVaultClient
	AzureProviderConfig        azpconf.AzureProviderConfig
	TenantHandler              azpbuild.TenantHandler
	TokenFactory               workflowbuild.TokenFactory
	TokenService               tokens.Service
	JobsRepo                   deployer.JobsRepository
	ResolverTokenFactory       resolver.TokenFactory
	BillingPlatformTwirpClient billingplatform.Client
}
