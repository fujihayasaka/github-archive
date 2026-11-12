package parser

import (
	"fmt"

	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/types"
)

const NoLowerBound = uint32(0)
const NoUpperBound = ^uint32(0)

// Compound takes a QueryType (which must be one of AndQuery, OrQuery,
// or QueryGroup) and a slice of subqueries and returns an AND/OR/GROUP query.
// It returns nil and an error if the QueryType doesn't accept subqueries.
func Compound(qt QueryType, subqueries ...*Query) (*Query, error) {
	switch qt {
	case AndQuery:
		return And(subqueries...), nil
	case OrQuery:
		return Or(subqueries...), nil
	case QueryGroup:
		return Group(subqueries...), nil
	default:
		return nil, errors.Errorf("cannot create compound query of type %q", qt)
	}
}

func Text(t string) *Query {
	return &Query{
		Value: t,
		Kind:  TextQuery,
	}
}

func Regex(t string) *Query {
	return &Query{
		Value: t,
		Kind:  RegexQuery,
	}
}

func NumericRange(lower, upper uint32) *Query {
	return &Query{
		Kind:       RangeQuery,
		LowerBound: lower,
		UpperBound: upper,
	}
}

func Group(subqueries ...*Query) *Query {
	start := ^uint32(0)
	end := uint32(0)

	for _, subquery := range subqueries {
		if subquery.Start < start {
			start = subquery.Start
		}
		if subquery.End > end {
			end = subquery.End
		}
	}

	return &Query{
		Kind:       QueryGroup,
		Subqueries: subqueries,
		Start:      start,
		End:        end,
	}
}

func (q *Query) IsNothing() bool {
	return q.Kind == NothingQuery
}

// Rewrites the node as Nothing, but preserves the original query which is then
// later used for user facing error messages in the case of malformed or invalid
// qualifier values.
//
// TODO: Refactor this!
func RewriteAsNothing(original *Query) *Query {
	return &Query{
		Kind:          NothingQuery,
		OriginalQuery: original,
	}
}

func Nothing() *Query {
	return &Query{
		Kind: NothingQuery,
	}
}

func Everything() *Query {
	return &Query{
		Kind: EverythingQuery,
	}
}

func And(subqueries ...*Query) *Query {
	out := Group(subqueries...)
	out.Kind = AndQuery
	return out
}

func Or(subqueries ...*Query) *Query {
	out := Group(subqueries...)
	out.Kind = OrQuery
	return out
}

func Content(text string) *Query {
	return MakeQualifier(ContentQualifier, Text(text))
}

func RepoID(ids ...int) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: RepoIDQualifier,
		IntValues:     ids,
	}
}

func OwnerID(ids ...int) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: OwnerIDQualifier,
		IntValues:     ids,
	}
}

func Owner(name string) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: OwnerQualifier,
		Value:         name,
	}
}

func Language(name string) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: LanguageQualifier,
		Value:         name,
	}
}

func Repo(name string) *Query {
	return MakeQualifier(RepoQualifier, Text(name))
}

func Path(path string) *Query {
	return MakeQualifier(PathQualifier, Text(path))
}

func PathRegex(regex string) *Query {
	return MakeQualifier(PathQualifier, Regex(regex))
}

func LanguageID(ids ...int) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: LanguageIDQualifier,
		IntValues:     ids,
	}
}

func DefaultBranch() *Query {
	return Trait(Text("default_branch"))
}

func Is(value string) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: IsQualifier,
		Value:         value,
	}
}

func Prompt(prompt string, angle int) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: PromptQualifier,
		Value:         prompt,
		IntValues:     []int{angle},
	}
}

func BM25(query string) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: BM25Qualifier,
		Value:         query,
	}
}

func Embedding(embedding []float32, angle int) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: EmbeddingQualifier,
		Embedding:     embedding,
		IntValues:     []int{angle},
	}
}

func Trait(subquery *Query) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: TraitQualifier,
		Subqueries:    []*Query{subquery},
	}
}

func PublicRepo() *Query {
	return Trait(Text(PublicRepoTrait.Value))
}

func ArchivedRepo() *Query {
	return Trait(Text(ArchivedRepoTrait.Value))
}

func NonArchivedRepo() *Query {
	return Trait(Text(NonArchivedRepoTrait.Value))
}

func NumTrailingZeros(zeros int) *Query {
	return Trait(Text(fmt.Sprintf("trailing_zeros_%d", zeros)))
}

// OwnerLoginTrait trait, e.g., trait:owner_<LOGIN>
func OwnerLoginTrait(login string) *Query {
	return Trait(Text(fmt.Sprintf("%s%s", OwnerQualifierTraitPrefix, login)))
}

// RepoNameTrait trait, e.g., trait:repo_<NAME>
func RepoNameTrait(name string) *Query {
	return Trait(Text(fmt.Sprintf("%s%s", RepoQualifierTraitPrefix, name)))
}

