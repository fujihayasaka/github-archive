package github

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/graph-gophers/graphql-go"
	"github.com/pkg/errors"
)

/**
 * Attempts to parse the provided responses for each query received, allowing
 * GQL response parsing code to be unit-tested.
 */
type parsingGQLRunner struct {
	requestCount int
	responses    []string
}

var _ gqlRunner = (*parsingGQLRunner)(nil)

func (p *parsingGQLRunner) do(_ context.Context, _, _, _ string, _ map[string]any, dest any, _ http.Header) (*GraphQLResponse, error) {
	i := p.requestCount
	p.requestCount++
	if i >= len(p.responses) {
		return nil, errors.Errorf("no response specified for request number %v", i+1)
	}

	r := GraphQLResponse{
		Data: dest,
	}
	err := json.Unmarshal([]byte(p.responses[i]), &r)
	if err != nil {
		return nil, errors.Wrap(err, "parsingGQLRunner: response JSON invalid")
	}

	return &r, errorsFromResponse(&r)
}

// Records outgoing requests, and validates them against our schema.
// Always returns RecordingGQLRunnerNoResponse error, use EqualError to
// write tests to ensure the query was well formed vs our schema:
//
//	var dest SomeType
//	_, err := r.Query(ctx, query, vars, &dest)
//	require.EqualError(t, err, RecordingGQLRunnerNoResponse)
//	// from this point we can be sure the GQL query was valid vs our schema
//	assert.Contains(t, r.queries[0], "something")
type recordingAndValidatingGQLRunner struct {
	schema  *graphql.Schema
	queries []graphQLRequest
}

var _ gqlRunner = (*recordingAndValidatingGQLRunner)(nil)

const RecordingGQLRunnerNoResponse = "outgoing validation only"

func (r *recordingAndValidatingGQLRunner) do(_ context.Context, _, _, query string, variables map[string]any, _ any, _ http.Header) (*GraphQLResponse, error) {
	r.queries = append(r.queries, graphQLRequest{
		Query:     query,
		Variables: variables,
	})
	queryErrors := r.schema.ValidateWithVariables(query, variables)
	if queryErrors != nil {
		js, err := json.Marshal(queryErrors)
		if err == nil {
			return nil, errors.Errorf("invalid GQL query for schema:\n%s", js)
		}
		// show what we've got
		fmt.Println(queryErrors)
		return nil, errors.Errorf("invalid GQL query for schema")
	}
	return nil, errors.New(RecordingGQLRunnerNoResponse)
}
