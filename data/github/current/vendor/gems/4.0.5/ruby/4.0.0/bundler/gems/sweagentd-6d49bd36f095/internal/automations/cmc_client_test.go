package automations

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/observability"
	cmcautomationsv1 "github.com/github/sweagentd/internal/proto/twirp/automations/v1"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func TestCMCAutomationsClientSetsTenantHeadersIndependently(t *testing.T) {
	var gotTenantSlug, gotTenantID string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		gotTenantSlug = req.Header.Get(requestctx.GitHubTenantHeader)
		gotTenantID = req.Header.Get(requestctx.GitHubTenantIDHeader)

		body, err := proto.Marshal(&cmcautomationsv1.HasRepositoryAutomationResponse{})
		require.NoError(t, err)
		w.Header().Set("Content-Type", "application/protobuf")
		_, err = w.Write(body)
		require.NoError(t, err)
	}))
	defer server.Close()

	client, err := NewCMCAutomationsClientFromConfig(&config.Config{
		CopilotMissionControlTwirpURL:              server.URL,
		CopilotMissionControlTwirpHMACKey:          "secret",
		CopilotMissionControlTwirpRequestTimeoutMs: 1000,
	}, observability.NewNoopExporters())
	require.NoError(t, err)

	ctx := requestctx.NewContext(context.Background())
	require.NoError(t, requestctx.AddTenantID(ctx, "tenant-id"))
	_, err = client.HasRepositoryAutomation(ctx, &cmcautomationsv1.HasRepositoryAutomationRequest{
		OwnerId: 1,
		RepoId:  2,
		Event:   "issues",
	})
	require.NoError(t, err)
	require.Empty(t, gotTenantSlug)
	require.Equal(t, "tenant-id", gotTenantID)

	ctx = requestctx.NewContext(context.Background())
	require.NoError(t, requestctx.AddTenantSlug(ctx, "tenant-slug"))
	_, err = client.HasRepositoryAutomation(ctx, &cmcautomationsv1.HasRepositoryAutomationRequest{
		OwnerId: 1,
		RepoId:  2,
		Event:   "issues",
	})
	require.NoError(t, err)
	require.Equal(t, "tenant-slug", gotTenantSlug)
	require.Empty(t, gotTenantID)
}
