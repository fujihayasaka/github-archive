package parser

import (
	"context"
	"fmt"
	"math"
	"strings"
	"time"

	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/linguist/pkg/linguist"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/models"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/redact"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/types"
)

// RewriteQuery takes an end-user query and rewrites it by converting qualifiers
// to blackbird's qualifiers (e.g. language: => language_id:) and adding
// filters. The passed in query is mutated.
//
// Returns a slice of QueryErrors for display to the end-user (which may be
// empty) or an error which means that rewriting failed. In that case the query
// RPC must fail.
func RewriteQuery(
	ctx context.Context,
	query *Query,
	actor *models.Actor,
	tenant *pb.Tenant,
	index search.Index,
	customScopes map[string]*Query,
	promptRewriter PromptRewriter,
) ([]*QueryError, int, error) {
	return rewriteQueryViaSnapshotSearch(ctx, query, actor, tenant, index, customScopes, promptRewriter)
}

// Extract a flattened list of all terms of the same type. For example,
// a nested structure of AND or OR terms would flatten into a single OR.
func getFlattenedTerms(query *Query, kind QueryType) []*Query {
	var out []*Query

	// Don't flatten DivOR nodes
	if (query.Kind == kind && !query.IsDiversityEnabled()) || query.Kind == QueryGroup {
		for _, q := range query.Subqueries {
			out = append(out, getFlattenedTerms(q, kind)...)
		}
	} else {
		out = []*Query{query}
	}

	return out
}

// SimplifyQuery is a final re-write step to remove Everything and Nothing
// nodes and un-necessary structure in the AST.
//
// NOTE: SimplifyQuery will potentially drop all information about the original
// query, e.g. by rewriting nodes as Nothing or dropping branches of an
// unsatisfiable AND. Therefore, a simplified query should not be re-displayed
// to a user; use their original query instead.
func SimplifyQuery(query *Query) {
	for _, sub := range query.Subqueries {
		SimplifyQuery(sub)
	}

	switch query.Kind {
	case NotQuery:
		// TODO: Empty not => Everything?
		// TODO: A NOT with more than one subquery isn't defined, panic on that?
		if len(query.Subqueries) == 1 {
			if query.Subqueries[0].Kind == EverythingQuery {
				*query = *Nothing()
			} else if query.Subqueries[0].Kind == NothingQuery {
				*query = *Everything()
			}
		}
	case AndQuery:
		newSubqueries := []*Query{}
		for _, sub := range query.Subqueries {
			// if there are any nothings, turn whole query into a nothing
			if sub.Kind == NothingQuery {
				*query = *Nothing()
				return
			}
			// remove everything nodes from subqueries
			if sub.Kind != EverythingQuery {
				newSubqueries = append(newSubqueries, sub)
			}
		}

		// If there are no subqueries return everything
		if len(newSubqueries) == 0 {
			*query = *Everything()
			return
		}

		// If there's just one subquery, remove the outer and
		if len(newSubqueries) == 1 {
			*query = *newSubqueries[0]
			return
		}

		// Otherwise, re-write to the new list of subqueries
		query.Subqueries = newSubqueries

		// If this AND condition contains both repo and org IDs, just drop the org IDs
		// since those are not useful.
		redundantOwnerID := -1
		for _, q := range query.Subqueries {
			if q.Kind == QualifierQuery && q.QualifierKind == RepoIDQualifier {
				redundantOwnerID = int(q.MetadataOwnerID)
				break
			}
		}
		if redundantOwnerID != -1 {
			pos := 0
			for i, q := range query.Subqueries {
				// Only exclude terms which are made redundant by existing repo qualifiers. Keep terms that are contradictory,
				// since those make the query unsatisfiable. Simplifying the query shouldn't change whether it is satisfiable
				// or not.
				if q.Kind == QualifierQuery && q.QualifierKind == OwnerIDQualifier && len(q.IntValues) == 1 && q.IntValues[0] == redundantOwnerID {
					continue
				}
				query.Subqueries[pos] = query.Subqueries[i]
				pos++
			}
			query.Subqueries = query.Subqueries[:pos]
		}

		// Flatten all terms down to a single set, but if diveristy is
		// enabled, don't restructure the AND query.
		if !query.IsDiversityEnabled() {
			query.Subqueries = getFlattenedTerms(query, AndQuery)
		}
	case OrQuery:
		// Don't simplify divOR nodes
		if query.IsDiversityEnabled() {
			return
		}

		newSubqueries := []*Query{}
		for _, sub := range query.Subqueries {
			// if there are any everything, turn whole query into a everything
			if sub.Kind == EverythingQuery {
				*query = *Everything()
				return
			}
			// remove nothing nodes from subqueries
			if sub.Kind != NothingQuery {
				newSubqueries = append(newSubqueries, sub)
			}
		}

		// If there are no subqueries return nothing
		if len(newSubqueries) == 0 {
			*query = *Nothing()
			return
		}

		// If there's just one subquery, remove the outer or
		if len(newSubqueries) == 1 {
			*query = *newSubqueries[0]
			return
		}

		// Otherwise, re-write to the new list of subqueries
		query.Subqueries = newSubqueries

		// Flatten all terms down to a single set
		query.Subqueries = getFlattenedTerms(query, OrQuery)

		// Merge multiple terms together
		langPos := -1
		repoPos := -1
		ownerPos := -1
		pos := 0
		for idx, q := range query.Subqueries {
			if q.Kind == QualifierQuery && q.QualifierKind == LanguageIDQualifier {
				if langPos == -1 {
					langPos = pos
				} else {
					query.Subqueries[langPos].IntValues = append(query.Subqueries[langPos].IntValues, q.IntValues...)
					continue
				}
			} else if q.Kind == QualifierQuery && q.QualifierKind == RepoIDQualifier {
				if repoPos == -1 {
					repoPos = pos
				} else {
					query.Subqueries[repoPos].IntValues = append(query.Subqueries[repoPos].IntValues, q.IntValues...)
					continue
				}
			} else if q.Kind == QualifierQuery && q.QualifierKind == OwnerIDQualifier {
				if ownerPos == -1 {
					ownerPos = pos
				} else {
					query.Subqueries[ownerPos].IntValues = append(query.Subqueries[ownerPos].IntValues, q.IntValues...)
					continue
				}
			}

			query.Subqueries[pos] = query.Subqueries[idx]
			pos++
		}
		query.Subqueries = query.Subqueries[:pos]

		if len(query.Subqueries) == 1 {
			*query = *query.Subqueries[0]
		}
	case QueryGroup:
		*query = *query.Subqueries[0]
	}

}

