package hydro

import (
	"context"
	"testing"

	hydroclient "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/require"
)

func TestKafkaEventCoordsWithEventID_StoresPointerReturnsValues(t *testing.T) {
	ctx := context.Background()
	hm := &hydro.Message{
		Topic:     "test-topic",
		Partition: 123,
		Offset:    567,
	}

	ctx, coords := NewKafkaEventCoords(ctx, hm)
	require.Equal(t, "test-topic", hm.Topic)
	require.Equal(t, int32(123), coords.Partition)
	require.Equal(t, int64(567), coords.Offset)
	require.Equal(t, "", coords.EventID)

	ev := &hydroclient.Envelope{Id: "evt_123"}
	ctx2, coords2 := KafkaEventCoordsWithEventID(ctx, ev)
	require.NotSame(t, &coords, &coords2, "KafkaEventCoordsWithEventID should return new coords instance, not pointer to original")
	require.Equal(t, "evt_123", coords2.EventID)

	coords3 := GetKafkaEventCoords(ctx2)
	require.NotSame(t, &coords2, &coords3, "GetKafkaEventCoords should return new coords instance, not pointer to original")
	require.Equal(t, coords2, coords3)
}
