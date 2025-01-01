package config

import (
	"context"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	gitMock "github.com/github/dependency-snapshots-api/internal/gitaccess/mock"
	"github.com/github/dependency-snapshots-api/internal/gitaccess/spokes"
	"github.com/github/dependency-snapshots-api/internal/httputil"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-config"
	"github.com/github/go-config/env"
	"github.com/github/go-config/snakecaser"
	"github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	"github.com/github/go-stats"
	"github.com/go-sql-driver/mysql"
	"github.com/pkg/errors"
)

const (
	prodEnv        = "production"
	developmentEnv = "development"
	proximaEnv     = "proxima"
	ghesEnv        = "ghes"
	labEnv         = "lab"
)

// Config holds application configuration, including statting and tracing configs.
type Config struct {
	HTTPPort            int    `config:"9097,env=APP_PORT"`
	ServiceName         string `config:"dependency-snapshots-api,env=APP_NAME"`
	Environment         string `config:"development,env=APP_ENV"`
	DeployedEnvironment string `config:"development,env=HEAVEN_DEPLOYED_ENV"`
	SHA                 string `config:",env=APP_SHA"` // Moda runtime SHA
	Ref                 string `config:",env=APP_REF"` // Moda runtime ref
	BuildCommit         string // build-time commit SHA, supplied from main during Load

	StatsAddr   string        `config:",env=STATS_ADDR"`
	StatsPeriod time.Duration `config:"10s,env=STATS_PERIOD"`

	DB                string `config:"dependency_snapshots_development,env=DEPENDENCY_SNAPSHOTS_DB"`
	DBHost            string `config:"localhost,env=DEPENDENCY_SNAPSHOTS_DB_HOST"`
	DBPassword        string `config:",env=DEPENDENCY_SNAPSHOTS_DB_PASSWORD"`
	DBPort            string `config:"3001,env=DEPENDENCY_SNAPSHOTS_DB_PORT"`
	DBUsername        string `config:"root,env=DEPENDENCY_SNAPSHOTS_DB_USERNAME"`
	DBIdleConnections int    `config:"64,env=DEPENDENCY_SNAPSHOTS_DB_IDLE_CONNECTIONS"`
	DBMaxConnections  int    `config:"64,env=DEPENDENCY_SNAPSHOTS_DB_MAX_CONNECTIONS"`

	AzureStorageBlobEndpoint string `config:"http://127.0.0.1:20100/devstoreaccount1,env=AZURE_STORAGE_BLOB_ENDPOINT"`

	// In dev/CI we use Azurite in Docker for the blob store, but a *real* public instance
	// of CosmosDB. For dev, these env vars are set on repo in Codespaces/Actions Secrets
	CosmosURI                string `config:",env=COSMOSDB_URI"`
	CosmosAccountKey         string `config:",env=COSMOSDB_ACCOUNT_KEY"`
	CosmosReadOnlyEnabled    bool   `config:"false,env=COSMOSDB_RO_ENABLED"`
	CosmosReadOnlyURI        string `config:",env=COSMOSDB_RO_URI"`
	CosmosReadOnlyAccountKey string `config:",env=COSMOSDB_RO_ACCOUNT_KEY"`
	cosmosDBName             string // NOT used in Load (priv) just a cache for env-scoped, generated DB name

	// Configurations for Moda-deployed (staging, production) services' Spokes API backed Git operations
	SpokesURL      string `config:"http://127.0.0.1:28081,env=SPOKES_URL"`
	SpokesKey      string `config:",env=SPOKES_API_KEY"`
	SpokesCert     string `config:",env=SPOKES_API_CERT"`
	SpokesCABundle string `config:",env=SPOKES_API_CA_BUNDLE"`

	SkeemaFile string `config:"schemas/.skeema,env=SKEEMA_FILE"`

	ChatopsBaseURL      string `config:"http://localhost:9597/,env=CHATOPS_BASE_URL"`
	ChatopsBotPublicKey string `config:",env=CHATOPS_BOT_PUBLIC_KEY"`

	HMACKey string `config:"dependencysnapshotshmac,env=DEPENDENCY_SNAPSHOTS_API_HMAC_KEY"`
	// If you, a developer, want to force HMAC to be checked even on your local
	DevForceHmacAuthentication bool `config:"false,env=DEV_FORCE_HMAC_AUTHENTICATION"`

	// MonolithTwirpURL is the URL of the Monolith's Twirp RPC interfaces.
	// Examples:
	// - https://internal-api.service.iad.github.net/internal (production)
	// - https://api.github.localhost/internal                (tests)
	MonolithTwirpURL string `config:"https://api.github.localhost:3000/internal,env=MONOLITH_TWIRP_URL"`

	// MonolithTwirpHMACKey is the key used to create the HMAC required by the monolith-twirp RPC interfaces.
	// The value for production comes from Vault; see https://github.com/github/security-iam/issues/5001.
	MonolithTwirpHMACKey string `config:"launchhmac,env=MONOLITH_TWIRP_HMAC_KEY"`

	// Use a mocked version of Spokes for local development
	DevStandaloneMode bool `config:"false,env=DEV_STANDALONE_MODE"`
	// For the mocked Spokes, set a minimum response time. Maximum is 3x the minimum.
	DevSpokesDelayMs int `config:"50,env=DEV_SPOKES_DELAY_MS"`

	// Address of freno
	FrenoAddr string `config:",env=FRENO_ADDR"`
	// Cluster that freno is monitoring
	FrenoCluster string `config:",env=FRENO_CLUSTER"`

	// True if DS-API is running in an enterprise environment, false otherwise
	Enterprise bool `config:"false,env=ENTERPRISE"`

	// We may want to output statistics to the terminal when running locally, if so, enable this
	DevUseConsoleStatter bool `config:"false,env=USE_CONSOLE_STATTER"`
}