// Returns true if the query is globally scoped. A globally scoped query
// targets all public repos AND all repos accessible to the user.
func isGloballyScoped(ctx context.Context, query *Query) bool {
	global := true
	if query.Kind == QualifierQuery && query.QualifierKind == RepoIDQualifier {
		global = false
	} else if query.Kind == QualifierQuery && query.IsRepoNWOTrait() {
		global = false
	} else {
		any := len(query.Subqueries) == 0
		all := true
		for _, sub := range query.Subqueries {
			isGlobal := isGloballyScoped(ctx, sub)
			if isGlobal {
				any = true
			} else {
				all = false
			}
		}

		// Is this part of of the AST globally scoped?
		//   - AND node: all children must be globally scoped
		//   - OR node: any one child must be globally scoped
		//   - NOT node: always globally scoped
		//   - trait:public_repo - never globally scoped
		switch query.Kind {
		case AndQuery:
			global = all
		case OrQuery:
			global = any
		case NotQuery:
			global = true
		case QualifierQuery:
			if query.IsPublicRepoTrait() {
				global = false
			}
		}
	}

	return global
}

// shouldFilterByRepoIDs returns true if the query re-writer should filter by
// repo_ids instead of owner_ids.
func shouldFilterByRepoIDs(actor *models.Actor) bool {
	if actor == nil {
		return true
	}

	// For a small number of repos, this is always preferable.
	if len(actor.AccessiblePrivateRepoIDs) <= 10 {
		return true
	}

	// if looking at owners dramatically reduces the size of the rewrite it's
	// worth filtering by owners and having to do the post processing work.
	if 2*len(actor.AccessibleOrganizationIDs) < len(actor.AccessiblePrivateRepoIDs) {
		return false
	}

	// Default is to filter by repos
	return true
}

// filterToRepos rewrites the query to only target public repos and private
// repos in the accessible_repo_ids list.
func filterToRepos(ctx context.Context, query *Query, actor *models.Actor) {
	inner := *query
	// Optionally wrap in an OR node and make sure that public repos are always searchable.
	if actor != nil && len(actor.AccessiblePrivateRepoIDs) > 0 {
		repoIDs := make([]int, 0, len(actor.AccessiblePrivateRepoIDs))
		for repoID := range actor.AccessiblePrivateRepoIDs {
			repoIDs = append(repoIDs, int(repoID))
		}
		*query = *And(&inner, Or(RepoID(repoIDs...), PublicRepo()))
	} else {
		*query = *And(&inner, PublicRepo())
	}
}

// filterToOwners rewrites the query to make sure that we only search for:
// - public repos
// - results in user/org accounts that the user has access to
func filterToOwners(ctx context.Context, query *Query, actor *models.Actor) {
	inner := *query
	// Optionally wrap in an OR node and make sure that public repos are always searchable.
	if actor != nil && len(actor.AccessibleOrganizationIDs) > 0 {
		ownerIDs := make([]int, 0, len(actor.AccessibleOrganizationIDs))
		for ownerID := range actor.AccessibleOrganizationIDs {
			ownerIDs = append(ownerIDs, int(ownerID))
		}
		*query = *And(&inner, Or(OwnerID(ownerIDs...), PublicRepo()))
	} else {
		*query = *And(&inner, PublicRepo())
	}
}

