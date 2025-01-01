package cli

import (
	"os"
	"strings"

	"github.com/github/launch/pkg/mu"

	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/utils/appcontext"
)

// Application is like mu.starter, except that this one is exported.
type Application interface {
	// OnStartUp matches mu.starter.OnStartUp.
	OnStartUp(*mu.Service) error

	// ServiceName is the name of this launch service. It's used to differentiate this service's stats from the other launch services.
	ServiceName() string
}

// Environment returns the launch environment.
func Environment() string {
	return os.Getenv("LAUNCH_ENV")
}

// DeployedTo returns the name of the environment the application has been deployed to (e.g., 'canary', 'lab', 'production')
func DeployedTo() string {
	return fixDeployedTo(os.Getenv("HEAVEN_DEPLOYED_ENV"))
}

func fixDeployedTo(deployedTo string) string {
	if strings.Index(deployedTo, "/") > 0 {
		// Sentry does not accept a "/" in an environment name, so we will replace "/" with "-".
		// Replacing "/" with "-" allows us to differentiate between environments that have similar suffixes
		// e.g. lab/canary and production/canary become lab-canary and production-canary
		//
		// See https://github.com/github/sentry/issues/160 for more information on "/" limitation.
		trimmed := strings.Trim(deployedTo, "/")
		deployedTo = strings.ReplaceAll(trimmed, "/", "-")
	}

	return deployedTo
}

// RunMuService runs mu.
func RunMuService(app Application) {
	SetupLogging()
	ParseFlags()

	metadata := GetApplicationMetadata(app.ServiceName())

	mu.Run(&mu.Config{
		Name:         "launch",
		Application:  app,
		BuildVersion: metadata.BuildVersion,
		MuVersion:    MuVersion,
		StatsTags:    metadata.ObservabilityFields,
		// these also end up in error fields
		DefaultLogFields: appcontext.MapToLogFields(metadata.ObservabilityFields),
	})
}

func GetApplicationMetadata(serviceName string) appcontext.ApplicationMetadata {
	env := Environment()
	deployedTo := DeployedTo()

	return appcontext.ApplicationMetadata{
		ServiceName: serviceName,
		Environment: launchconfig.AppEnv(env),
		// these will always be set on logs, stats and errors (mu.logger.Report extracts
		// log fields)
		ObservabilityFields: map[string]string{
			"launch_service": serviceName,
			"launch_env":     launchconfig.EnvironmentTag(),
			"release":        BuildVersion,
			"deployed_to":    deployedTo, // Send the environment the application has been deployed to for Sentry integration
		},
		BuildVersion: BuildVersion,
		MuVersion:    MuVersion,
	}
}