var portFlag = flag.Int("port", 9597, "port number to run http server on")

// Load parses configuration from the environment and places it in a newly
// allocated Config struct.
func Load(buildCommit string) (*Config, error) {
	flag.Parse()

	cfg := &Config{
		HTTPPort:    *portFlag,
		BuildCommit: buildCommit,
	}

	// The go-config library has some magic that naively tries to determine if a "Key" (could be config struct field name or the env= value if specified)
	// should be massaged into an environment variable. For real struct field names, the behavior needs to be preserved. Since the library is out in the wild
	// and changing the behavior might surprise someone down the road, we have our own crappy naive patch -- assume that underscores are meant to indicate a
	// literal environment variable name.
	var literalExceptionCaser = func(s string) string {
		if strings.Contains(s, "_") {
			return s
		}

		return snakecaser.Do(s)
	}

	loader := env.New(env.SnakeCaser(literalExceptionCaser))
	if err := config.Load(cfg, loader); err != nil {
		return nil, err
	}

	if cfg.Enterprise && cfg.Environment == "" {
		// uses the default logger since we don't have a context here
		log.Info("APP_ENV environment variable is not set, setting to 'ghes'")
		cfg.Environment = ghesEnv
	}

	return cfg, nil
}

var once = sync.Once{}

func (cfg *Config) IsGHES() bool {
	return cfg.Environment == ghesEnv
}

func (cfg *Config) IsProxima() bool {
	return cfg.Environment == proximaEnv
}

func (cfg *Config) IsDevelopment() bool {
	return cfg.Environment == developmentEnv
}

func (cfg *Config) IsLab() bool {
	return cfg.Environment == labEnv
}

func (cfg *Config) IsProduction() bool {
	return cfg.Environment == prodEnv
}

// See https://github.com/github/dependency-graph/issues/2463#issuecomment-1706253978
// for an explanation of why we are not using the same Vault keys across environments.
func (cfg *Config) GetAzureSPNEnvVar() string {
	envvar := "spn_dependency_snapshots_api"
	if cfg.IsProxima() {
		envvar += "_" + strings.ReplaceAll(cfg.DeployedEnvironment, "-", "_")
	}
	return envvar
}

// SPN is a service principal name. Our was created like this: https://github.com/github/azure-rbac/pull/161.
// SPNs are how we authenticate to azure resources. Roles should be configured via terraform templates.
func (cfg *Config) GetAzureSPN() (creds struct {
	Key      string
	ClientID string
	TenantID string
}) {
	envvar := cfg.GetAzureSPNEnvVar()
	creds.Key = os.Getenv(envvar)
	creds.TenantID = os.Getenv(fmt.Sprintf("%s_tenant_id", envvar))
	creds.ClientID = os.Getenv(fmt.Sprintf("%s_client_id", envvar))
	return
}

