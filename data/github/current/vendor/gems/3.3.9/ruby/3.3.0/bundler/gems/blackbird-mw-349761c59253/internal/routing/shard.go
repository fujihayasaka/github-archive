package routing

import (
	"time"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
)

// ServingOffset is the offset on the snapshot topic that a IndexHost is serving.
// This is used in delta indexing to provide consistency in the system.
type ServingOffset int64

type ShardResponse struct {
	ServingHost      string // The hostname that served the shard
	ShardID          uint32
	BBResponse       *searchpb.SearchResponse
	Offset           ServingOffset
	Duration         time.Duration
	ShardUnavailable bool // True if no hosts were able to serve this shard
	NumFailedHosts   int  // Number of hosts that failed to serve this shard
	LastError        error
}

func (s *ShardResponse) QueryStats() *searchpb.QueryStats {
	if s.BBResponse != nil {
		return s.BBResponse.Stats
	}

	return nil
}
