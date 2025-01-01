package main

import (
	"time"

	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/aqueduct"
	"github.com/github/notifyd/internal/pkg/config/deployment"
	"github.com/github/notifyd/internal/pkg/job/middlewares/retries"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Config represents the configuration for the delete-repository worker.
type Config struct {
	// [development, test, production]
	// TODO: @mrtazz 2022/12/16: We have an issue open at
	// https://github.com/github/notifyd/issues/2148 to remove this
	Environment string `config:",env=APP_ENV"`

	// MySQL database
	Database mysql.Config

	StatsdAddr            string `config:",env=STATSD_ADDR"`
	ExceptionHTTPExporter bool   `config:"false,env=EXCEPTION_HTTP_EXPORTER"`

	Deployment deployment.Config

	PprofAddr string `config:":8081,env=PPROF_ADDR"`

	ShutdownTimeout time.Duration `config:"25s,env=SHUTDOWN_TIMEOUT"`

	// Telemetry
	Telemetry telemetry.Config

	// Aqueduct
	AqueductClient  aqueduct.ClientConfig
	AqueductWorker  aqueduct.WorkerConfig
	AqueductRetries retries.Config

	// Tenancy
	Tenancy tenancy.Config
}