// InitDefaultLogger initializes a default logger object.
func (cfg *Config) InitDefaultLogger() (err error) {
	once.Do(func() {
		logger, e := log.NewFromEnv()
		if e != nil {
			err = e
			return
		}
		l := logger.WithFields(
			kvp.String("build.version", cfg.BuildCommit),
			kvp.String("app.environment", cfg.Environment),
			kvp.String("deployment.environment", cfg.DeployedEnvironment))
		log.SetDefault(l)
	})
	return err
}

// NewExceptionReporter configures a new exceptions reporter based on the config.
// It prints reports to stdout in development environment, but sends them to
// Failbotg (which is proxied to Sentry) in production.
func (cfg *Config) NewExceptionReporter() (*exceptions.Reporter, error) {
	var exporter exceptions.Exporter = writer.NewExporter(os.Stdout)

	if !cfg.IsDevelopment() {
		contextlogger.Info(context.Background(), "replacing multiexporter with outbound HTTP exporter for FailbotG reporting")
		httpExporter, err := httpexporter.NewExporter()
		if err != nil {
			return nil, err
		}

		stdErrExporter := writer.NewExporter(os.Stderr)
		exporter = exceptions.MultiExporter(httpExporter, stdErrExporter)
	}

	return exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication(cfg.ServiceName),
		exceptions.WithStacktraceFunc(RootCauseStackTracer),
		exceptions.WithValues(map[string]string{
			"deployed_to":     cfg.DeployedEnvironment,
			"app_environment": cfg.Environment,
			"release":         cfg.SHA,
			"ref":             cfg.Ref,
		}),
	)
}

// NewStatsClient generates a new statter for use with DataDog.
func (cfg *Config) NewStatsClient() (stats.Client, error) {
	if cfg.DevUseConsoleStatter {
		return ConsoleLoggingStatter, nil
	}
	if cfg.StatsAddr == "" {
		return stats.NullStatter, nil
	}

	sink, err := stats.NewUDPSink(cfg.StatsAddr)
	if err != nil {
		return stats.NullStatter, err
	}
	tags := stats.Tags{"app_env": cfg.Environment, "deployed_env": cfg.DeployedEnvironment}
	client := stats.NewClient(sink, cfg.StatsPeriod, cfg.ServiceName).WithTags(tags)

	if cfg.Enterprise {
		client = stats.NewCollectdClient(client)
	}

	return client, nil
}

func (cfg *Config) NewGitAccessClient() (gitaccess.Client, error) {
	defaultHeaders := http.Header{
		"User-Agent": {fmt.Sprintf("%s/%s", cfg.ServiceName, cfg.DeployedEnvironment)},
	}

	switch {
	case cfg.DevStandaloneMode:
		contextlogger.Info(context.Background(), "Using mock GitAccess client")
		return gitMock.NewClient(cfg.DevSpokesDelayMs), nil

	case cfg.IsDevelopment(), cfg.IsProxima():
		contextlogger.Info(context.Background(), "Attempting to create un-authenticated GitAccess client")

		httpClient, err := httputil.NewClient(defaultHeaders)
		if err != nil {
			return nil, errors.Wrapf(err, "failed to create HTTP client for Spokes Twirp API")
		}

		return spokes.NewClient(cfg.SpokesURL, httpClient, cfg.DevStandaloneMode)

	default:
		contextlogger.Info(context.Background(), "Attempting to create Spokes-backed GitAccess client")

		// initial swipe - mostly using defaults that have served well from here:
		// https://github.com/hashicorp/go-cleanhttp/blob/master/cleanhttp.go
		httpClient, err := httputil.NewClient(
			defaultHeaders,
			httputil.WithTLSFromEnv(cfg.SpokesKey, cfg.SpokesCert, cfg.SpokesCABundle),
			httputil.WithKeepAlive(30*time.Second),
			httputil.WithConnectTimeout(30*time.Second),
			httputil.WithMaxIdleConns(100),
			httputil.WithIdleConnTimeout(90*time.Second),
			httputil.WithTLSHandshakeTimeout(10*time.Second),
		)
		if err != nil {
			return nil, errors.Wrapf(err, "failed to create HTTP client for Spokes Twirp API")
		}
		return spokes.NewClient(cfg.SpokesURL, httpClient, cfg.DevStandaloneMode)
	}
}

