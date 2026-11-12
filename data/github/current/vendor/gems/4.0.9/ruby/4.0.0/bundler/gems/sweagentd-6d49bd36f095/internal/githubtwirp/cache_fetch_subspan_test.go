package githubtwirp

import (
	"context"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

func TestGetCopilotUserDetailsFetchSubspan(t *testing.T) {
	t.Run("feature flag enabled adds fetch subspan only on cache miss", func(t *testing.T) {
		obsv, spanRecorder := newSpanRecorderExporters(t)
		callCount := 0

		client := &Client{
			obsv:       obsv,
			ffClient:   featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentCachedRPCFetchSubspans: true}),
			cacheStore: cache.NewMemoryCacheStore(),
			userDetailAPI: &NoopUserDetailAPI{
				MockGetCopilotUser: func(_ context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					callCount++
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{
							Id:                  req.Id,
							AnalyticsTrackingId: "tracking-id",
						},
					}, nil
				},
			},
		}

		ctx := requestctx.NewContext(context.Background())

		_, err := client.GetCopilotUserDetails(ctx, 123)
		require.NoError(t, err)
		require.Equal(t, 1, callCount)
		require.ElementsMatch(t,
			[]string{
				"githubtwirp.Client.GetCopilotUserDetails",
				"githubtwirp.Client.GetCopilotUserDetails.fetch",
			},
			endedSpanNames(spanRecorder),
		)

		spanRecorder.Reset()
		_, err = client.GetCopilotUserDetails(ctx, 123)
		require.NoError(t, err)
		require.Equal(t, 1, callCount)
		require.Equal(t, []string{"githubtwirp.Client.GetCopilotUserDetails"}, endedSpanNames(spanRecorder))
	})

	t.Run("feature flag disabled does not add fetch subspan", func(t *testing.T) {
		obsv, spanRecorder := newSpanRecorderExporters(t)
		callCount := 0

		client := &Client{
			obsv:       obsv,
			ffClient:   featureflags.NewNoopClient(map[string]bool{}),
			cacheStore: cache.NewMemoryCacheStore(),
			userDetailAPI: &NoopUserDetailAPI{
				MockGetCopilotUser: func(_ context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					callCount++
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{Id: req.Id},
					}, nil
				},
			},
		}

		_, err := client.GetCopilotUserDetails(requestctx.NewContext(context.Background()), 456)
		require.NoError(t, err)
		require.Equal(t, 1, callCount)
		require.Equal(t, []string{"githubtwirp.Client.GetCopilotUserDetails"}, endedSpanNames(spanRecorder))
	})
}

func TestGetRepoByNameFetchSubspan(t *testing.T) {
	t.Run("feature flag enabled adds fetch subspan only on cache miss", func(t *testing.T) {
		obsv, spanRecorder := newSpanRecorderExporters(t)
		mockAPI := &mockRepositoriesAPI{
			findByNameResponse: &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         123,
						OwnerId:    456,
						OwnerLogin: "owner",
						Name:       "repo",
					},
				},
			},
		}

		client := &Client{
			obsv:       obsv,
			ffClient:   featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentCachedRPCFetchSubspans: true}),
			cacheStore: cache.NewMemoryCacheStore(),
			reposAPI:   mockAPI,
		}

		_, err := client.GetRepoByName(context.Background(), "owner", "repo")
		require.NoError(t, err)
		require.Equal(t, 1, mockAPI.callCount)
		require.ElementsMatch(t,
			[]string{
				"githubtwirp.Client.GetRepoByName",
				"githubtwirp.Client.GetRepoByName.fetch",
			},
			endedSpanNames(spanRecorder),
		)

		spanRecorder.Reset()
		_, err = client.GetRepoByName(context.Background(), "owner", "repo")
		require.NoError(t, err)
		require.Equal(t, 1, mockAPI.callCount)
		require.Equal(t, []string{"githubtwirp.Client.GetRepoByName"}, endedSpanNames(spanRecorder))
	})

	t.Run("feature flag disabled does not add fetch subspan", func(t *testing.T) {
		obsv, spanRecorder := newSpanRecorderExporters(t)
		mockAPI := &mockRepositoriesAPI{
			findByNameResponse: &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         123,
						OwnerId:    456,
						OwnerLogin: "owner",
						Name:       "repo",
					},
				},
			},
		}

		client := &Client{
			obsv:       obsv,
			ffClient:   featureflags.NewNoopClient(map[string]bool{}),
			cacheStore: cache.NewMemoryCacheStore(),
			reposAPI:   mockAPI,
		}

		_, err := client.GetRepoByName(context.Background(), "owner", "repo")
		require.NoError(t, err)
		require.Equal(t, 1, mockAPI.callCount)
		require.Equal(t, []string{"githubtwirp.Client.GetRepoByName"}, endedSpanNames(spanRecorder))
	})
}

