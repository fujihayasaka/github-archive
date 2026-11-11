package search

import (
	"context"
	"time"

	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/models"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

//go:generate counterfeiter . Index
type Index interface {
	// Perform a search query against all shards. Returns a shard request (for
	// instrumentation) and a `QueryResponse` or an error.
	Search(ctx context.Context, query *querypb.Query, queryCtx *QueryContext) (*pb.QueryResponse, error)

	// Perform a count query against all shards. Returns a shard request (for
	// instrumentation) and a `CountResponse` or an error.
	Count(ctx context.Context, query *querypb.Query, queryCtx *QueryContext) (*pb.CountResponse, error)

	// Take a user query and do a snapshot search to lookup any repos or owners
	// mentioned in it. Used for query rewriting.
	BuildCacheFromQuery(ctx context.Context, isGloballyScoped bool, actor *models.Actor, query *querypb.Query) (*RepoAndOwnerCache, error)

	// Get a single owner by login. Returns:
	//  - an owner OR
	//  - nil and a nil error if an owner with this login was not found OR
	//  - nil and an error if there was a problem querying the search index
	GetOwner(ctx context.Context, login string) (*models.Owner, error)
	GetOwners(ctx context.Context, ids []int64) ([]*models.Owner, error)

	// Get a single repository by nwo or id. Returns:
	//  - a repo OR
	//  - nil and a nil error if a repo was not found (or not accessible by the actor) OR
	//  - nil and an error if there was a problem querying the search index
	//
	// NOTE: Though this returns a db.Repository, not all fields will be valid as the
	// search index doesn't track everything (e.g. HasLicense).
	GetRepositoryByNWO(ctx context.Context, actor *models.Actor, nwo types.NWO) (*db.Repository, error)
	GetRepositoryByID(ctx context.Context, actor *models.Actor, repoID types.RepoID) (*db.Repository, error)

	// Returns the corpus for this index.
	Corpus() routing.Corpus

	// Returns the number of shards
	NumShards() int
}

// QueryType is used to distinguish user queries from system generated queries
// like suggestions and counts as each may have different limits and parameters.
type QueryType string

const (
	QueryTypeUser            QueryType = "user-query"
	QueryTypeSuggest         QueryType = "suggest"
	QueryTypeFindDefinitions QueryType = "find-definitions"
	QueryTypeFindReferences  QueryType = "find-references"
	QueryTypeCount           QueryType = "count"
	QueryTypeRewriting       QueryType = "query-rewriting"
	QueryTypeExemplar        QueryType = "exemplar-query"
	QueryTypeCompleteness    QueryType = "completeness-query"
	QueryTypeMetadata        QueryType = "metadata-query"
	QueryTypePath            QueryType = "path-check-query"
	QueryTypeSimilarity      QueryType = "similarity"
)

// QuerySource is used to distinguish the source of a query.
type QuerySource string

const (
	QuerySourceFE               QuerySource = "fe"
	QuerySourceLegacyAPI        QuerySource = "legacy-api"
	QuerySourceProber           QuerySource = "prober"
	QuerySourceCopilotAPI       QuerySource = "copilot-api"
	QuerySourceGraphQLAPI       QuerySource = "graphql-api"
	QuerySourceCopilotIDE       QuerySource = "copilot-ide"
	QuerySourceBing             QuerySource = "bing"
	QuerySourceAleph            QuerySource = "aleph"
	QuerySourceGetRepoStatus    QuerySource = "get-repo-status"
	QuerySourceCodeNav          QuerySource = "code-nav"
	QuerySourceCopilotWorkspace QuerySource = "copilot-workspace"
)

const (
	MaxTimeout                                 = 90 * time.Second // max query timeout (per shard)
	DefaultTimeout                             = 9 * time.Second  // default query timeout (per shard)
	DefaultSuggestTimeout                      = 2 * time.Second  // suggest specific query timeout (per shard)
	DefaultSearchSnapshotTimeoutMillis uint32  = 500              // snapshot search timeout (e.g. for query rewriting). Chosen to be 100x typical p99.
	DefaultRetries                     uint32  = 1                // by default, allow a single retry to get up to the requested doc limit
	DefaultUserQueryRetries            uint32  = 2                // user queries can retry twice
	UserQueryUnavailableShardsPercent  float32 = 0.06             // user queries tolerate *some* missing shards, incomplete results are returned with a warning
	CountUnavailableShardsPercent      float32 = 0.50             // count queries can tolerate a few more missing shards
	SuggestUnavailableShardsPercent    float32 = 0.90             // suggest queries can tolerate a lot of missing shards, just return whatever we've got
	ProbersUnavailableShardsPercent    float32 = 0.0              // probers do not tolerate missing shards
	LocationRequestTimeout                     = 2 * time.Second  // More stringent than most because code nav needs to be fast
)

type RepoAndOwnerCache struct {
	OwnersByLogin map[string]*models.Owner
	OwnersByID    map[uint32]*models.Owner
	ReposByName   map[string][]*snapshotpb.SnapshotEntry
	ReposByNWO    map[string]*snapshotpb.SnapshotEntry
	ReposByID     map[types.RepoID]*snapshotpb.SnapshotEntry

	// DO NOT USE (see ReposByNWO instead)
	//
	// This is to check for the existence of a repo in the index (for logging), but is unsafe to use in user responses b/c
	// it does not take permissions into account and can leak the existence of private repos.
	SnapshotReposByNWO map[string]*snapshotpb.SnapshotEntry
}

func NewRepoAndOwnerCache() *RepoAndOwnerCache {
	return &RepoAndOwnerCache{
		OwnersByLogin:      map[string]*models.Owner{},
		OwnersByID:         map[uint32]*models.Owner{},
		ReposByName:        map[string][]*snapshotpb.SnapshotEntry{},
		ReposByNWO:         map[string]*snapshotpb.SnapshotEntry{},
		ReposByID:          map[types.RepoID]*snapshotpb.SnapshotEntry{},
		SnapshotReposByNWO: map[string]*snapshotpb.SnapshotEntry{},
	}
}
