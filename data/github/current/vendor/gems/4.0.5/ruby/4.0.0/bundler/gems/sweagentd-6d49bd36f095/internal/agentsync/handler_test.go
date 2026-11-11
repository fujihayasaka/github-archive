package agentsync

import (
	"context"
	"testing"

	"github.com/github/go-stats"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	sweagentdv1 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v1"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/customagent/store/memory"
	"github.com/github/sweagentd/internal/envrouting"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

type counterCall struct {
	key   string
	tags  stats.Tags
	value int64
}

type metricsCapturingStatter struct {
	stats.NullClient

	counterCalls []counterCall
}

func (s *metricsCapturingStatter) Counter(key string, tags stats.Tags, value int64) {
	s.counterCalls = append(s.counterCalls, counterCall{key, tags, value})
}

func filterCounterCalls(calls []counterCall, key string) []counterCall {
	var filtered []counterCall
	for _, c := range calls {
		if c.key == key {
			filtered = append(filtered, c)
		}
	}
	return filtered
}

func newAgentsUpdatedMessage(t *testing.T) hydro_lib.Message {
	t.Helper()

	msg := &sweagentdv1.AgentsUpdated{
		Repository: &entities.Repository{
			Id:      100,
			Name:    "my-repo",
			OwnerId: wrapperspb.UInt32(200),
		},
		Actor: &entities.User{
			Id:    300,
			Login: "pusher",
		},
		CommitSha: "abc123",
	}
	msgBytes, err := proto.Marshal(msg)
	require.NoError(t, err)

	env, err := proto.Marshal(&hydro_pb.Envelope{
		TypeUrl: "test",
		Message: msgBytes,
	})
	require.NoError(t, err)

	return hydro_lib.Message{
		Topic: topics.AgentsUpdated,
		Value: env,
	}
}

func TestHandler_EventSkipped_MinimalTags(t *testing.T) {
	t.Run("feature_flag skip emits only reason and scope tags", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		// All flags disabled → feature flag gate triggers skip
		ffClient := featureflags.NewNoopClient(nil)
		envRouter := envrouting.NewRouter(ffClient, config.EnvironmentDevelopment, "development")

		h := NewHandler(
			&mockFileReader{},
			memory.NewStore(),
			memory.NewStore(),
			memory.NewStore(),
			ffClient,
			&NoopEnterpriseResolver{},
			envRouter,
			obsv,
		)

		err := h.Dispatch(context.Background(), newAgentsUpdatedMessage(t))
		require.NoError(t, err)

		skippedCalls := filterCounterCalls(statter.counterCalls, "hydro.event_skipped")
		require.Len(t, skippedCalls, 1)
		require.Equal(t, stats.Tags{"reason": "feature_flag", "scope": "repository"}, skippedCalls[0].tags,
			"hydro.event_skipped must emit only minimal tags to keep cardinality low")
	})

	t.Run("environment_routing skip emits only reason and scope tags", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		// Enable config sync + env routing flags, but use staging env so routing skips
		ffClient := featureflags.NewNoopClient(map[string]bool{
			"copilot_swe_agent_config_sync":             true,
			"copilot_swe_agent_config_sync_env_routing": true,
		})
		envRouter := envrouting.NewRouter(ffClient, config.EnvironmentStaging, "staging")

		h := NewHandler(
			&mockFileReader{},
			memory.NewStore(),
			memory.NewStore(),
			memory.NewStore(),
			ffClient,
			&NoopEnterpriseResolver{},
			envRouter,
			obsv,
		)

		err := h.Dispatch(context.Background(), newAgentsUpdatedMessage(t))
		require.NoError(t, err)

		skippedCalls := filterCounterCalls(statter.counterCalls, "hydro.event_skipped")
		require.Len(t, skippedCalls, 1)
		require.Equal(t, stats.Tags{"reason": "environment_routing", "scope": "repository"}, skippedCalls[0].tags,
			"hydro.event_skipped must emit only minimal tags to keep cardinality low")
	})
}