func rewriteCustomScopes(query *Query, customScopes map[string]*Query, isNested bool) []*QueryError {
	if query.Kind == QualifierQuery && query.QualifierKind == ScopeQualifier {
		inner := query.Subqueries[0]
		if strings.HasPrefix(inner.Value, "@") {
			// If the query starts with @, we treat it as an owner/org name
			original := *query
			*query = *Owner(inner.Value[1:])
			query.Start = original.Start
			query.End = original.End
			query.OriginalQuery = &original
			query.MetadataOwnerID = original.MetadataOwnerID
		} else if strings.Contains(inner.Value, "/") {
			// If the query contains a slash, it must be a repo name
			original := *query
			*query = *Repo(inner.Value)
			query.Start = original.Start
			query.End = original.End
			query.OriginalQuery = &original
			query.MetadataOwnerID = original.MetadataOwnerID
		} else if namedQuery, ok := customScopes[inner.Value]; ok {
			// All other names must be named custom scopes
			original := *query
			*query = DeepCopy(namedQuery)
			ResetRange(query, original.Start, original.End)
			query.OriginalQuery = &original
			query.MetadataOwnerID = original.MetadataOwnerID

			// It's possible for an in: qualifier to be rewritten into something
			// else that contains an in: qualifier, so we will need to resolve it a
			// second time. Note that this does not go on forever, since we
			// disallow nested named custom scopes, so we can't reach this
			// condition again on our second pass.
			return rewriteCustomScopes(query, nil, true)

		} else {
			message := fmt.Sprintf("Unknown custom scope: %v", inner.Value)
			if isNested {
				message = "Named scopes cannot be nested"
			}
			return []*QueryError{{
				Message: message,
				Ranges:  []Range{{query.Start, query.End}},
				Type:    ErrorTypeParsingFatal,
			}}
		}
	}

	for _, subquery := range query.Subqueries {
		err := rewriteCustomScopes(subquery, customScopes, isNested)
		if err != nil {
			return err
		}
	}

	return nil
}

func reportUnresolvedCustomScopes(query *Query) []*QueryError {
	if query.Kind == QualifierQuery && query.QualifierKind == ScopeQualifier {
		return []*QueryError{{
			Message: "Named scopes cannot be nested",
			Ranges:  []Range{{query.Start, query.End}},
			Type:    ErrorTypeParsingFatal,
		}}
	}

	for _, subquery := range query.Subqueries {
		err := reportUnresolvedCustomScopes(subquery)
		if err != nil {
			return err
		}
	}

	return nil
}

func pushDownNots(query *Query) error {
	switch query.Kind {
	case AndQuery, OrQuery, QueryGroup:
		for _, sub := range query.Subqueries {
			err := pushDownNots(sub)
			if err != nil {
				return err
			}
		}
	case NotQuery:
		if len(query.Subqueries) != 1 {
			return errors.Errorf("got %d subquery for NOT, this shouldn't happen", len(query.Subqueries))
		}

		subquery := query.Subqueries[0]

		switch subquery.Kind {
		case AndQuery, OrQuery, QueryGroup:
			notQueries := make([]*Query, 0, len(subquery.Subqueries))
			for _, sub := range subquery.Subqueries {
				notQueries = append(notQueries, Not(sub))
			}

			var replacementKind QueryType
			switch subquery.Kind {
			case AndQuery:
				replacementKind = OrQuery
			case OrQuery:
				replacementKind = AndQuery
			case QueryGroup:
				replacementKind = QueryGroup
			default:
				return errors.Errorf("logic error: unexpected subquery kind %q after checking", subquery.Kind)
			}

			replacement, err := Compound(replacementKind, notQueries...)
			if err != nil {
				return err
			}

			err = pushDownNots(replacement)
			if err != nil {
				return err
			}
			*query = *replacement
		case NotQuery:
			replacement := subquery.Subqueries[0]
			err := pushDownNots(replacement)
			if err != nil {
				return err
			}
			*query = *replacement
		case QualifierQuery:
			// Invert traits. Example: NOT trait:archived_repo => trait:non_archived_repo
			replacement := subquery.Trait().Inverse()
			if replacement != nil {
				*query = *replacement
			}
		}
	default:
		// don't do anything
	}

	return nil

}

// filterToDefaultBranch adds the trait:default_branch qualifier so that only
// results on the default branch of a repo will be returned.
func filterToDefaultBranch(query *Query) {
	current := *query
	*query = *And(&current, DefaultBranch())
}

