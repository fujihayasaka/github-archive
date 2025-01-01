package parser

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/parser/geyser"
)

// ParseGeyserQuery takes legacy code search query text (the user input
// portion), parses it and converts it to the as-equivalent-as-possible
// Blackbird query.
//
// # The legacy code search syntax
//
// The legacy code search syntax is fairly simple: it doesn't allow grouping,
// and only individual terms can be negated. Phrases are allowed in quotation
// marks. Multiple terms are AND'ed together, but repeated qualifiers of the
// same type are OR'ed together before AND'ing with the rest of the query. A
// light preprocessing step is applied in dotcom to translate named entities
// like Organizations or NWOs into IDs.
//
// # Translating path-related searches
//
// As described in [Search by the file contents or file path], legacy code
// search's behavior is to search the file contents UNLESS the in: qualifier is
// specified. There are three values:
//
// 1. in:file - same as the default behavior
// 2. in:path - search only paths
// 3. in:file,path - search BOTH files and paths.
//
// Fortunately, the Geyser parser handles converting a query like "foo
// in:path,file" into a Content query OR'ed with a PathSplit query. The
// underlying Elasticsearch `path.split` field tokenizes paths on `/` to support
// searches on path segments. To translate these queries to Blackbird, we use a
// text match on path.
//
// Furthermore, the ES schema which legacy code search uses indexes tokenizes
// path hierarchies to support filtering documents based on path prefixes. The
// filename is not indexed as part of this hierarchy, so filename searches use a
// separate filename field, which is tokenized like code (e.g., tokens for case
// changes and splits at characters like `-`, `_`, `.`, etc.). Extension are
// also indexed separately as keywords to support filtering.
//
// The query language supports the following path-related filtering qualifiers
// to restrict the search:
//
// 1. path:/ is a special case to limit the search to the root directory
// 2. path:app/models limits the search to content with a path prefix of "app/models"
// 3. filename:file.txt limits the search to to files matching "file.txt"
// 4. ext:js (or ext:.js) limits the search to files ending with ".js"
//
// This behavior is described in [Search by file location]:
//
// "You can use the path qualifier to search for source code that appears at a
// specific location in a repository. Use path:/ to search for files that are
// located at the root level of a repository. Or specify a directory name or the
// path to a directory to search for files that are located within that
// directory or any of its subdirectories."
//
// To translate these path-related queries to Blackbird syntax, regexes are used
// to match the appropriate part of the path. To match the behavior of the
// legacy code search, content (instead of content AND paths) is searched by default.
//
// TODO: Drop queries without any terms (except for filename:)
//
// [Search by file location]: https://docs.github.com/en/search-github/searching-on-github/searching-code#search-by-file-location
// [Search by the file contents or file path]: https://docs.github.com/en/search-github/searching-on-github/searching-code#search-by-the-file-contents-or-file-path
func ParseGeyserQuery(ctx context.Context, text string) (*Query, error) {
	defer func() {
		if err := recover(); err != nil {
			logging.Error(ctx, "geyser query translation panicked", kvp.String("user_query", text), kvp.Any("error", err))
			panic(err) // re-panic
		}
	}()

	geyserQuery, err := geyser.ParseQuery(text)
	if err != nil {
		return nil, err
	}

	query, err := convertGeyserQuery(geyserQuery)
	if err != nil {
		return nil, err
	}

	query = RestrictGeyserQuery(query)

	SimplifyQuery(query)

	return query, nil
}

func RestrictGeyserQuery(q *Query) *Query {
	query := q

	// Restrict to non-fork repos, unless the query contains a fork qualifier already
	if !queryContainsForkQualifier(query) {
		query = And(q, NonForkRepo())
	}

	// Don't search archived repositories
	query = And(query, NonArchivedRepo())

	SimplifyQuery(query)

	return query
}

func queryContainsForkQualifier(q *Query) bool {
	if q.IsForkRepoTrait() {
		return true
	}

	for _, sq := range q.Subqueries {
		if queryContainsForkQualifier(sq) {
			return true
		}
	}

	return false
}

