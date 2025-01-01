package timing

import (
	"context"
	"fmt"
	"time"

	"github.com/github/go-stats"
	"github.com/github/go-telemetry/statting"
)

// QueryTiming allows tracking durations of each step that it takes to process
// and execute a query: parsing and re-writing, querying the shards, post-query
// filtering for accessible_repo_ids, and spokesd blob resolution.
//
// Metrics are sent to DataDog, but also recorded in a way that they can be
// returned in the various query response types.
type QueryTimings struct {
	start   time.Time
	end     time.Time
	Timings []*QueryTiming // Ordered list of timings for each individual step
}

// TotalDuration of a query from when `Start` is called until `Finish`.
// Individual timing steps do *not* necessarily add up to the total duration as
// it is up to callers to add those and there can be gaps between one step and
// another.
func (q *QueryTimings) TotalDuration() time.Duration { return q.end.Sub(q.start) }

// Start puts a QueryTimings struct in the context and records the start of the
// query execution.
func Start(ctx context.Context) context.Context {
	return context.WithValue(ctx, ctxQueryTimingsKey{}, &QueryTimings{time.Now(), time.Time{}, []*QueryTiming{}})
}

// Record an individual step's timing information. Tags are passed on to the
// statting.DistributionMs call.
func Record(ctx context.Context, key QueryStep, start time.Time, tags ...stats.Tags) {
	if qt, ok := getQueryTimings(ctx); ok {
		duration := time.Since(start)
		qt.Timings = append(qt.Timings, &QueryTiming{key, duration, start, time.Now()})
		statting.DistributionMs(ctx, fmt.Sprintf("query_timings.%s.duration", key), duration, tags...)
	}
}

// Finish a query execution. Returns the QueryTimings from the context or nil if
// none was ever added.
func Finish(ctx context.Context) *QueryTimings {
	qt, ok := getQueryTimings(ctx)
	if ok {
		qt.end = time.Now()
	}
	return qt
}

// Timing information for an individual step in the query process. While we
// calculate duration, it's possible that there are gaps between individual
// steps in the Timings slices of QueryTimings so start and end would
// theoretically allow identifying those.
type QueryTiming struct {
	Key      QueryStep
	Duration time.Duration
	Start    time.Time
	End      time.Time
}

// An individual step in executing a query
type QueryStep string

const (
	QueryStepPreparedContext       QueryStep = "prepared_context"        // context preparation
	QueryStepClusterSelection      QueryStep = "cluster_selection"       // cluster selection
	QueryStepParseQuery            QueryStep = "parse_query"             // parsing
	QueryStepRewriteQuery          QueryStep = "rewrite_query"           // rewriting
	QueryStepLintQuery             QueryStep = "lint_query"              // linting and simplifying
	QueryStepRanQuery              QueryStep = "ran_query"               // ran query against all shards
	QueryStepFetchedMissingContent QueryStep = "fetched_missing_content" // fetched any missing content
	QueryStepResolvedBlobs         QueryStep = "resolved_blobs"          // resolved blobs with spokesd
)

type ctxQueryTimingsKey struct{}

func getQueryTimings(ctx context.Context) (*QueryTimings, bool) {
	val, ok := ctx.Value(ctxQueryTimingsKey{}).(*QueryTimings)
	return val, ok
}