// hasBranchTrait returns true if a trait qualifier with either default_branch or
// non_default_branch was specified anwhere in the query AST.
func hasBranchTrait(query *Query) bool {
	if query.Kind == QualifierQuery && query.QualifierKind == TraitQualifier {
		if len(query.Subqueries) > 0 {
			v := query.Subqueries[0].Value
			return v == "default_branch" || v == "non_default_branch"
		}
	} else if len(query.Subqueries) > 0 {
		for _, q := range query.Subqueries {
			if hasBranchTrait(q) {
				return true
			}
		}
	}
	return false
}

// Helper for logging
func Serialize(queries ...*Query) string {
	if len(queries) == 0 {
		return ""
	} else if len(queries) == 1 {
		query := queries[0]
		if query == nil {
			return ""
		} else if query.Kind == "" {
			query.Kind = "??"
		} else if query.Kind == TextQuery || query.Kind == RegexQuery {
			return fmt.Sprintf("%s(%q)", query.Kind, query.Value)
		} else if query.Kind == QualifierQuery {
			if len(query.Subqueries) > 0 {
				return fmt.Sprintf("%s(%s)", query.QualifierKind, Serialize(query.Subqueries...))
			} else if query.QualifierKind == PromptQualifier && len(query.IntValues) > 0 {
				return fmt.Sprintf("%s(%q@%d)", query.QualifierKind, query.Value, query.IntValues[0])
			} else if query.Value == "" {
				return fmt.Sprintf("%s(%v)", query.QualifierKind, query.IntValues)
			}
			return fmt.Sprintf("%s(%q)", query.QualifierKind, query.Value)
		}

		// Detect and render recursive queries, rather than crashing
		for _, sq := range query.Subqueries {
			if sq == query {
				return fmt.Sprintf("%s(RECURSIVE!)", query.Kind)
			}
		}

		return fmt.Sprintf("%s(%s)", query.Kind, Serialize(query.Subqueries...))
	} else {
		rendered := []string{}
		for _, query := range queries {
			rendered = append(rendered, Serialize(query))
		}
		return strings.Join(rendered, ",")
	}
}

//
// New
//

// rewriteQueryViaSnapshotSearch takes an end-user query and rewrites it by
// 1. Sending the query to blackbird to resolve repos and owners. Calculating embeddings for prompt qualifiers
// 2. Converting qualifiers to their _id representation where appropriate (e.g. language: => language_id:)
// 3. Adding filters for accessible repos (or orgs).
//
// NOTE: The passed in query is mutated.
//
// Returns a slice of QueryErrors for display to the end-user (which may be
// empty), a count of how many calls to get embeddings were made, and an error which means
// that rewriting failed. In that case the query RPC must fail.
func rewriteQueryViaSnapshotSearch(
	ctx context.Context,
	query *Query,
	actor *models.Actor,
	tenant *pb.Tenant,
	index search.Index,
	customScopes map[string]*Query,
	promptRewriter PromptRewriter,
) ([]*QueryError, int, error) {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "query_service.query_rewrite.duration", time.Since(start), stats.Tags{"method": "via-snapshots"})
	}()

	var embeddingCount int

	queryBeforeRewrite := Serialize(query)

	// Start by rewriting custom scopes
	queryErrors := rewriteCustomScopes(query, customScopes, false)
	if queryErrors != nil {
		return queryErrors, embeddingCount, nil
	}

	// Fail if any remaining unresolved custom scopes exist
	queryErrors = reportUnresolvedCustomScopes(query)
	if queryErrors != nil {
		return queryErrors, embeddingCount, nil
	}

	queryErrors = rewriteLanguage(query)
	if queryErrors != nil {
		return queryErrors, embeddingCount, nil
	}

	if err := rewritePromptQualifier(ctx, query, actor, promptRewriter, &embeddingCount); err != nil {
		return nil, embeddingCount, err
	}

	// Only qualify the query with default branch if the incoming query doesn't have the
	// default_branch or non_default_branch qualifier at all
	if !hasBranchTrait(query) {
		filterToDefaultBranch(query)
	}

	explicitQualifiers, queryErrors := rewriteReposAndOwners(ctx, query, tenant)
	if len(queryErrors) > 0 {
		return queryErrors, embeddingCount, nil
	}

	// Once we rewrite the original query we must build two different caches, one that allows us to resolve explicit
	// repos/owner qualifiers and the second cache is built if the query still has other bare qualifiers. We then use
	// both of these caches to issue snapshot queries.

	var cache = search.NewRepoAndOwnerCache()
	var err error
	// Resolve any explicit qualifiers separately.
	if explicitQualifiers != nil {
		cache, err = index.BuildCacheFromQuery(ctx, isGloballyScoped(ctx, explicitQualifiers), actor, ConvertToProto(explicitQualifiers))
		if err != nil {
			return nil, embeddingCount, err
		}
	}

	isEmbeddingSearch := embeddingCount > 0

	// Rewrite repo and org qualifiers to their id representations
	queryErrors = []*QueryError{}
	rewriteQualifiersWithSnapshotData(ctx, query, cache, isEmbeddingSearch, promptRewriter, &queryErrors)
	// Add accessible repos to the query (if necessary).
	filteredBy := addAccessibleResourcesFilter(ctx, actor, query)

	// Simplify the query by pushing NOTs down as far as possible and eliminating unnecessary NOTs
	err = pushDownNots(query)
	if err != nil {
		return nil, embeddingCount, err
	}

	kvps := []kvp.Field{
		kvp.String("global_filtered_by", string(filteredBy)),
		kvp.Duration("duration_ms", time.Since(start)),
	}

	if !experiments.IsExperimentEnabled(ctx, experiments.DisableQueryLogging) {
		kvps = append(kvps, kvp.String("query_before_rewrite", redact.Redact(queryBeforeRewrite)), kvp.String("query_after_rewrite", redact.Redact(Serialize(query))))
	}

	logging.Info(ctx, "re-wrote query via snapshot search", kvps...)

	return queryErrors, embeddingCount, nil
}

