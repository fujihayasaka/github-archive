package main

import (
	"context"
	"net"
	"testing"
	"time"

	"github.com/github/turboghas/internal/fromctx"
	"github.com/stretchr/testify/require"
)

func isAlive(addr string) bool {
	conn, err := net.DialTimeout("tcp", addr, time.Millisecond*10)
	if err != nil {
		return false
	}
	if err := conn.Close(); err != nil {
		return false
	}
	return true
}

func TestTurboghasBoots(t *testing.T) {
	done := make(chan struct{})
	ctx := fromctx.WithShutdown(context.Background(), done)
	// immediately shut down the context so that we just run through all the setup without
	// actually going into the service loop to start indefinitely listening for connections
	close(done)

	// check to see if Kakfa is available, if so also set up the processor.
	// to also start Kafka when spinning up Docker dependencies, use:
	// > docker compose --profile processor up --wait
	startProcessor := isAlive("localhost:9093")

	require.NoError(t, do(ctx, startProcessor))
}
