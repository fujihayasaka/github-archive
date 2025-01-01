package main

import (
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/config/deployment"
	"github.com/github/notifyd/internal/pkg/mysql"
)

// Config represents the configuration for the migrate command.
type Config struct {
	// [development, test, production]
	// TODO: @mrtazz 2022/12/16: We have an issue open at
	// https://github.com/github/notifyd/issues/2148 to remove this
	Environment string `config:",env=APP_ENV"`
	Deployment  deployment.Config
	Telemetry   telemetry.Config
	Database    mysql.Config
}