// This function does 2 things:
//
//  1. It rewrites/mutates `query` so that `repo:` and `owner:` qualifiers are
//     rewritten to `trait:` (if possible). The following rules apply for rewriting:
//
//     owner:<login> =>
//     - trait:owner_<login> (if login is valid)
//     - owner:<owner>       (if owner is a regex - TODO)
//     - nothing             (if login is invalid)
//
//     repo:<nwo> =>
//     - trait:nwo_<nwo>   (if nwo is valid)
//     - trait:repo_<name> (if name is valid - TODO)
//     - repo:<repo>       (if repo is a regex - TODO)
//     - nothing           (if nwo is blank)
//
//  2. It extracts the values of the explicit repo or owner qualifiers and holds
//     onto them (as subqueries) during the rewriting process. These subqueries
//     are then ORed together so that we can send it to blackbird for resolving
//     them.
//
// This function needs to perform 2 separate operations so that it can maintain the
// form of the original query (for actual query execution) while making sure that
// the snapshot searches successfully resolve.
//
// It's not always possible for blackbird resolve qualifiers in the query's original form.
// For example: `repo:github.com/blackbird-mw repo:github.com/blackbird` is a contradictory
// (unsatisfiable) query and cannot be used for searching snapshots (blackbird would return
// 0 results). But for the linter to mark this query unsatisfiable we must still resolve
// qualifiers and rewrite it with correct IDs.
//
// This function returns 2 values:
//   - The first value is an ORed query that contains all the explicit qualifiers e.g.
//     repo:github/blackbird or owner:a_valid_owner_login etc.
//   - The second is the list of errors encountered when rewriting repos and owners.
func rewriteReposAndOwners(ctx context.Context, query *Query, tenant *pb.Tenant) (*Query, []*QueryError) {
	subqueries, queryErrors := rewriteReposAndOwnersInner(ctx, query, tenant)
	if len(subqueries) == 0 {
		return nil, queryErrors
	}

	return Or(subqueries...), queryErrors
}

