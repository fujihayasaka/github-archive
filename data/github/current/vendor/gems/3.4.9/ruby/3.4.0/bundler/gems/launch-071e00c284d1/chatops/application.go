package chatops

import (
	"github.com/github/go-chatops/v2/security"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/rate"

	"github.com/github/launch/services/pb/deploy"
)

// Application holds the application configuration and any other
// application global resources.
type Application struct {
	Logger            logger.Logger
	DeployerClient    deploy.LaunchDeploymentService
	GlobalIDMigrator  deployer.GlobalIDMigrator
	ActionsAppID      string
	ConfigSyncService rate.ConfigSyncService

	validator *security.Validator
	prompter  security.Prompter
}

// NewApplication creates a new Application.
func NewApplication(
	logger logger.Logger,
	deployerClient deploy.LaunchDeploymentService,
	gidMigrator deployer.GlobalIDMigrator,
	appID string,
	validator *security.Validator,
	prompter security.Prompter,
	configSyncService rate.ConfigSyncService) *Application {
	return &Application{
		Logger:            logger,
		DeployerClient:    deployerClient,
		GlobalIDMigrator:  gidMigrator,
		ActionsAppID:      appID,
		ConfigSyncService: configSyncService,
		validator:         validator,
		prompter:          prompter,
	}
}
