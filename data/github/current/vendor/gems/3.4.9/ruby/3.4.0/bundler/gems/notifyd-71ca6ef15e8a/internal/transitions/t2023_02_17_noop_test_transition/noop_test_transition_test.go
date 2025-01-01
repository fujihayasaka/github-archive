package t2023_02_17_noop_test_transition //nolint:revive,stylecheck // allow underscores

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
)

func TestNew(t *testing.T) {
	r := require.New(t)
	transition := NewNoopTestTransition(logs.NullTelem, new(routing.ServiceMock), new(subscriptions.ServiceMock))
	r.NotNil(transition)
}
