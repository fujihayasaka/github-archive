package config

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/github/billing-platform/internal/monolith"
	"github.com/github/billing-platform/lib/models"

	"github.com/github/github-telemetry-go/log"
	goconfig "github.com/github/go-config"
	exceptions "github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
)

var (
	instance *Config
)

// Config holds application configuration, including database and statting configs.
type Config struct {
	ServiceName string `config:"billing-platform,env=APP_NAME"`
	Environment string `config:"local,env=HEAVEN_DEPLOYED_ENV"`
	Sha         string `config:",env=APP_SHA"`
	Ref         string `config:",env=APP_REF"`

	StatsAddr   string        `config:"null,env=STATS_ADDR"`
	StatsPeriod time.Duration `config:"10s,env=STATS_PERIOD"`
	StatsPrefix string        `config:"billing-platform,env=STATS_PREFIX"`

	CSRFSecret     string `config:",env=ADMIN_CSRF_SECRET"`
	OktaHMACSecret string `config:",env=HMAC_SECRET_BILLING_PLATFORM_ADMIN_GITHUBAPP_COM"`

	DBReadOnlySPNTenantID     string `config:",env=BILLING_PLATFORM_DB_READ_ONLY_SPN_TENANT_ID"`
	DBReadOnlySPNClientID     string `config:",env=BILLING_PLATFORM_DB_READ_ONLY_SPN_CLIENT_ID"`
	DBReadOnlySPNClientSecret string `config:",env=BILLING_PLATFORM_DB_READ_ONLY_SPN_CLIENT_SECRET"`

	UseCosmosConnectionString         bool   `config:"false,env=USE_COSMOS_CONNECTION_STRING"`
	CosmosAccountEndpoint             string `config:",env=COSMOS_ACCOUNT_ENDPOINT"`
	DBConnectionString                string `config:",env=COSMOS_CONN_STR"`
	DBGatewayConnectionString         string `config:",env=COSMOS_GATEWAY_CONN_STR"`
	ReadOnlyDBConnectionString        string `config:",env=COSMOS_READ_ONLY_CONN_STR"`
	ReadOnlyDBGatewayConnectionString string `config:",env=COSMOS_READ_ONLY_GATEWAY_CONN_STR"`
	DatabaseName                      string `config:",env=COSMOS_DB"`
	ContainerName                     string `config:",env=COSMOS_CONTAINER"`
	DatabaseEndPoint                  string
	DatabaseKey                       string
	GatewayDatabaseEndPoint           string
	GatewayDatabaseKey                string
	ReadOnlyDatabaseEndPoint          string
	ReadOnlyDatabaseKey               string
	DisableCache                      bool `config:"false,env=DISABLE_CACHE"`
	IsProxima                         bool `config:"false,env=IS_PROXIMA"`

	HmacKeys string `config:",env=HMAC_KEYS"`
	SkipHmac bool   `config:"false,env=SKIP_HMAC"`

	HydroConsumerGroupID string `config:"billing-platform-development-consumer,env=HYDRO_CONSUMER_GROUP_ID"`
	HydroKafkaBrokers    string `config:"127.0.0.1:9092,env=HYDRO_KAFKA_BROKERS"`
	HydroKafkaCAPath     string `config:",env=HYDRO_KAFKA_CA_PATH"`

	// The AQUEDUCT_ADDRESS env variable will be over-written in production environments.
	// We keep this around for local development and testing.
	AqueductAddress       string `config:"http://localhost:18081,env=AQUEDUCT_ADDRESS"`
	AqueductApiKey        string `config:",env=AQUEDUCT_API_KEY"`
	AqueductApiKeyVersion int    `config:"0,env=AQUEDUCT_API_KEY_VERSION"`
	WorkerType            string `config:",env=WORKER_TYPE"`

	HTTPPort int `config:"8989,env=HTTP_PORT"`

	EnsureCollection bool `config:"true,env=ENSURE_COLLECTION"`

	commandArgs *CommandArgs

	RunLimited                       bool
	OverrideQueuePrefix              string
	NumberOfLimitedMessagesToProcess int

	FeatureFlagAPIHMAC   string `config:"billinghmac,env=MONOLITH_TWIRP_HMAC_KEY"`
	MonolithTwirpURL     string
	MonolithTwirpHMACKey string `config:"billinghmac,env=MONOLITH_TWIRP_HMAC_KEY"`

	AzureCommerceSasTokenSecretName string `config:"billingnonprod573dad-meusesasclient,env=AZURE_COMMERCE_SAS_TOKEN_SECRET_NAME"`
	AzureCommerceStorageAccountName string `config:"billingnonprod573dad,env=AZURE_COMMERCE_STORAGE_ACCOUNT_NAME"`
	AzureCommerceSpnClientId        string `config:"bb21a566-5f76-4c4c-8366-de4aa6c7fa56,env=AZURE_COMMERCE_SPN_CLIENT_ID"`
	AzureCommerceSpnClientSecret    string `config:",env=AZURE_COMMERCE_SPN_CLIENT_SECRET"` // This is a secret, so we don't want to track it
	AzureCommerceKeyVaultTenantId   string `config:"72f988bf-86f1-41af-91ab-2d7cd011db47,env=AZURE_COMMERCE_KEY_VAULT_TENANT_ID"`
	AzureCommerceKeyVaultName       string `config:"billingnonprod573dad,env=AZURE_COMMERCE_KEY_VAULT_NAME"`
	AzureCommerceKeyVaultUri        string
	AzureCommerceLocation           string
	AzureCommerceTableUri           string
	AzureCommerceTableListUri       string
	AzureCommerceQueueUri           string
	AzureCommerceErrorQueueUri      string

	CustomersWithDailyEmissionEnabled    string `config:",env=DAILY_EMISSION_CUSTOMER_IDS"`
	CustomersWithMonthlyEmissionDisabled string `config:",env=MONTHLY_EMISSION_CUSTOMER_IDS"`
	DailyEmissionsActiveDate             string `config:",env=DAILY_EMISSION_ACTIVE_DATE"`

	// in milliseconds
	ThrottledWatermarkItemsPerSecond int `config:"5,env=THROTTLED_WATERMARK_ITEMS_PER_WORKER_PER_SECOND"`

	KustoBlobExportStorageAccountEndpoint string `config:",env=KUSTO_BLOB_EXPORT_STORAGE_ACCOUNT_ENDPOINT"`
	KustoBlobExportContainerName          string `config:"billing-metered-exports-reports,env=KUSTO_BLOB_EXPORT_CONTAINER_NAME"`
	KustoEndpoint                         string `config:",env=KUSTO_ENDPOINT"`
	KustoSpnTenantId                      string `config:",env=KUSTO_SPN_TENANT_ID"`
	KustoSpnClientId                      string `config:",env=KUSTO_SPN_CLIENT_ID"`
	KustoSpnClientSecret                  string `config:",env=KUSTO_SPN_CLIENT_SECRET"`

	ZuoraApiURL       string `config:"https://rest.apisandbox.zuora.com,env=ZUORA_API_URL"`
	ZuoraClientID     string `config:"71368f9e-ff6b-4bbb-9858-ad0e5bc20796,env=ZUORA_CLIENT_ID"`
	ZuoraClientSecret string `config:",env=ZUORA_CLIENT_SECRET"`
}

