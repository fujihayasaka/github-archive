package search

import (
	"time"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	"google.golang.org/protobuf/types/known/durationpb"

	"github.com/github/blackbird-mw/internal/models"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/types"
)

type PaginationOptions struct {
	PageIdx uint32
	PerPage uint32
}

// QueryContext contains contextual information related to a query.
type QueryContext struct {
	ScopeRepoIDs                  []types.RepoID
	Actor                         *models.Actor
	Limits                        QueryLimits
	ScoreDocIDs                   []*searchpb.DocId
	MaxAllowedRetries             uint32        // Max retries (per query, per cluster)
	MaxPercentUnavailableShards   float32       // Max unavailable shards allowed as a percent of total shards before the query is considered failed.
	Timeout                       time.Duration // Timeout (per query, per cluster)
	QueryType                     QueryType     // Type of the query: e.g., user, suggest
	QuerySource                   QuerySource   // Source of the query: e.g., fe, prober
	SnippetOptions                *pb.SnippetOptions
	PaginationOptions             *PaginationOptions // number of results per page
	QueryCacheKey                 string             // a hash of the query
	DontRetryOnSaturatedLocations bool
	ReturnEnclosingSymbols        bool
}

func BuildQueryContext(
	actor *models.Actor,
	limits QueryLimits,
	maxAllowedRetries uint32,
	maxPercentUnavailableShards float32,
	timeout time.Duration,
	queryType QueryType,
	querySource QuerySource,
	scopeRepoIds []types.RepoID,
	snippetOptions *pb.SnippetOptions,
	paginationOptions *PaginationOptions,
	queryCacheKey string,
	returnEnclosingSymbols bool,
) *QueryContext {
	return &QueryContext{
		ScopeRepoIDs:                scopeRepoIds,
		Actor:                       actor,
		Limits:                      limits,
		MaxAllowedRetries:           maxAllowedRetries,
		MaxPercentUnavailableShards: maxPercentUnavailableShards,
		Timeout:                     timeout,
		QueryType:                   queryType,
		QuerySource:                 querySource,
		SnippetOptions:              snippetOptions,
		PaginationOptions:           paginationOptions,
		QueryCacheKey:               queryCacheKey,
		ReturnEnclosingSymbols:      returnEnclosingSymbols,
	}
}

// Build a QueryContext for a front-end user query.
func BuildFEUserQueryContext(
	actor *models.Actor,
	limits QueryLimits,
	queryType QueryType,
	querySource QuerySource,
	timeout time.Duration,
	scopeRepoIds []types.RepoID,
	snippetOptions *pb.SnippetOptions,
	paginationOptions *PaginationOptions,
	queryCacheKey string,
	returnEnclosingSymbols bool,
) *QueryContext {
	return BuildQueryContext(
		actor,
		limits,
		DefaultUserQueryRetries,
		UserQueryUnavailableShardsPercent,
		timeout,
		queryType,
		querySource,
		scopeRepoIds,
		snippetOptions,
		paginationOptions,
		queryCacheKey,
		returnEnclosingSymbols,
	)
}

// Build a QueryContext for a front-end suggest query.
func BuildFESuggestQueryContext(
	actor *models.Actor,
	timeout time.Duration,
	scopeRepoIds []types.RepoID,
	queryCacheKey string,
) *QueryContext {
	return BuildQueryContext(
		actor,
		QueryLimits{
			RequestedDocs:  10,   // We only display a limited number of suggestions
			RequestedLocs:  5,    // Request enough locations to avoid suggest retries when locations get filtered out due to accessible repos.
			LocationsLimit: 5,    //
			TermMatchLimit: 1,    // Do we need these?
			ToRetrieve:     1000, //
			ToScore:        10,   //
			ToReturn:       10,   //
			WithContent:    10,   // Avoid having to fetchMissingContent
		},
		DefaultRetries,
		SuggestUnavailableShardsPercent,
		timeout,
		QueryTypeSuggest,
		QuerySourceFE,
		scopeRepoIds,
		nil, /* snippetOptions */
		nil, /* paginationOptions */
		queryCacheKey,
		false, /* returnEnclosingSymbols */
	)
}

// Build a QueryContext for a front-end count query.
func BuildFECountQueryContext(
	actor *models.Actor,
	timeout time.Duration,
	scopeRepoIds []types.RepoID,
	queryCacheKey string,
) *QueryContext {
	return BuildQueryContext(
		actor,
		QueryLimits{
			RequestedDocs:  0,    // OK to use zero b/c this is only used in the search path to clamp results
			RequestedLocs:  1,    // No need for more than one location per document
			LocationsLimit: 1,    // No need for more than one location per document
			TermMatchLimit: 0,    // Don't return any term matches
			ToRetrieve:     0,    // Set to zero as we only care about results returned for the child nodes
			ToScore:        0,    // Don't do any scoring
			ToReturn:       1000, // Set a high limit on docs to return so it doesn't interfere with counting
			WithContent:    0,    // Don't return content
		},
		0, // no retries for counts
		CountUnavailableShardsPercent,
		timeout,
		QueryTypeCount,
		QuerySourceFE,
		scopeRepoIds,
		nil, /* snippetOptions */
		nil, /* paginationOptions */
		queryCacheKey,
		false,
	)
}

func (q *QueryContext) UsePagination() bool {
	return q.PaginationOptions != nil && q.PaginationOptions.PerPage != 0
}

// SearchTimeout returns a valid timeout for the Search RPC. Not too small, not
// too big. Just right. To be used as the overall RPC timeout.
func SearchTimeout(val *durationpb.Duration) time.Duration {
	return fetchTimeout(val, DefaultTimeout)
}

// SuggestTimeout returns a valid timeout for the Suggest RPC. Not too small, not
// too big. Just right. To be used as the overall RPC timeout.
func SuggestTimeout(val *durationpb.Duration) time.Duration {
	return fetchTimeout(val, DefaultSuggestTimeout)
}

// CountTimeout returns a valid timeout for the Count RPC. Not too small, not
// too big. Just right. To be used as the overall RPC timeout.
func CountTimeout(val *durationpb.Duration) time.Duration {
	return fetchTimeout(val, DefaultTimeout)
}

// Given a possibly null protobuf Duration and a default value, return a
// time.Duration. However, if the protobuf Duration is too large, return the
// MaxTimeout.
func fetchTimeout(val *durationpb.Duration, defaultTimeout time.Duration) time.Duration {
	timeout := defaultTimeout
	if val.IsValid() {
		timeout = val.AsDuration()
		if timeout > MaxTimeout {
			timeout = MaxTimeout
		}
	}
	return timeout
}
