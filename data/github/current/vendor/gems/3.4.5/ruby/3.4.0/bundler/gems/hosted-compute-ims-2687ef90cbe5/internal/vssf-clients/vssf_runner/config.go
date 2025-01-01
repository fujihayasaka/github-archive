package vssf_runner

import (
	"fmt"

	"github.com/github/go-config"
)

type Config struct {
	InstanceFallback     string   `config:"http://runner.codedev.ms/servicedeployments/runner1/,env=KNOWN_RUNNER_INSTANCE"` // Used for testing by setting a fully qualified runner instance
	RunnerInstanceNames  []string `config:",env=RUNNER_INSTANCE_NAMES"`
	KnownRunnerInstances []string
}

func (c *Config) Load() error {
	err := config.Load(c)
	if err != nil {
		return err
	}

	c.KnownRunnerInstances = make([]string, 0)
	for _, instanceName := range c.RunnerInstanceNames {
		instanceUrl := fmt.Sprintf("https://%s.actions.githubusercontent.com/", instanceName)
		c.KnownRunnerInstances = append(c.KnownRunnerInstances, instanceUrl)
	}

	if len(c.KnownRunnerInstances) == 0 {
		c.KnownRunnerInstances = append(c.KnownRunnerInstances, c.InstanceFallback)
	}

	return nil
}
