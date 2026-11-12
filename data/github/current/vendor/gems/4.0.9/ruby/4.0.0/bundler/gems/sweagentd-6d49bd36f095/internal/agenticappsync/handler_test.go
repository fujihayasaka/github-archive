package agenticappsync

import (
	"context"
	"testing"

	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func newTestHandler(t *testing.T, copilotAppID int64) *Handler {
	t.Helper()

	copilot := agenticapp.NewCopilot(copilotAppID, "copilot-swe-agent", 200, "copilot-bot", "commit-login", "commit@email.com")
	provider := agenticapp.NewProvider(copilot)

	return &Handler{
		obsv:        observability.NewNoopExporters(),
		appProvider: provider,
	}
}

func newTestHandlerWithTwirp(t *testing.T, copilotAppID int64, ghTwirpClient githubtwirp.ClientInterface) *Handler {
	t.Helper()

	copilot := agenticapp.NewCopilot(copilotAppID, "copilot-swe-agent", 200, "copilot-bot", "commit-login", "commit@email.com")
	provider := agenticapp.NewProvider(copilot)

	return &Handler{
		obsv:        observability.NewNoopExporters(),
		ghTwirp:     ghTwirpClient,
		cfg:         &config.Config{},
		appProvider: provider,
	}
}

func buildHydroMessage(t *testing.T, integrationID uint32, integrationName string, agentSource *entities.IntegrationAgentSource) hydro_lib.Message {
	t.Helper()

	msg := &githubv1.IntegrationUpdate{
		Actor: &entities.User{
			Id:    1,
			Login: "admin",
		},
		Integration: &entities.Integration{
			Id:          integrationID,
			Name:        integrationName,
			AgentSource: agentSource,
		},
		Owner: &entities.User{
			Id:    2,
			Login: "owner",
		},
	}

	msgBytes, err := proto.Marshal(msg)
	require.NoError(t, err)

	envelope := &hydro_pb.Envelope{
		Id:        "test-envelope-id",
		Message:   msgBytes,
		Timestamp: timestamppb.Now(),
	}

	envBytes, err := proto.Marshal(envelope)
	require.NoError(t, err)

	return hydro_lib.Message{
		Topic: topics.IntegrationUpdate,
		Value: envBytes,
	}
}

func buildIntegrationCreateMessage(t *testing.T, integrationID uint32, integrationName string, agentSource *entities.IntegrationAgentSource) hydro_lib.Message {
	t.Helper()

	msg := &githubv1.IntegrationCreate{
		Actor: &entities.User{
			Id:    1,
			Login: "admin",
		},
		Integration: &entities.Integration{
			Id:          integrationID,
			Name:        integrationName,
			AgentSource: agentSource,
		},
		Owner: &entities.User{
			Id:    2,
			Login: "owner",
		},
	}

	msgBytes, err := proto.Marshal(msg)
	require.NoError(t, err)

	envelope := &hydro_pb.Envelope{
		Id:        "test-envelope-id",
		Message:   msgBytes,
		Timestamp: timestamppb.Now(),
	}

	envBytes, err := proto.Marshal(envelope)
	require.NoError(t, err)

	return hydro_lib.Message{
		Topic: topics.IntegrationCreate,
		Value: envBytes,
	}
}

func TestDispatch_WrongTopic(t *testing.T) {
	h := newTestHandler(t, 100)

	msg := hydro_lib.Message{
		Topic: "some.other.topic",
		Value: []byte("invalid"),
	}

	// Wrong topic should be acked (nil error) even though envelope is invalid
	err := h.Dispatch(context.Background(), msg)
	require.NoError(t, err)
}

func TestDispatch_InvalidEnvelope(t *testing.T) {
	h := newTestHandler(t, 100)

	msg := hydro_lib.Message{
		Topic: topics.IntegrationUpdate,
		Value: []byte("not-a-protobuf"),
	}

	// Invalid envelope should be acked to prevent infinite retries
	err := h.Dispatch(context.Background(), msg)
	require.NoError(t, err)
}

func TestDispatch_IntegrationWithoutAgentSource(t *testing.T) {
	h := newTestHandler(t, 100)

	// Integration without AgentSource should be skipped
	msg := buildHydroMessage(t, 999, "some-other-app", nil)

	err := h.Dispatch(context.Background(), msg)
	require.NoError(t, err)
}

func TestDispatch_IntegrationWithEmptyAgentSourceURL(t *testing.T) {
	h := newTestHandler(t, 100)

	// Integration with AgentSource but empty URL should be skipped
	msg := buildHydroMessage(t, 999, "some-other-app", &entities.IntegrationAgentSource{})

	err := h.Dispatch(context.Background(), msg)
	require.NoError(t, err)
}

func TestDispatch_NilIntegration(t *testing.T) {
	h := newTestHandler(t, 100)

	msg := &githubv1.IntegrationUpdate{
		Actor: &entities.User{Id: 1, Login: "admin"},
		// Integration is nil
	}

	msgBytes, err := proto.Marshal(msg)
	require.NoError(t, err)

	envelope := &hydro_pb.Envelope{
		Id:        "test-envelope-id",
		Message:   msgBytes,
		Timestamp: timestamppb.Now(),
	}
	envBytes, err := proto.Marshal(envelope)
	require.NoError(t, err)

	hydroMsg := hydro_lib.Message{
		Topic: topics.IntegrationUpdate,
		Value: envBytes,
	}

	err = h.Dispatch(context.Background(), hydroMsg)
	require.NoError(t, err)
}

func TestHandleIntegrationUpdate_MatchingAppTriggersReload(t *testing.T) {
	copilotAppID := int64(100)

	ghTwirpClient := githubtwirp.NewNoopClient()
	ghTwirpClient.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
		return &sweagentdv1.GetAgenticAppsResponse{
			AgenticApps: []*sweagentdv1.AgenticApp{
				{
					AppId:       copilotAppID,
					AppLogin:    "copilot-swe-agent",
					AppBotId:    200,
					BotLogin:    "copilot-bot",
					CommitLogin: "commit-login",
					CommitEmail: "commit@email.com",
				},
			},
		}, nil
	}

	h := newTestHandlerWithTwirp(t, copilotAppID, ghTwirpClient)

	agentSource := &entities.IntegrationAgentSource{Url: "https://github.com/owner/repo"}
	msg := buildHydroMessage(t, uint32(copilotAppID), "copilot-swe-agent", agentSource)
	err := h.Dispatch(context.Background(), msg)
	require.NoError(t, err)

	// Verify the provider was reloaded (Apps() returns updated list)
	apps := h.appProvider.Apps()
	require.Len(t, apps, 1)
}

