package query

import (
	"encoding/binary"
	"fmt"
	"hash/fnv"

	"google.golang.org/protobuf/proto"

	"github.com/github/blackbird-mw/internal/experiments"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

func QueryCacheKey(req *pb.QueryRequest) string {
	queryHash := fnv.New64a()
	queryHash.Write([]byte(req.Query))
	queryHash.Write([]byte{0})
	queryHash.Write([]byte(req.ScopingQuery))
	queryHash.Write([]byte{0})
	queryHash.Write(serializeExperiments(req.Experiments))
	queryHash.Write([]byte{0})

	// Include the query parser in the cache key
	_ = binary.Write(queryHash, binary.LittleEndian, uint32(req.QueryParser))
	_ = binary.Write(queryHash, binary.LittleEndian, req.DocumentLocationLimit)

	if req.ReturnEnclosingSymbols {
		queryHash.Write([]byte{1})
	} else {
		queryHash.Write([]byte{0})
	}

	// Include custom scopes in the cache key
	for _, scope := range req.CustomScopes {
		bytes, _ := proto.Marshal(scope)
		queryHash.Write(bytes)
	}

	return fmt.Sprintf("%x", queryHash.Sum(nil))
}

func serializeExperiments(experiments experiments.Experiments) []byte {
	return []byte(experiments.String())
}

func SuggestCacheKey(req *pb.SuggestRequest) string {
	queryHash := fnv.New64a()
	queryHash.Write([]byte(req.Query))
	queryHash.Write([]byte{0})
	queryHash.Write([]byte(req.ScopingQuery))
	queryHash.Write([]byte{0})
	queryHash.Write(serializeExperiments(req.Experiments))
	queryHash.Write([]byte{0})

	// Include custom scopes in the cache key
	for _, scope := range req.CustomScopes {
		bytes, _ := proto.Marshal(scope)
		queryHash.Write(bytes)
	}

	return fmt.Sprintf("%x", queryHash.Sum(nil))
}

func CountCacheKey(req *pb.CountRequest) string {
	queryHash := fnv.New64a()
	queryHash.Write([]byte(req.Query))
	queryHash.Write([]byte{0})
	queryHash.Write([]byte(req.ScopingQuery))
	queryHash.Write([]byte{0})
	queryHash.Write(serializeExperiments(req.Experiments))
	queryHash.Write([]byte{0})

	// Include custom scopes in the cache key
	for _, scope := range req.CustomScopes {
		bytes, _ := proto.Marshal(scope)
		queryHash.Write(bytes)
	}

	return fmt.Sprintf("%x", queryHash.Sum(nil))
}
