package consumers

import (
	"context"
	"testing"

	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/turboscan/ts/flipper"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

// requireProcessEnvelope constructs the hydro envelope and calls the ProcessEnvelope method of the processor
func requireProcessEnvelope(t *testing.T, p hydroProcessor, m proto.Message, topic string) {
	t.Helper()
	ctx := context.Background()
	ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningListenToComputeUsage)

	protoMsg, err := proto.Marshal(m)
	require.NoError(t, err)

	require.NoError(t, p.ProcessEnvelope(ctx, &envelope.Envelope{Message: protoMsg}, topic))
}