func TestHandleIntegrationUpdate_ReloadError(t *testing.T) {
	copilotAppID := int64(100)

	ghTwirpClient := githubtwirp.NewNoopClient()
	ghTwirpClient.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
		return nil, goerrors.New("monolith unavailable")
	}

	h := newTestHandlerWithTwirp(t, copilotAppID, ghTwirpClient)

	agentSource := &entities.IntegrationAgentSource{Url: "https://github.com/owner/repo"}
	msg := buildHydroMessage(t, uint32(copilotAppID), "copilot-swe-agent", agentSource)
	err := h.Dispatch(context.Background(), msg)
	// Error is swallowed (ACKed) to prevent infinite retries
	require.NoError(t, err)
}

func TestDispatch_IntegrationCreate_WithoutAgentSource(t *testing.T) {
	h := newTestHandler(t, 100)

	// Integration without AgentSource should be skipped
	msg := buildIntegrationCreateMessage(t, 999, "some-other-app", nil)

	err := h.Dispatch(context.Background(), msg)
	require.NoError(t, err)
}

func TestHandleIntegrationCreate_MatchingAppTriggersReload(t *testing.T) {
	copilotAppID := int64(100)

	ghTwirpClient := githubtwirp.NewNoopClient()
	ghTwirpClient.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
		return &sweagentdv1.GetAgenticAppsResponse{
			AgenticApps: []*sweagentdv1.AgenticApp{
				{
					AppId:       copilotAppID,
					AppLogin:    "copilot-swe-agent",
					AppBotId:    200,
					BotLogin:    "copilot-bot",
					CommitLogin: "commit-login",
					CommitEmail: "commit@email.com",
				},
			},
		}, nil
	}

	h := newTestHandlerWithTwirp(t, copilotAppID, ghTwirpClient)

	agentSource := &entities.IntegrationAgentSource{Url: "https://github.com/owner/repo"}
	msg := buildIntegrationCreateMessage(t, uint32(copilotAppID), "copilot-swe-agent", agentSource)
	err := h.Dispatch(context.Background(), msg)
	require.NoError(t, err)

	apps := h.appProvider.Apps()
	require.Len(t, apps, 1)
}

func TestHandleIntegrationCreate_NilIntegration(t *testing.T) {
	h := newTestHandler(t, 100)

	msg := &githubv1.IntegrationCreate{
		Actor: &entities.User{Id: 1, Login: "admin"},
		// Integration is nil
	}

	msgBytes, err := proto.Marshal(msg)
	require.NoError(t, err)

	envelope := &hydro_pb.Envelope{
		Id:        "test-envelope-id",
		Message:   msgBytes,
		Timestamp: timestamppb.Now(),
	}
	envBytes, err := proto.Marshal(envelope)
	require.NoError(t, err)

	hydroMsg := hydro_lib.Message{
		Topic: topics.IntegrationCreate,
		Value: envBytes,
	}

	err = h.Dispatch(context.Background(), hydroMsg)
	require.NoError(t, err)
}
