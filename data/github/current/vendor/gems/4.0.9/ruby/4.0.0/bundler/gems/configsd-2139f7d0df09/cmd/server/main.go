// Package main creates an example GitHub HTTP server
package main

import (
	"context"
	"fmt"
	"os/signal"
	"syscall"

	"github.com/github/go-server/hosting/httphost"
	"github.com/github/go-server/hosting/httphost/twirpapi"

	"github.com/github/configsd/internal/db"
	"github.com/github/configsd/internal/readiness"
	"github.com/github/configsd/internal/twirpapi/configs"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	httpSvr, err := twirpapi.NewHost(
		twirpapi.WithPollingReadinessCheck(readiness.NewSimpleReadinessCheck()),
		twirpapi.WithHMACKeys(httphost.LoadHMACKeys()...),
	)
	if err != nil {
		// Can't use the logger here since there's not guarantee it's been initialized correctly
		panic(fmt.Errorf("failed to create HTTP server: %w", err))
	}

	conn, err := db.NewDbConnectionFromEnvironment()
	if err != nil {
		httpSvr.Logger().WithError(err).Fatal("Failed to create database connection")
	}
	defer conn.Close()

	store, err := db.NewStore(conn, nil)
	if err != nil {
		httpSvr.Logger().WithError(err).Fatal("Failed to create database store")
	}

	service := configs.NewConfigsService(store)
	httpSvr.Handle(configs.NewConfigsServer(service, httpSvr.Hooks()))

	// Start the server
	if err := httpSvr.Run(ctx); err != nil {
		httpSvr.Logger().WithError(err).Error("Failed to run server")
		return
	}

	httpSvr.Logger().Info("Server stopped gracefully")
}