func rewriteReposAndOwnersInner(ctx context.Context, query *Query, tenant *pb.Tenant) ([]*Query, []*QueryError) {
	subqueries := []*Query{}
	queryErrors := []*QueryError{}

	switch query.Kind {
	case QualifierQuery:
		switch query.QualifierKind {
		case RepoIDQualifier:
			// NB: Even though we already have ids, it's important to check against
			// the user's accessible resources.
			subqueries = append(subqueries, RepoID(query.IntValues...))
		case OwnerIDQualifier:
			subqueries = append(subqueries, OwnerID(query.IntValues...))
		case RepoQualifier:
			original := *query
			val := query.Subqueries[0].Value
			if len(val) == 0 {
				*query = *RewriteAsNothing(&original)
				break
			}

			nwo, err := types.NewNWO(val)
			if err != nil {
				// Bare repo qualifiers are not allowed for now so return an error but... this will change in future.
				qErr := &QueryError{
					Message: fmt.Sprintf("Invalid repository name: %s", val),
					Ranges:  []Range{{Start: original.Start, End: original.End}},
					Type:    ErrorTypeParsingWarning,
				}
				queryErrors = append(queryErrors, qErr)
				*query = *RewriteAsNothing(&original)
			} else {
				// repo:a/b
				val = nwo.NameWithUniqueOwner(tenant)
				*query = *RepoNWOTrait(val)
				query.OriginalQuery = &original
				query.Start = original.Start
				query.End = original.End
				subqueries = append(subqueries, RepoNWOTrait(val))
			}
		case OwnerQualifier:
			original := *query
			if len(query.Value) == 0 {
				*query = *RewriteAsNothing(&original)
				break
			}

			// TODO: Support regexes in `owner:`` queries (requires changing
			// grammar.peg and looking at query.Subqueries[0] instead of the query
			// directly)
			// if original.Subqueries[0].Kind == RegexQuery {
			// 	// owner:/[^]a/
			//  We only need to resolve the non explicit qualifiers so set this to
			//  true when we're ready to handle regex queries.
			//  needsResolving = true
			// }
			owner, err := types.NewOwner(query.Value)
			if err != nil {
				// invalid login
				qErr := &QueryError{
					Message: fmt.Sprintf("Invalid owner: %s", query.Value),
					Ranges:  []Range{{Start: query.Start, End: query.End}},
					Type:    ErrorTypeParsingWarning,
				}
				queryErrors = append(queryErrors, qErr)
				*query = *RewriteAsNothing(&original)
			} else {
				// owner:a
				val := owner.UniqueLogin(tenant)
				*query = *OwnerLoginTrait(val)
				query.OriginalQuery = &original
				query.Start = original.Start
				query.End = original.End
				subqueries = append(subqueries, OwnerLoginTrait(val))
			}
		case IsQualifier:
			original := *query
			traitQuery := query.Trait().Query()
			if traitQuery != nil {
				*query = *traitQuery
				query.OriginalQuery = &original
			} else {
				// Not a valid is: query. Rewrite to a text query
				query.OriginalQuery = &original
				query.QualifierKind = ""
				query.Kind = TextQuery
				query.Value = fmt.Sprintf("is:%s", query.Value)
			}
		}
	}

	for _, subquery := range query.Subqueries {
		if query.Kind != NothingQuery {
			sq, qe := rewriteReposAndOwnersInner(ctx, subquery, tenant)
			subqueries = append(subqueries, sq...)
			queryErrors = append(queryErrors, qe...)
		}
	}

	return subqueries, queryErrors
}

