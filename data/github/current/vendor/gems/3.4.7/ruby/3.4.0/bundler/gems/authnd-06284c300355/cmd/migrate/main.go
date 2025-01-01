package main

import (
	"os"

	"github.com/github/authnd/internal/migrate"
	"github.com/github/github-telemetry-go/log"
)

func main() {
	isEnteprise := os.Getenv("IS_ENTERPRISE_SERVER")
	if isEnteprise != "true" {
		log.Error("migrate cannot be run without IS_ENTERPRISE_SERVER=true")
		os.Exit(1)
	}

	if err := realMain(); err != nil {
		log.WithError(err).Error("failed to migrate successfully")
		os.Exit(1)
	}
}

func realMain() error {
	cfg, err := migrate.NewConfigFromEnvironment()
	if err != nil {
		return err
	}

	ctx, err := cfg.NewRootContext()
	if err != nil {
		return err
	}

	return migrate.RunMigrations(ctx, cfg, "./migrations")
}