// RepoNWOTrait trait, e.g., trait:nwo_<NWO>
func RepoNWOTrait(nwo string) *Query {
	return Trait(Text(fmt.Sprintf("%s%s", NWOQualifierTraitPrefix, nwo)))
}

// VendoredTrait trait, e.g., trait:vendored
func VendoredTrait() *Query {
	return VendoredContentTrait.Query()
}

// NonVendoredTrait trait, e.g., trait:non_vendored
func NonVendoredTrait() *Query {
	return NonVendoredContentTrait.Query()
}

// GeneratedTrait trait, e.g., trait:generated
func GeneratedTrait() *Query {
	return GeneratedContentTrait.Query()
}

// NonGeneratedTrait trait, e.g., trait:non_generated
func NonGeneratedTrait() *Query {
	return NonGeneratedContentTrait.Query()
}

func ForkRepo() *Query {
	return ForkRepoTrait.Query()
}

func NonForkRepo() *Query {
	return NonForkRepoTrait.Query()
}

// Trait returns a QueryTrait, or nil if this isn't a trait: or is: Query.
func (q *Query) Trait() *QueryTrait {
	if q.Kind == QualifierQuery && q.QualifierKind == IsQualifier {
		return QueryTraitForIs(q.Value)
	}

	if q.Kind == QualifierQuery && q.QualifierKind == TraitQualifier && len(q.Subqueries) == 1 && q.Subqueries[0].Kind == TextQuery {
		return QueryTraitForString(q.Subqueries[0].Value)
	}

	return nil
}

func (q *Query) IsDefaultBranchTrait() bool {
	return q.Trait() != nil && q.Trait().Value == DefaultBranchTrait.Value
}

func (q *Query) IsPublicRepoTrait() bool {
	return q.Trait() != nil && q.Trait().Value == PublicRepoTrait.Value
}

func (q *Query) IsOwnerLoginTrait() bool {
	return q.Trait().IsOwnerLogin()
}

func (q *Query) IsRepoNWOTrait() bool {
	return q.Trait().IsRepoNWO()
}

func (q *Query) IsRepoNameTrait() bool {
	return q.Trait().IsRepoName()
}

func (q *Query) IsForkRepoTrait() bool {
	return q.Trait().IsForkRepo()
}

func Not(subquery *Query) *Query {
	return &Query{
		Kind:       NotQuery,
		Subqueries: []*Query{subquery},
		Start:      subquery.Start,
		End:        subquery.End,
	}
}

func Symbol(subquery *Query) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: SymbolQualifier,
		Subqueries:    []*Query{subquery},
		Start:         subquery.Start,
		End:           subquery.End,
	}
}

func SymbolRef(subquery *Query) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: SymbolRefQualifier,
		Subqueries:    []*Query{subquery},
		Start:         subquery.Start,
		End:           subquery.End,
	}
}

func MakeQualifier(kind QualifierType, subquery *Query) *Query {
	return &Query{
		Kind:          QualifierQuery,
		QualifierKind: kind,
		Subqueries:    []*Query{subquery},
		Start:         subquery.Start,
		End:           subquery.End,
	}
}

func FindQueryUnderCursor(query *Query, cursor uint32) *Query {
	if len(query.Subqueries) > 0 {
		for _, subquery := range query.Subqueries {
			if node := FindQueryUnderCursor(subquery, cursor); node != nil {
				return node
			}
		}
	}

	if query.Start <= cursor && cursor <= query.End {
		return query
	}
	return nil
}

// This function determines the set of repo IDs that this query is exclusively scoped to.
// For example, the query:
//
//	(repo_id:123 OR repo_id:345) AND language:python
//
// is exclusively scoped to repos 123 and 345. But the query
//
//	repo_id:123 OR repo_id:345 OR language:python
//
// is not restricted to a particular set of repos, so the set of exclusively scoped repos is empty.
func GetScopeRepoIDs(query *Query) []types.RepoID {
	if query.Kind == OrQuery {
		output := []types.RepoID{}
		for _, q := range query.Subqueries {
			nodeScope := GetScopeRepoIDs(q)
			if len(nodeScope) == 0 {
				return nodeScope
			}
			output = append(output, nodeScope...)
		}
		return output
	} else if query.Kind == AndQuery || query.Kind == QueryGroup {
		output := []types.RepoID{}
		for _, q := range query.Subqueries {
			output = append(output, GetScopeRepoIDs(q)...)
		}
		return output
	} else if query.Kind == QualifierQuery && query.QualifierKind == RepoIDQualifier {
		output := []types.RepoID{}
		for _, v := range query.IntValues {
			output = append(output, types.RepoID(v))
		}
		return output
	}

	return []types.RepoID{}
}

func GetRepoIDQualifiers(query *Query) []*Query {
	return findRepoIDQualifiers(query, []*Query{})
}

func findRepoIDQualifiers(query *Query, qualifiers []*Query) []*Query {
	if query.Kind == QualifierQuery && query.QualifierKind == RepoIDQualifier {
		qualifiers = append(qualifiers, query)
	}

	for _, q := range query.Subqueries {
		qualifiers = findRepoIDQualifiers(q, qualifiers)
	}

	return qualifiers
}

