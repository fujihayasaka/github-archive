// Package main implements a Kafka consumer for processing repository creation events
package main

import (
	"context"
	"fmt"
	"os/signal"
	"syscall"

	"github.com/github/configsd/internal/db"
	"github.com/github/configsd/internal/hydro"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	dbConn, err := db.NewDbConnectionFromEnvironment()
	if err != nil {
		panic(fmt.Errorf("failed to create database connection: %w", err))
	}

	consumer, err := hydro.NewConsumer(dbConn, nil)
	if err != nil {
		panic(fmt.Errorf("failed to create consumer: %w", err))
	}

	defer consumer.Close(ctx)

	if err := consumer.ConsumeRepoCreationEvents(ctx, stop); err != nil {
		panic(fmt.Errorf("failed to consume repo creation events: %w", err))
	}
}