// Replicate scoped CosmosDB database naming used in paved path dev; for
// prod/Proxima/GHES, and in Actions/CI, we can use fixed, env-based name
func (cfg *Config) GenerateCosmosDBDatabaseName() (string, error) {
	if len(cfg.cosmosDBName) > 0 {
		return cfg.cosmosDBName, nil
	}

	if !cfg.IsDevelopment() {
		cfg.cosmosDBName = fmt.Sprintf("%s_db", strings.ToLower(cfg.DeployedEnvironment))
		return cfg.cosmosDBName, nil
	}

	// envs that require additional per-branch scoping
	var prefix string
	switch {
	case len(os.Getenv("GITHUB_ACTION")) > 0:
		// Actions env only needs one container per branch
		prefix = "actions_"
	case len(os.Getenv("CI")) > 0:
		// CI env only needs one container per branch
		prefix = "ci"
	case len(os.Getenv("GITHUB_USER")) > 0:
		// dev users need their own container per branch
		prefix = os.Getenv("GITHUB_USER")
	case runtime.GOOS == "darwin" && len(os.Getenv("USER")) > 0:
		// NOTE: laptop devs need to set their own COSMOSDB_* env vars too!
		prefix = os.Getenv("USER")
	default:
		return "", errors.New("expected GITHUB_ACTION, GITHUB_USER, and/or CI env vars unset; is this a dev/CI env?")
	}

	// shell out to obtain branch name and format it for CosmosDB use
	gitPath, err := exec.LookPath("git")
	if err != nil {
		return "", errors.Wrapf(err, "failed to locate Git binary for CosmosDB database name gen")
	}
	rawBranch, err := exec.Command(gitPath, "branch", "--show-current").Output()
	if err != nil {
		return "", errors.Wrapf(err, "failed to obtain Git branch name for CosmosDB database name gen")
	}
	// ditch newline and slashes for use as container name suffix
	branch := strings.Replace(strings.Replace(string(rawBranch), "\n", "", -1), "/", "-", -1)

	// format the scoped collection name
	cfg.cosmosDBName = fmt.Sprintf("%s_%s", prefix, branch)
	return cfg.cosmosDBName, nil
}

func (cfg *Config) NewMysqlConfig() *mysql.Config {
	dbCfg := mysql.NewConfig()

	dbCfg.User = cfg.DBUsername
	dbCfg.Passwd = cfg.DBPassword
	dbCfg.Net = "tcp"
	dbCfg.Addr = net.JoinHostPort(cfg.DBHost, cfg.DBPort)
	dbCfg.DBName = cfg.DB

	dbCfg.ParseTime = true
	dbCfg.MultiStatements = true
	dbCfg.InterpolateParams = true
	dbCfg.Params = map[string]string{
		"sql_mode": "'STRICT_ALL_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,NO_AUTO_VALUE_ON_ZERO,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'",
	}
	return dbCfg
}

// builds off pkgerrors.NewStackTracer, but uses the innermost wrapped error's stack trace
// to ensure we get the trace closest to where the error occurred logged in Sentry
func RootCauseStackTracer(err error) ([]exceptions.StackTrace, string) {
	if err == nil {
		return nil, ""
	}

	// used to identify private types in github.com/pkg/errors
	type unwrappable interface {
		Unwrap() error
	}
	type stacktraceable interface {
		StackTrace() errors.StackTrace
	}

	// see also: https://github.com/github/go-exceptions/blob/main/stacktracers/pkgerrors/pkgerrors.go
	// almost right, but only unwraps one layer, missing the originating trace
	fn := pkgerrors.NewStackTracer()

	// recursively unwrap github.com/pkg/errors to find the "leaf node"
	// with the stack trace closest to where the error originally happened
	innermostErrWithTrace := err
	for {
		if unwrappableErr, ok := err.(unwrappable); ok {
			unwrappedErr := unwrappableErr.Unwrap()
			err = unwrappedErr

			// BEWARE! innermost wrapped errors (including *errors.fundamental and *errors.withMessage!)
			// will NOT contain a stack trace: https://github.com/pkg/errors/blob/master/errors.go#L181-L213
			// must capture the *innermost wrapped error that includes a trace*
			if _, ok := unwrappedErr.(stacktraceable); ok {
				innermostErrWithTrace = unwrappedErr
			}
		} else {
			break
		}
	}

	return fn(innermostErrWithTrace)
}
