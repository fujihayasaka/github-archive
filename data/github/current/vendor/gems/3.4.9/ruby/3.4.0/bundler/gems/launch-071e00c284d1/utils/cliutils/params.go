package cliutils

import (
	"github.com/github/launch/pkg/launchconfig"
)

func ParseEnv(env string) (string, error) {
	if env == "" {
		return launchconfig.ProductionAppEnv.String(), nil
	}
	appEnv, err := launchconfig.ParseEnv(env)
	return appEnv.String(), err
}
