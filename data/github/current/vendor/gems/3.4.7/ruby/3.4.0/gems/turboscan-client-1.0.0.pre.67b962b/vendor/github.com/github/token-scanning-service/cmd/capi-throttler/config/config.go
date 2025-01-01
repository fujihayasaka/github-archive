package config

import (
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

type Config struct {
	// Deployment configuration
	ServiceName string `config:"capi-throttler,env=SERVICE_NAME"`
	ServerAddr  string `config:"localhost:5001,env=SERVER_ADDR"`

	// Heaven deployment variables
	Role        string `config:",env=APP_ROLE"`
	Sha         string `config:",env=HEAVEN_DEPLOYED_SHA"`
	Ref         string `config:",env=HEAVEN_DEPLOYED_REF"`
	DeployedEnv string `config:",env=HEAVEN_DEPLOYED_ENV"`

	// Stats config
	StatsAddr   string        `config:"127.0.0.1:8125,env=STATS_ADDR"`
	StatsPeriod time.Duration `config:"1ms,env=STATS_PERIOD"`

	// How many seconds per rebalancing cycle
	RebalanceInterval float64 `config:"600,env=REBALANCE_INTERVAL"`
}

func (c *Config) NewStatsClient() (stats.Client, error) {
	sink, err := stats.NewUDPSink(c.StatsAddr)
	if err != nil {
		return nil, err
	}
	statsClient := stats.NewClient(
		sink,
		c.StatsPeriod,
		c.ServiceName,
	)

	return statsClient.WithTags(c.StatsTags()), nil
}

// StatsTags returns the core set of stats tags to always include
func (c *Config) StatsTags() stats.Tags {
	tags := stats.Tags{}
	for key, value := range c.getDimensions() {
		if key != "ref" {
			tags[key] = value
		}
	}
	return tags
}

func (c *Config) ConfigureLogger(logger log.Logger) log.Logger {
	fields := make([]kvp.Field, 0, len(c.getDimensions()))
	for k, v := range c.getDimensions() {
		fields = append(fields, kvp.String(k, v))
	}
	return logger.WithFields(fields...)
}

func (c *Config) getDimensions() map[string]string {
	return map[string]string{
		"ref":          c.Ref,
		"release":      c.Sha,
		"app_role":     c.Role,
		"deployed_to":  c.DeployedEnv,
		"deployed_env": c.DeployedEnv,
	}
}
