package notifier

import (
	"github.com/github/authnd/internal/common/config"
	goconfig "github.com/github/go-config"
	"github.com/pkg/errors"
)

const serviceName = "authnd-notifier"

// Config defines the configuration to run the notifier job.
type Config struct {
	config.CommonConfig
}

// NewConfigFromEnvironment parses configuration from the environment and
// places it in a newly allocated Config struct.
func NewConfigFromEnvironment() (*Config, error) {
	cfg := &Config{}
	if err := goconfig.Load(cfg); err != nil {
		return nil, errors.WithStack(err)
	}
	cfg.ServiceName = serviceName
	cfg.StatsPrefix = "authnd.notifier"

	return cfg, nil
}