var m = new(sync.RWMutex)

func LoadWithOptions(loadCommandLine bool) (*Config, error) {
	m.Lock()
	defer m.Unlock()

	if instance != nil {
		return instance, nil
	}

	if instance == nil {
		// initialize configuration
		cfg := &Config{}

		if err := goconfig.Load(cfg); err != nil {
			return nil, errors.Wrap(err, "failed to load configuration")
		}

		cfg.LoadAzureConfig()
		cfg.LoadMonolithConfig()

		// allow testing command line arguments to override default or pre-computed configuration values
		models.UtcNow = func() time.Time { return time.Now().UTC() }
		if !cfg.IsProduction() && loadCommandLine {
			commandArgs := getCommandLineFlags(cfg)

			if commandArgs.TimeTravel {
				models.UtcNow = func() time.Time {
					return commandArgs.TimeTravelDate
				}
			}
			if commandArgs.TestingCollectionName != "" {
				cfg.ContainerName = commandArgs.TestingCollectionName
			}

			if commandArgs.TestingDatabaseName != "" {
				cfg.DatabaseName = commandArgs.TestingDatabaseName
			}

			if commandArgs.ZuoraApiUrl != "" {
				cfg.ZuoraApiURL = commandArgs.ZuoraApiUrl
			}

			if commandArgs.MonolithTwirpServerURL != "" {
				cfg.MonolithTwirpURL = commandArgs.MonolithTwirpServerURL
			}

			cfg.RunLimited = commandArgs.RunLimited
			cfg.OverrideQueuePrefix = commandArgs.TestingQueueName
			cfg.NumberOfLimitedMessagesToProcess = commandArgs.NumberOfLimitedMessagesToProcess

			cfg.commandArgs = commandArgs
		}

		if err := cfg.LoadDB(); err != nil {
			return nil, err
		}

		if !cfg.IsProduction() {
			if err := cfg.LoadReadOnlyDB(); err != nil {
				return nil, err
			}
		}

		instance = cfg
	}

	return instance, nil
}

func RootPath() string {
	_, b, _, _ := runtime.Caller(0)

	// Root folder of this project
	root := filepath.Join(filepath.Dir(b), "../..")
	return root
}

func Load() (*Config, error) {
	return LoadWithOptions(true)
}

