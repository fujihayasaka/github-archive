package syncmux

import (
	"context"
	"errors"
	"testing"

	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/require"
)

func TestMux_RoutesToCorrectHandler(t *testing.T) {
	var calledTopic string
	handler := func(ctx context.Context, msg hydro_lib.Message) error {
		calledTopic = msg.Topic
		return nil
	}

	mux := New(map[string]hydro_lib.MessageHandler{
		"topic.a": handler,
		"topic.b": handler,
	})

	err := mux.Dispatch(context.Background(), hydro_lib.Message{Topic: "topic.a"})
	require.NoError(t, err)
	require.Equal(t, "topic.a", calledTopic)

	err = mux.Dispatch(context.Background(), hydro_lib.Message{Topic: "topic.b"})
	require.NoError(t, err)
	require.Equal(t, "topic.b", calledTopic)
}

func TestMux_UnknownTopicAcks(t *testing.T) {
	mux := New(map[string]hydro_lib.MessageHandler{})

	err := mux.Dispatch(context.Background(), hydro_lib.Message{Topic: "unknown"})
	require.NoError(t, err)
}

func TestMux_PropagatesHandlerError(t *testing.T) {
	expectedErr := errors.New("handler failed")
	handler := func(ctx context.Context, msg hydro_lib.Message) error {
		return expectedErr
	}

	mux := New(map[string]hydro_lib.MessageHandler{
		"topic.a": handler,
	})

	err := mux.Dispatch(context.Background(), hydro_lib.Message{Topic: "topic.a"})
	require.ErrorIs(t, err, expectedErr)
}
