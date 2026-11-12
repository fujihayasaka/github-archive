package aqueduct

import (
	"context"
	"testing"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/require"
)

func TestParseEchoPayloadRejectsEmptyMessage(t *testing.T) {
	_, err := ParseEchoPayload([]byte(`{"message":""}`))
	require.Error(t, err)
}

func TestEchoHandlerReturnsErrorOnBadPayload(t *testing.T) {
	// initialize a logger for the handler
	cfg := &config.Config{}
	require.NoError(t, cfg.InitDefaultLogger())
	handler := NewEchoHandler(log.Named("test"))

	err := handler(context.Background(), aq.ReceiveResult{Job: aq.Job{Payload: []byte(`not-json`)}})
	require.Error(t, err)
}