func Transform(query *Query, transform func(node *Query) bool) {
	shouldRecurse := transform(query)
	if !shouldRecurse {
		return
	}

	// Recursively transform all subqueries
	for _, sub := range query.Subqueries {
		Transform(sub, transform)
	}
}

func RewriteQueryForSuggestions(query *Query) {
	Transform(query, func(node *Query) bool {
		if node.Kind == QualifierQuery {
			return false
		}

		if node.Kind == TextQuery {
			inner := *node

			const (
				suggestDiversityScoreLimit     = 5
				suggestDiversityRetrievalLimit = 10 * suggestDiversityScoreLimit // TODO: Continue to adjust this number
			)

			pq := MakeQualifier(PathQualifier, &inner)
			pq.DivorToScore = suggestDiversityScoreLimit
			pq.DivorToRetrieve = suggestDiversityRetrievalLimit

			sq := MakeQualifier(SymbolQualifier, &inner)
			sq.DivorToScore = suggestDiversityScoreLimit
			sq.DivorToRetrieve = suggestDiversityRetrievalLimit

			*node = *Or(
				pq,
				sq,
			)
			// Don't recurse if we modified the node
			return false
		}
		// Recurse into all other subqueries
		return true
	})
}

// Determines whether a query is scoped to an org or repo (vs global)
func IsScoped(query *Query) bool {
	switch query.Kind {
	case QualifierQuery:
		switch {
		case query.QualifierKind == RepoQualifier:
			return true
		case query.QualifierKind == RepoIDQualifier:
			return true
		case query.QualifierKind == OwnerQualifier:
			return true
		case query.QualifierKind == OwnerIDQualifier:
			return true
		case query.Trait().IsScoped():
			return true
		}
	case OrQuery:
		// In case of an OR query, all branches must be scoped or it is unscoped
		if len(query.Subqueries) == 0 {
			return false
		}
		for _, sub := range query.Subqueries {
			if !IsScoped(sub) {
				return false
			}
		}
		return true
	case AndQuery:
		// In case of an AND query, at least one branch must be scoped
		if len(query.Subqueries) == 0 {
			return false
		}
		for _, sub := range query.Subqueries {
			if IsScoped(sub) {
				return true
			}
		}
		return false
	}
	return false
}

func DeepCopy(query *Query) Query {
	out := *query
	out.Subqueries = make([]*Query, 0, len(out.Subqueries))
	for _, sq := range query.Subqueries {
		copied := DeepCopy(sq)
		out.Subqueries = append(out.Subqueries, &copied)
	}

	if query.OriginalQuery != nil {
		copied := DeepCopy(query.OriginalQuery)
		out.OriginalQuery = &copied
	}

	return out
}

// ResetRange is used to override the AST position information for query nodes
// which are not part of the users typed query
func ResetRange(query *Query, start, end uint32) {
	query.Start = start
	query.End = end
	for _, q := range query.Subqueries {
		ResetRange(q, start, end)
	}
}

func MakeCountQuery(query *Query) *Query {
	everything := Everything()
	everything.DivorToScore = constants.CountExactDivorToScore
	everything.DivorToRetrieve = constants.CountDivorToRetrieve

	zeros := []*Query{everything}

	for i := 1; i < constants.MaxTrailingZeros; i++ {
		q := Trait(Text(fmt.Sprintf("trailing_zeros_%d", i)))
		q.DivorToScore = constants.CountApproximateDivorToScore
		q.DivorToRetrieve = constants.CountDivorToRetrieve
		zeros = append(zeros, q)
	}

	return And(
		query,
		Or(
			zeros...,
		),
	)
}

func MakeCountQueryProto(query *querypb.Query) *querypb.Query {
	everything := Everything()
	everything.DivorToScore = constants.CountExactDivorToScore
	everything.DivorToRetrieve = constants.CountDivorToRetrieve

	subqueries := []*querypb.Query{
		ConvertToProto(everything),
	}

	for i := 1; i < constants.MaxTrailingZeros; i++ {
		q := Trait(Text(fmt.Sprintf("trailing_zeros_%d", i)))
		q.DivorToScore = constants.CountApproximateDivorToScore
		q.DivorToRetrieve = constants.CountDivorToRetrieve
		subqueries = append(subqueries, ConvertToProto(q))
	}

	return &querypb.Query{
		Kind: querypb.QueryKind_QUERY_KIND_AND,
		Subqueries: []*querypb.Query{
			query,
			{
				Kind:       querypb.QueryKind_QUERY_KIND_OR,
				Subqueries: subqueries,
			},
		},
	}
}

func IsEmbeddingSearch(query *querypb.Query) bool {
	if query.Domain == querypb.Domain_DOMAIN_DENSE {
		return true
	}

	for _, s := range query.Subqueries {
		if IsEmbeddingSearch(s) {
			return true
		}
	}
	return false
}
