package main

import (
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/config/deployment"
	"github.com/github/notifyd/internal/pkg/mysql"
)

// Config represents the configuration for the transition job.
type Config struct {
	// [development, test, production]
	// TODO: @mrtazz 2022/12/16: We have an issue open at
	// https://github.com/github/notifyd/issues/2148 to remove this
	Environment string `config:",env=APP_ENV"`

	// MySQL database
	Database mysql.Config

	StatsdAddr string `config:",env=STATSD_ADDR"`

	Deployment deployment.Config

	Telemetry telemetry.Config
}
