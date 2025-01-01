package config

import (
	"errors"
	"os"
	"strings"

	"github.com/Shopify/sarama"
	"github.com/github/go-config/v2"
	"github.com/github/go-kvp"
	"github.com/github/go-log"
	"github.com/github/go-stats"
	ghhydro "github.com/github/hydro-client-go/v3/pkg/hydro"

	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/utils/roundtrippers"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/logger/kafkalog"
	"github.com/github/launch/observability/statter"
)

// Config wraps the environment variables for launch's Hydro consumer.
type Config struct {
	launchconfig.CommonConfig

	// Twirp connection settings
	DeployerTwirpAddr string `config:",env=DEPLOYER_TWIRP_ADDR,required"`
	InternalAddr      string `config:",env=INTERNAL_ADDR,required"`

	// The secret to use to sign requests to deployer for HMAC verification.
	// This should match one of the secrets in Deployer's DEPLOYER_HMAC_VERIFY_SECRETS
	DeployerHMACSigningSecret string `config:",env=DEPLOYER_HMAC_SECRET,required"`

	// HEAVEN_DEPLOYED_ENV
	DeployedTo string `config:",env=HEAVEN_DEPLOYED_TO"`

	// Hydro configuration
	KafkaBrokers    string `config:",env=KAFKA_BROKERS,required"`
	KafkaGroup      string `config:",env=KAFKA_GROUP,required"`
	KafkaVersion    string `config:",env=KAFKA_VERSION"`
	KafkaTLSEnabled bool   `config:"false,env=KAFKA_TLS_ENABLED"`
	KafkaCABundle   string `config:",env=KAFKA_CERT_PATH"`

	// Exceptions
	ReportingAddr string `config:",env=FAILBOT_HAYSTACK_URL"`

	// All the stuff needed to make a twirp client
	launchcache.CacheConfig
	launchredis.RedisConfig

	// The secret to use for HMAC verification to GitHub's Twirp API
	GitHubTwirpHMACSecret string `config:",env=GITHUB_TWIRP_HMAC_SECRET,required"`
	GitHubTwirpAddr       string `config:",env=GITHUB_TWIRP_ADDR,required"`

	BreakerConfig abreaker.Config
	roundtrippers.RoundTripperConfig
}

// NewKafkaConfig creates a new Kafka configuration from the application
// configuration.
func (c *Config) NewKafkaConfig(log log.FieldLogger, stats stats.Client) (*ghhydro.KafkaConfig, error) {
	brokers := strings.Split(c.KafkaBrokers, ",")
	var logb []kvp.Field
	for _, b := range brokers {
		logb = append(logb, kvp.String("peer.service", b))
	}
	log.Debug("connecting to brokers", logb...)

	klog := kafkalog.AdaptFieldLoggerToKafkaLogger(log)
	ghhydro.SetKafkaLogger(klog)

	kafkaOptions := []ghhydro.KafkaConfigOption{
		ghhydro.WithKafkaStats(stats),
		ghhydro.WithKafkaLogger(klog),
		ghhydro.WithSaramaConfig(func(scfg *sarama.Config) {
			scfg.Consumer.Offsets.Initial = sarama.OffsetNewest
		}),
	}

	if c.KafkaTLSEnabled {
		if c.KafkaCABundle == "" {
			return nil, errors.New("missing cert path for Kafka")
		}

		kafkaOptions = append(kafkaOptions, ghhydro.WithRootCA(c.KafkaCABundle))
	}

	if c.LaunchMode == "enterprise" {
		kafkaOptions = append(kafkaOptions, ghhydro.WithKafkaVersion(c.KafkaVersion))
	}

	if c.LaunchEnv == "development" {
		// Use a kafka-lite compatible version for the local environment
		kafkaOptions = append(kafkaOptions, ghhydro.WithKafkaVersion("1.1.1"))
	}

	return ghhydro.NewKafkaConfig(brokers, kafkaOptions...)
}

func (c *Config) GetLogger() logger.Logger {
	return logger.New(&logger.Config{
		App:          "launch",
		Debug:        c.LogDebug,
		Hostname:     getHostName(),
		ReportURL:    c.ReportingAddr,
		LoggerConfig: c.LoggerConfig,
		FieldTags:    logger.DefaultFieldTags,
	})
}

func getHostName() string {
	if appHost, err := os.Hostname(); err == nil {
		return appHost
	}
	return "unknown"
}

func (c *Config) GetStatter(statsTags statter.Tags) statter.Statter {
	if c.IsEnterprise() {
		// https://github.com/github/c2c-actions-experience/issues/2982#issuecomment-661206260
		return statter.NullStatter()
	}

	statter := statter.New(&statter.Config{
		Addr:   c.StatsAddr,
		Prefix: c.StatsPrefix,
		Period: c.StatsPeriod,
		Tags:   statsTags,
	})
	statter.Start()

	return statter
}

// Load returns an instance of `Config` with the environment variables loaded
// into it.
func Load() (*Config, error) {
	cfg := &Config{}
	if err := config.Load(cfg); err != nil {
		return nil, err
	}

	return cfg, nil
}