func (cfg *Config) LoadDB() error {
	accountKey, sdkUri, err := getElementsFromConnectionString(cfg.DBConnectionString)
	if err != nil {
		return err
	}

	cfg.DatabaseEndPoint = sdkUri
	cfg.DatabaseKey = accountKey

	// handle missing or invalid DBGatewayConnectionString or disabled cache by using the direct connection string values
	gatewayAccountKey, gatewaySdkUri, err := getElementsFromConnectionString(cfg.DBGatewayConnectionString)
	if err != nil || cfg.DisableCache {
		gatewayAccountKey = accountKey
		gatewaySdkUri = sdkUri
	}

	cfg.GatewayDatabaseEndPoint = gatewaySdkUri
	cfg.GatewayDatabaseKey = gatewayAccountKey

	return nil
}

func (cfg *Config) LoadReadOnlyDB() error {
	accountKey, accountEndpoint, err := getElementsFromConnectionString(cfg.ReadOnlyDBConnectionString)
	if err != nil {
		return err
	}

	cfg.ReadOnlyDatabaseEndPoint = accountEndpoint
	cfg.ReadOnlyDatabaseKey = accountKey

	return nil
}

func (cfg *Config) LoadAzureConfig() {
	cfg.setAzureLocationForEnvironment()
	cfg.AzureCommerceKeyVaultUri = fmt.Sprintf("https://%s.vault.azure.net", cfg.AzureCommerceKeyVaultName)
	cfg.AzureCommerceTableListUri = fmt.Sprintf("https://%s.table.core.windows.net/usages", cfg.AzureCommerceStorageAccountName)
	cfg.AzureCommerceTableUri = fmt.Sprintf("https://%s.table.core.windows.net/usages()", cfg.AzureCommerceStorageAccountName)
	cfg.AzureCommerceQueueUri = fmt.Sprintf("https://%s.queue.core.windows.net/usages", cfg.AzureCommerceStorageAccountName)
	cfg.AzureCommerceErrorQueueUri = fmt.Sprintf("https://%s.queue.core.windows.net/errors", cfg.AzureCommerceStorageAccountName)
}

func (cfg *Config) LoadMonolithConfig() {
	switch cfg.Environment {
	case "development":
		// we don't manually set aqueduct address here because we want to allow the use of
		// ENV vars to override it for different development environments
		cfg.MonolithTwirpURL = "http://api.github.localhost/internal"
	case "production", "production/canary":
		cfg.AqueductAddress = "https://aqueduct-gateway-production.service.iad.github.net"
		cfg.MonolithTwirpURL = "https://internal-api.service.iad.github.net/internal"
	default:
		// assume anything that makes it here is Proxima: staff-wus2-01, prod-weu-01, etc.
		cfg.AqueductAddress = fmt.Sprintf("https://aqueduct.service.%s.github.net", cfg.Environment)
		cfg.MonolithTwirpURL = fmt.Sprintf("https://internal-api.service.%s.github.net/internal", cfg.Environment)
	}
}

var errConnectionString = errors.New("connection string is either blank or malformed. The expected connection string should contain key value pairs separated by semicolons. For example 'AccountEndpoint=https://example.com;AccountKey=<accountKey>;")

func (cfg *Config) CurrentWorkerType() models.WorkerType {
	return models.WorkerType(cfg.WorkerType)
}

func (cfg *Config) ValidateWorkerConfig() error {
	if cfg.ContainerName == "" || cfg.DBConnectionString == "" || cfg.DatabaseName == "" {
		return errors.Errorf("invalid database connection")
	}

	if cfg.CurrentWorkerType() == models.UnknownWorkerType {
		return errors.Errorf("worker type must be set")
	}

	return nil
}

func (cfg *Config) ValidateBaseConfig() error {
	if cfg.ContainerName == "" || cfg.DBConnectionString == "" || cfg.DatabaseName == "" {
		return errors.Errorf("invalid database connection")
	}

	return nil
}

// ConfigureLogger configures the provided logger with the default settings
func (cfg *Config) ConfigureLogger(logger log.Logger, namespace string) log.Logger {
	// Set the default logger level based on the environment
	if cfg.IsProduction() {
		logger = logger.WithLevel(log.InfoLevel)
	} else {
		logger = logger.WithLevel(log.DebugLevel)
	}

	// Set the top-level namespace for the logger
	// Subsequent calls to logger.Named() will append to the scope
	// Example: logger.Named("TopLevel").Named("SubComponent")
	// Log Message:  InstrumentationScope=TopLevel.SubComponent
	logger = logger.Named(namespace)

	return logger
}

