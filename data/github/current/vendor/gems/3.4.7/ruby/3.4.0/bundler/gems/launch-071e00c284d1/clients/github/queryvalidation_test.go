package github

import (
	"regexp"
	"strings"
	"sync"
	"testing"

	"github.com/graph-gophers/graphql-go"
	"github.com/stretchr/testify/require"
)

var directive = regexp.MustCompile(`@([a-zA-Z]*)(\([^\)]+\))?`)

var loadSchemaOnce sync.Once
var loadSchemaResult struct {
	schema *graphql.Schema
	err    error
}

// loadSchema() parses the GraphQL schema
func loadSchema(t *testing.T) *graphql.Schema {
	loadSchemaOnce.Do(func() {
		// Load file bytes:
		rawSchema := fixture("schema.internal.graphql")

		// graphql-gophers/graphql does allow:
		//  - directives on types
		//  - directives on fields of input types
		var schemaIDL strings.Builder
		var multilineSkipping bool
		for _, line := range strings.Split(rawSchema, "\n") {
			if !strings.HasPrefix(line, "directive ") {
				// If we're starting a multi-line directive, skip until we see `)`
				if lineIsDirective(line) && !strings.Contains(line, ")") {
					multilineSkipping = true
					continue
				} else if multilineSkipping {
					if strings.HasSuffix(line, ")") {
						multilineSkipping = false
					}
					continue
				}
				line = directive.ReplaceAllString(line, "")
			}
			schemaIDL.WriteString(line + "\n")
		}

		// graphql-gophers/graphql requires a schema definition for mapping to root types:
		schemaIDL.WriteString(`schema {
		  query: Query
		  mutation: Mutation
		}`)

		// Parse doctored schema:
		loadSchemaResult.schema, loadSchemaResult.err = graphql.ParseSchema(schemaIDL.String(), nil, graphql.UseStringDescriptions())
	})
	require.NoError(t, loadSchemaResult.err)
	return loadSchemaResult.schema
}

func lineIsDirective(line string) bool {
	directives := []string{
		"@possibleTypes",
		"@underDevelopment",
		"@deprecated",
		"@useNextGlobalIdFormat",
		"@serviceMapping",
	}
	for _, directive := range directives {
		if strings.Contains(line, directive) {
			return true
		}
	}
	return false
}