func TestGetInstallationInfoFetchSubspan(t *testing.T) {
	t.Run("feature flag enabled adds fetch subspan only on cache miss", func(t *testing.T) {
		obsv, spanRecorder := newSpanRecorderExporters(t)
		callCount := 0
		noopAPI := &NoopSweagentdAPI{}
		noopAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			callCount++
			return &sweagentdTwirp.GetRepositoryInstallationResponse{
				InstallationId: 999,
				OwnerId:        111,
				OwnerLogin:     "owner",
				OwnerType:      sweagentdTwirp.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_ORGANIZATION,
				ClientId:       "client-id",
				RepoName:       "repo",
			}, nil
		}

		client := &Client{
			obsv:         obsv,
			ffClient:     featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentCachedRPCFetchSubspans: true}),
			cacheStore:   cache.NewMemoryCacheStore(),
			sweagentdAPI: noopAPI,
		}

		_, err := client.GetInstallationInfo(context.Background(), 10, 20)
		require.NoError(t, err)
		require.Equal(t, 1, callCount)
		require.ElementsMatch(t,
			[]string{
				"githubtwirp.Client.GetInstallationInfo",
				"githubtwirp.Client.GetInstallationInfo.fetch",
			},
			endedSpanNames(spanRecorder),
		)

		spanRecorder.Reset()
		_, err = client.GetInstallationInfo(context.Background(), 10, 20)
		require.NoError(t, err)
		require.Equal(t, 1, callCount)
		require.Equal(t, []string{"githubtwirp.Client.GetInstallationInfo"}, endedSpanNames(spanRecorder))
	})

	t.Run("feature flag disabled does not add fetch subspan", func(t *testing.T) {
		obsv, spanRecorder := newSpanRecorderExporters(t)
		callCount := 0
		noopAPI := &NoopSweagentdAPI{}
		noopAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			callCount++
			return &sweagentdTwirp.GetRepositoryInstallationResponse{
				InstallationId: 999,
				OwnerId:        111,
				OwnerLogin:     "owner",
				OwnerType:      sweagentdTwirp.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_ORGANIZATION,
				ClientId:       "client-id",
				RepoName:       "repo",
			}, nil
		}

		client := &Client{
			obsv:         obsv,
			ffClient:     featureflags.NewNoopClient(map[string]bool{}),
			cacheStore:   cache.NewMemoryCacheStore(),
			sweagentdAPI: noopAPI,
		}

		_, err := client.GetInstallationInfo(context.Background(), 10, 20)
		require.NoError(t, err)
		require.Equal(t, 1, callCount)
		require.Equal(t, []string{"githubtwirp.Client.GetInstallationInfo"}, endedSpanNames(spanRecorder))
	})
}

func newSpanRecorderExporters(t *testing.T) (observability.Exporters, *tracetest.SpanRecorder) {
	t.Helper()

	spanRecorder := tracetest.NewSpanRecorder()
	tp := sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(spanRecorder))
	t.Cleanup(func() {
		require.NoError(t, tp.Shutdown(context.Background()))
	})

	obsv := observability.NewNoopExporters()
	obsv.Tracer = tp.Tracer("githubtwirp-test")

	return obsv, spanRecorder
}

func endedSpanNames(spanRecorder *tracetest.SpanRecorder) []string {
	endedSpans := spanRecorder.Ended()
	names := make([]string, 0, len(endedSpans))
	for _, span := range endedSpans {
		names = append(names, span.Name())
	}
	return names
}