// NewExceptionReporter configures a new exceptions reporter based on the config.
// It prints reports to stderr in development environment, but sends them to
// Failbotg (which is proxied to Sentry) in production.
func (cfg *Config) NewExceptionReporter() (*exceptions.Reporter, error) {
	var err error
	var exporter exceptions.Exporter = writer.NewExporter(os.Stderr)

	if cfg.IsProduction() {
		exporter, err = httpexporter.NewExporter()
		if err != nil {
			return nil, errors.Wrap(err, "failed to initialize a new httpexporter")
		}
	}

	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication(cfg.ServiceName),
		exceptions.WithCatalogService("billing-platform"),
		exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		exceptions.WithValues(map[string]string{
			"deployed_to": cfg.Environment,
			"release":     cfg.Sha,
			"ref":         cfg.Ref,
		}),
	)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize exceptions reporter")
	}

	return reporter, nil
}

// StatsClient generates a new statter for use with DataDog.
func (cfg *Config) StatsClient() stats.Client {
	var statsClient stats.Client
	switch cfg.StatsAddr {
	case "stdout":
		statsClient = stats.NewClient(
			os.Stdout,
			cfg.StatsPeriod,
			cfg.StatsPrefix,
		)
	case "null":
		statsClient = stats.NullStatter
	default:
		statsClient = stats.NewClient(
			stats.UDPSink(cfg.StatsAddr),
			cfg.StatsPeriod,
			cfg.StatsPrefix,
		)
	}
	return statsClient
}

type statterKey string

const StatterKey statterKey = "per_request_statter"

func WithStatter(ctx context.Context, statter stats.Client) context.Context {
	return context.WithValue(ctx, StatterKey, statter)
}

func (cfg *Config) NewMonolithClient(ctx context.Context) (*monolith.Client, error) {
	return monolith.NewClient(&monolith.ClientConfig{
		Context: ctx,
		URL:     cfg.MonolithTwirpURL,
		HMACKey: cfg.MonolithTwirpHMACKey,
	})
}

func (cfg *Config) ParsedHydroKafkaBrokers() []string {
	return strings.Split(cfg.HydroKafkaBrokers, ",")
}

func (cfg *Config) SkipHmacForLocalDev() bool {
	return cfg.SkipHmac && (!cfg.IsProduction())
}

func (cfg *Config) IsRemoteNonProd() bool {
	return cfg.Environment == "development"
}

func (cfg *Config) IsProduction() bool {
	return cfg.Environment == "production" ||
		cfg.Environment == "production/canary" ||
		cfg.Environment == "staff-wus2-01" ||
		// match on all prod Proxima stamps
		strings.Contains(cfg.Environment, "prod-")
}

func (cfg *Config) IsLocal() bool {
	return cfg.Environment == "local"
}

func (cfg *Config) AqueductApplication() string {
	environment := "production"
	if !cfg.IsProduction() {
		// For anything that's not production, use "development" to match Rails.env in Dotcom
		environment = "development"
	}
	return fmt.Sprintf("%s-%s", "billing-platform", environment)
}

func getElementsFromConnectionString(connStr string) (string, string, error) {
	connStrMap, err := convertConnStrToMap(connStr)
	if err != nil {
		return "", "", err
	}

	accountKey, ok := connStrMap["AccountKey"]
	if !ok {
		return "", "", errors.Wrap(errConnectionString, "AccountKey not ok")
	}

	sdkUri, ok := connStrMap["AccountEndpoint"]
	if !ok {
		return "", "", errors.Wrap(errConnectionString, "AccountEndpoint not ok")
	}

	return accountKey, sdkUri, nil
}

// Borrowed from: https://github.com/Azure/azure-sdk-for-go/blob/main/sdk/data/aztables/connection_string.go
// TODO: file an upstream issue to request support for something like `azcosmos.NewClientWithConnectionString`?
// convertConnStrToMap converts a connection string (in format key1=value1;key2=value2;key3=value3;) into a map of key-value pairs
func convertConnStrToMap(connStr string) (map[string]string, error) {
	ret := make(map[string]string)
	connStr = strings.TrimRight(connStr, ";")

	splitString := strings.Split(connStr, ";")
	if len(splitString) == 0 {
		return nil, errors.New("connection string has no parts")
	}
	for _, stringPart := range splitString {
		parts := strings.SplitN(stringPart, "=", 2)
		if len(parts) != 2 {
			return nil, errors.Errorf("connection string has invalid format: %s", stringPart)
		}
		ret[parts[0]] = parts[1]
	}
	return ret, nil
}

func (cfg *Config) setAzureLocationForEnvironment() {
	switch cfg.Environment {
	case "staff-wus2-01":
		cfg.AzureCommerceLocation = "westus2"
	case "prod-weu-01":
		cfg.AzureCommerceLocation = "westeurope"
	case "prod-sdc-01":
		cfg.AzureCommerceLocation = "swedencentral"
	case "prod-ae-01":
		cfg.AzureCommerceLocation = "australiaeast"
	default:
		cfg.AzureCommerceLocation = "eastus"
	}
}
