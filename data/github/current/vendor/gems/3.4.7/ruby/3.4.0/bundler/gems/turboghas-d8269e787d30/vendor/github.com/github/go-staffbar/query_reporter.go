package staffbar

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"time"
)

type key int

var queryReporterKey key

// QueryTiming represents a database query with a duration and number of results
// returned.
type QueryTiming struct {
	Query    string `json:"query"`
	Duration int64  `json:"duration"`
	Results  int64  `json:"results"`
}

// QueryReporter tracks query timings.
type QueryReporter struct {
	queries []QueryTiming
}

// ToPayload generates a payload for the query timings to be read by dotcom.
func (c *QueryReporter) ToPayload() string {
	if c == nil {
		return ""
	}

	queries := c.queries

	if len(queries) == 0 {
		return ""
	}

	values := make(map[string]interface{})
	values["version"] = 1
	values["queries"] = queries
	payload, err := json.Marshal(values)
	if err != nil {
		return ""
	}
	return base64.StdEncoding.EncodeToString(payload)
}

// Report tracks a query timing.
func (c *QueryReporter) Report(query string, duration time.Duration, results int64) {
	if c != nil {
		c.queries = append(c.queries, QueryTiming{query, duration.Nanoseconds(), results})
	}
}

// QueryReporterFromContext returns the query reporter for a context.
func QueryReporterFromContext(ctx context.Context) *QueryReporter {
	if ctx == nil {
		return nil
	}

	c, _ := ctx.Value(queryReporterKey).(*QueryReporter)
	return c
}

func (c *QueryReporter) newContext(ctx context.Context) context.Context {
	return context.WithValue(ctx, queryReporterKey, c)
}
