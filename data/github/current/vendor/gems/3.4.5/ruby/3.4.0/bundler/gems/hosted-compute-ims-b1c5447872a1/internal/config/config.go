package config

import (
	"fmt"

	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/resources"
	"github.com/github/hosted-compute-ims/internal/twirp"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_runner"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_token"
	"github.com/github/hosted-compute-ims/internal/worker"

	"github.com/github/go-config"
	"github.com/github/hosted-compute-core/oidc"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/store/mysql"
)

type Config struct {
	Env          string `config:"development,env=ENVIRONMENT"`
	ServiceName  string `config:"hosted-compute-ims,env=SERVICE_NAME"`
	BuildVersion string `config:",env=HEAVEN_DEPLOYED_SHA"`

	Telemetry    telemetry.Config    // Embed the telemetry.Config struct
	Resources    resources.Config    // Embed the resources.Config struct
	Azure        azure.Config        // Embed the azure.Config struct
	MySQL        mysql.Config        // Embed the mysql.Config struct
	TwirpServer  twirp.Config        // Embed the twirp.Config struct
	Worker       worker.Config       // Embed the worker.Config struct
	VssfAuth     oidc.Config         // Embed the oidc.Config struct for VSSF authentication
	FeatureFlags featureflags.Config // Embed the featureflags.Config struct
	Runner       vssf_runner.Config  // Embed the runner.Config struct
	Token        vssf_token.Config   // Embed the runner.Config struct
}

func (c *Config) Load() error {
	if err := config.Load(c); err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	c.VssfAuth = oidc.Config{}
	if err := c.VssfAuth.Load(); err != nil {
		return fmt.Errorf("failed to load oidc config: %w", err)
	}
	c.VssfAuth.Enabled = c.TwirpServer.VssfAuthEnabled

	c.Token = vssf_token.Config{}
	if err := c.Token.Load(); err != nil {
		return fmt.Errorf("failed to load token config: %w", err)
	}

	c.Runner = vssf_runner.Config{}
	if err := c.Runner.Load(); err != nil {
		return fmt.Errorf("failed to load runner config: %w", err)
	}

	return nil
}
