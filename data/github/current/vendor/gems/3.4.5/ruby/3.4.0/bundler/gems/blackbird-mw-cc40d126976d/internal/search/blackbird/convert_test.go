package blackbird

import (
	"errors"
	"testing"
	"time"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	"github.com/stretchr/testify/require"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/routing"
)

func TestMetadataMapping_Failure(t *testing.T) {
	shardResp := &routing.ShardResponse{
		ServingHost:      "some-host-name",
		NumFailedHosts:   1,
		ShardUnavailable: true,
		LastError:        errors.New("boom"),
		Duration:         100 * time.Millisecond,
	}
	metadata := mapShardMetadata(shardResp)

	require.Equal(t, "boom", metadata.Error)
	verifyMetadata(t, shardResp, metadata)
}

func TestMetadataMapping_Success(t *testing.T) {
	shardResp := &routing.ShardResponse{
		ServingHost: "some-host-name",
		Duration:    100 * time.Millisecond,
		BBResponse: &searchpb.SearchResponse{
			Stats: &searchpb.QueryStats{
				Cost:                  999,
				DocsRetrieved:         1000,
				DocsScored:            100,
				LocationsRetrieved:    10000,
				LocationsScored:       10000,
				ItersCreated:          1000,
				ScoringDurationMicros: 100,
			},
		},
	}

	metadata := mapShardMetadata(shardResp)

	require.NotNil(t, metadata.Stats)
	require.Empty(t, metadata.Error)
	verifyMetadata(t, shardResp, metadata)
}

func verifyMetadata(t *testing.T, resp *routing.ShardResponse, meta *pb.ShardMetadata) {
	t.Helper()
	require.NotNil(t, meta)
	require.Equal(t, resp.Duration.Microseconds(), meta.ResponseMicros)
	require.Equal(t, resp.ServingHost, meta.Hostname)
}