// rewrites qualifiers using a RepoAndOwnerCache built using a snapshot query.
//
// Rewrite rules:
//
// trait:nwo_<nwo> =>
//   - repo_id:<id> (if repo exists and is accessible)
//   - nothing      (if repo doesn't exist or is not accessible)
//
// trait:owner_<login> =>
//   - owner_id:<id> (if owner exists)
//   - nothing       (if owner doesn't exist)
//
// repo_id:<id> =>
//   - nothing (if repo doesn't exist or is not accessible)
//
// owner_id:<id> =>
//   - nothing (if owner doesn't exist)
//
// language:<lang> =>
//   - language_id:<id> (if lang exists)
//   - nothing          (if lang doesn't exist)
func rewriteQualifiersWithSnapshotData(
	ctx context.Context,
	query *Query,
	cache *search.RepoAndOwnerCache,
	isEmbeddingSearch bool,
	promptRewriter PromptRewriter,
	errors *[]*QueryError,
) {
	switch query.Kind {
	case QualifierQuery:
		switch query.QualifierKind {
		case TraitQualifier:
			trait := query.Trait()
			switch {
			case trait.IsRepoNWO():
				original := *query
				nwo := strings.ToLower(trait.Text())
				ctx = statting.WithTags(ctx, stats.Tags{"rpc": "user_query", "is_embedding_search": fmt.Sprintf("%t", isEmbeddingSearch)})
				if repo, ok := cache.ReposByNWO[nwo]; ok {
					queryError := nwoQueryErrorFromSnapshot(repo, query)
					if queryError != nil {
						logging.Info(ctx, "search miss: repo has a permanent error",
							kvp.String("nwo", nwo),
							kvp.String("error", queryError.Message),
							kvp.Int("repo_id", int(repo.RepoId)),
							kvp.Int("owner_id", int(repo.OwnerId)),
							kvp.Bool("is_embedding_search", isEmbeddingSearch))
						statting.Counter(ctx, "repo_indexed.miss", 1, stats.Tags{"reason": "permanent_error"})
						*errors = append(*errors, queryError)
						*query = *RewriteAsNothing(&original)
						break
					}

					*query = *RepoID(int(repo.RepoId))
					query.OriginalQuery = &original
					query.Start = original.Start
					query.End = original.End
					query.MetadataOwnerID = repo.OwnerId

					if isEmbeddingSearch {
						queryError := promptRewriter.ValidateRepo(ctx, query, repo)
						if queryError != nil {
							// I believe this ValidateRepo check is only for hybrid clusters where a repo might be in the lexical
							// index, but not have the right experiment flags set for semantic search.
							//
							// TODO: We should probably be re-writing the query to nothing here (b/c the repo isn't indexed for
							// semantic search)
							logging.Info(ctx, "search miss: repo does not have the experiments set for semantic search",
								kvp.String("nwo", nwo),
								kvp.String("error", queryError.Message),
								kvp.Int("repo_id", int(repo.RepoId)),
								kvp.Int("owner_id", int(repo.OwnerId)),
								kvp.Bool("is_embedding_search", isEmbeddingSearch))
							statting.Counter(ctx, "repo_indexed.miss", 1, stats.Tags{"reason": "experiment_not_set"})
							*errors = append(*errors, queryError)
							break
						}
						logging.Info(ctx, "search hit: repo is indexed for semantic search",
							kvp.String("nwo", nwo),
							kvp.Int("repo_id", int(repo.RepoId)),
							kvp.Int("owner_id", int(repo.OwnerId)),
							kvp.Bool("is_embedding_search", isEmbeddingSearch))
					}

					statting.Counter(ctx, "repo_indexed.hit", 1)
					break
				}

				if repo, ok := cache.SnapshotReposByNWO[nwo]; ok {
					logging.Info(ctx, "search miss: repo exists in the index but user does not have access",
						kvp.String("nwo", nwo),
						kvp.Int("repo_id", int(repo.RepoId)),
						kvp.Int("owner_id", int(repo.OwnerId)),
						kvp.Bool("is_embedding_search", isEmbeddingSearch))
					statting.Counter(ctx, "repo_indexed.miss", 1, stats.Tags{"reason": "user_acls"})
				} else {
					logging.Info(ctx, "search miss: repo is not indexed",
						kvp.String("nwo", nwo),
						kvp.Bool("is_embedding_search", isEmbeddingSearch))
					statting.Counter(ctx, "repo_indexed.miss", 1, stats.Tags{"reason": "not_indexed"})
				}

				*query = *RewriteAsNothing(&original)
				*errors = append(*errors, &QueryError{
					Message:                fmt.Sprintf("Unknown repo: %q", original.OriginalQuery.Subqueries[0].Value),
					Ranges:                 []Range{{original.Start, original.End}},
					InaccessibleRepoOrgNWO: original.OriginalQuery.Subqueries[0].Value,
					Type:                   ErrorTypeMissingInaccessibleRepoOrg,
				})

			case trait.IsOwnerLogin():
				original := *query
				login := strings.ToLower(trait.Text())
				if owner, ok := cache.OwnersByLogin[login]; ok {
					*query = *OwnerID(int(owner.OwnerID))
					query.OriginalQuery = &original
					query.Start = original.Start
					query.End = original.End
					break
				}
				*query = *RewriteAsNothing(&original)
				*errors = append(*errors, &QueryError{
					// NB: Just so "Unknown owner" doesn't appear in user facing error messages
					Message:                fmt.Sprintf("Unknown org or user: %q", original.OriginalQuery.Value),
					Ranges:                 []Range{{original.Start, original.End}},
					InaccessibleRepoOrgNWO: original.OriginalQuery.Value,
					Type:                   ErrorTypeMissingInaccessibleRepoOrg,
				})
			}

		case RepoIDQualifier:
			// NB: repo_ids that are not accessible are re-written to Nothing. This is
			// important to avoid leaking the existence of a repo that the user does
			// not have access too (exfiltration).
			//
			// Repo IDs that have a PermanentError are also rewritten as nothing.
			repo, ok := cache.ReposByID[types.RepoIDFromInt(query.IntValues[0])]
			if !ok || repo.PermanentErrorType != entities.PermanentErrorType_ERROR_UNKNOWN {
				original := *query
				*query = *RewriteAsNothing(&original)
				*errors = append(*errors, &QueryError{
					Message: fmt.Sprintf("Unknown repo_id: %v", original.IntValues),
					Ranges:  []Range{{original.Start, original.End}},
					Type:    ErrorTypeParsingWarning,
				})
			}

		case OwnerIDQualifier:
			// NB: owner_ids that are not found are re-written to Nothing. While the
			// existence of org logins is public knowledge, this helps to distinguish
			// between orgs that aren't in the search index at all vs. no search
			// results for a particular org. Different user error messages can be
			// shown respectively.
			id := query.IntValues[0]
			if id < 0 || id > math.MaxUint32 {
				panic(fmt.Sprintf("parser error: invalid owner ID: %d", id))
			}

			if _, ok := cache.OwnersByID[uint32(id)]; !ok {
				original := *query
				*query = *RewriteAsNothing(&original)
			}

		case IsQualifier:
			original := *query
			trait := query.Trait().Query()
			if trait != nil {
				*query = *trait
				query.OriginalQuery = &original
			} else {
				// Not a valid is: query. Rewrite to a text query
				query.OriginalQuery = &original
				query.QualifierKind = ""
				query.Kind = TextQuery
				query.Value = fmt.Sprintf("is:%s", query.Value)
			}
		}
	}

	for _, subquery := range query.Subqueries {
		if query.Kind != NothingQuery {
			rewriteQualifiersWithSnapshotData(ctx, subquery, cache, isEmbeddingSearch, promptRewriter, errors)
		}
	}
}

type filterBy string