func convertGeyserQuery(pq *geyser.ParsedQuery) (*Query, error) {
	if len(pq.SubQueries) == 0 {
		return convertGeyserField(pq)
	}

	// TODO: The And() queries could be consolidated. I used this structure
	// because it matches how Geyser builds ES queries so it was easy to port.
	should := []*Query{}
	must := []*Query{}
	mustNot := []*Query{}
	filter := []*Query{}

	for _, subq := range pq.SubQueries {
		query, err := convertGeyserQuery(subq)
		if err != nil {
			return nil, err
		}

		switch subq.ClauseType {
		case geyser.Filter:
			filter = append(filter, query)
		case geyser.MustNot:
			mustNot = append(mustNot, Not(query))
		case geyser.Must:
			must = append(must, query)
		case geyser.Should:
			should = append(should, query)
		default:
			panic(fmt.Sprintf("unknown clause type: %s", pq.ClauseType))
		}
	}

	query := And(
		And(must...),
		And(filter...),
		And(mustNot...),
	)

	if len(should) > 0 {
		query.Subqueries = append(query.Subqueries, Or(should...))
	}

	return query, nil
}

func convertGeyserField(pq *geyser.ParsedQuery) (*Query, error) {
	if len(pq.SubQueries) > 0 {
		panic("error: called convertGeyserField with compound query")
	}

	var query *Query
	switch pq.Field {
	case geyser.Unspecified:
		return nil, errors.New("query is empty")
	case geyser.Content:
		query = Content(pq.Value)
	case geyser.Path:
		// In legacy code search, paths and filenames were indexed separately.
		// Path means to filter the search to documents matching the given
		// path, or below.
		//
		// The path field was indexed as a hierarchy, so a path like
		// app/models/users would produce tokens [app, app/models, app/models/users].
		//
		// To convert this to Blackbird, match from the root and append a final / if not present.
		path := strings.TrimPrefix(pq.Value, "/")
		if !strings.HasSuffix(path, "/") {
			path = path + "/"
		}
		query = PathRegex("^" + regexp.QuoteMeta(path))
	case geyser.PathSplit:
		// In legacy code search, paths and filenames were indexed separately.
		// PathSplit means to find matches in the text of the complete path,
		// including the filename. Blackbird indexes the whole path, so this is
		// simply a text match on the path field.
		query = Path(pq.Value)
	case geyser.RepositoryID:
		id, err := strconv.Atoi(pq.Value)
		if err != nil {
			return nil, err
		}
		query = RepoID(id)
	case geyser.LanguageID:
		id, err := strconv.Atoi(pq.Value)
		if err != nil {
			return nil, err
		}
		query = LanguageID(id)
	case geyser.SizeField:
		lower, upper, err := parseSizeQuery(pq.Value)
		if err != nil {
			return nil, err
		}
		query = MakeQualifier(SizeQualifier, NumericRange(lower, upper))
	case geyser.OwnerID:
		id, err := strconv.Atoi(pq.Value)
		if err != nil {
			return nil, err
		}
		query = OwnerID(id)
	case geyser.Fork:
		query = ForkRepo()
	case geyser.Filename:
		// In legacy code search, filename ONLY matches the filename, not the
		// path. This regex should match anything in the last component of the
		// path.
		query = PathRegex("[^/]*" + regexp.QuoteMeta(pq.Value) + "[^/]*$")
	case geyser.Extension:
		query = PathRegex(`\.` + regexp.QuoteMeta(pq.Value) + "$")
	case geyser.Visibility:
		// TODO: check on values for this, probably something like:
		//
		// query = MakeQualifier(IsQualifier, Text("public"))
		//
		// But actually we don't support that in the query language -- we probably should.
		//
		// NOTE: This may not have actually been possible to query. It seems to have been added as a filter by Geyser.
		query = PublicRepo()
	case geyser.IsRootFile:
		// IsRootFile was a stupid hack for not being able to index filenames
		// with paths in the code search Elasticsearch mapping. Effectively, it
		// means to restrict the search to files in the root directory. It is
		// triggered by searching for path:/
		//
		// See: https://github.com/github/geyser/blob/af047473b2c6ff0f47dec456da359f04472ba968/shared/adapter/code_search_classic.go#L560-L564
		query = PathRegex("^[^/]+$")
	case geyser.Owner:
		query = Owner(pq.Value)
	case geyser.Repository:
		query = Repo(pq.Value)
	case geyser.Language:
		query = Language(pq.Value)
	default:
		panic(fmt.Sprintf("unknown field type: %s", pq.Field))
	}

	return query, nil
}