const (
	filterByRepos      filterBy = "repos"
	filterByOwners     filterBy = "owners"
	filterByRepoScoped filterBy = "repo scoped"
)

// Detect if the query is globally scoped and if so, add the appropriate filter
// for accessible repos (or owners). Repo scoped queries do not need this and
// are passed along as-is.
func addAccessibleResourcesFilter(ctx context.Context, actor *models.Actor, query *Query) filterBy {
	// If this is a globally scoped query, restrict to the
	// accessiblePrivateRepoIDs list (exact visibility filter, but potentially a
	// very large list) OR restrict to user/org accounts accessible to the user
	// (potentially a smaller list, but only an approximate visibility filter).
	if isGloballyScoped(ctx, query) {
		// TODO: Measure the len of the accessiblePrivateRepoIDs compared to the len of the
		// ownerIDs list to understand how much this optimization is helping.
		if shouldFilterByRepoIDs(actor) {
			filterToRepos(ctx, query, actor)
			return filterByRepos
		} else {
			filterToOwners(ctx, query, actor)
			return filterByOwners
		}
	}
	return filterByRepoScoped
}

func rewriteLanguage(query *Query) []*QueryError {
	switch query.Kind {
	case QualifierQuery:
		switch query.QualifierKind {
		case LanguageQualifier:
			if langID, err := linguist.GetLanguageByAlias(query.Value); err == nil {
				query.QualifierKind = LanguageIDQualifier
				query.IntValues = []int{int(langID)}
				query.Value = ""
				break
			}
			return []*QueryError{{
				Message: fmt.Sprintf("Unknown %s: %q", query.QualifierKind, query.Value),
				Ranges:  []Range{{query.Start, query.End}},
				Type:    ErrorTypeParsingFatal,
			}}
		}
	}

	for _, subquery := range query.Subqueries {
		if query.Kind != NothingQuery {
			if err := rewriteLanguage(subquery); err != nil {
				return err
			}
		}
	}

	return nil
}

// rewritePromptQualifier uses the provided [PromptRewriter] to rewrite any
// `prompt` qualifiers in the query.
func rewritePromptQualifier(ctx context.Context, query *Query, actor *models.Actor, promptRewriter PromptRewriter, embeddingCount *int) error {
	switch query.Kind {
	case QualifierQuery:
		switch query.QualifierKind {
		case PromptQualifier:
			if !experiments.IsExperimentEnabled(ctx, experiments.PromptQualifier) {
				panic("prompt experiment is not enabled, should've been rewritten to text by the query parser")
			}

			err := promptRewriter.RewritePrompt(ctx, query, actor)
			*embeddingCount++
			if err != nil {
				return err
			}
		}
	}

	for _, subquery := range query.Subqueries {
		if query.Kind != NothingQuery {
			if err := rewritePromptQualifier(ctx, subquery, actor, promptRewriter, embeddingCount); err != nil {
				return err
			}
		}
	}

	return nil
}

// nwoQueryErrorFromSnapshot returns a QueryError based on the snapshot. This
// should be used when the user queried an NWO; the NWO they typed is used in
// the error. Returns nil when there is no error on the snapshot.
func nwoQueryErrorFromSnapshot(entry *snapshotpb.SnapshotEntry, query *Query) *QueryError {
	// The NWO as the user typed it, not rewritten for traits or tenant shortcodes.
	queryNWO := query.OriginalQuery.Subqueries[0].Value
	var message string
	var errType ErrorType
	switch entry.PermanentErrorType {
	case entities.PermanentErrorType_ERROR_UNKNOWN: // NOTE: this is the default enum value. It means no error.
		return nil
	case entities.PermanentErrorType_SYSTEM_LIMIT:
		message = fmt.Sprintf("%s cannot be searched because it is too large", queryNWO)
		errType = ErrorTypeSystemLimit
	case entities.PermanentErrorType_RETRIES_EXHAUSTED:
		message = fmt.Sprintf("%s cannot be searched because it failed to index repeatedly", queryNWO)
		errType = ErrorTypeRetriesExhausted
	case entities.PermanentErrorType_INVALID_DEFAULT_REF:
		message = fmt.Sprintf("%s cannot be searched because its default branch name is not UTF-8", queryNWO)
		errType = ErrorTypeInvalidDefaultRef
	case entities.PermanentErrorType_BAD_COMMIT:
		message = fmt.Sprintf("%s cannot be searched because its latest commit couldn't be loaded", queryNWO)
		errType = ErrorTypeKindBadCommit
	default:
		// a vauge error that nevertheless indicates the system knows about the repo. We WILL NOT say it will be indexed.
		message = fmt.Sprintf("%s is cannot be searched because it could not be indexed", queryNWO)
		errType = ErrorTypeParsingWarning
	}

	return &QueryError{
		Message: message,
		Ranges:  []Range{{Start: query.Start, End: query.End}},
		Type:    errType,
	}
}
