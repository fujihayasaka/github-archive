//go:generate peg -noast -switch -inline -output grammar.peg.go grammar.peg

package parser

import (
	"context"
	"math"
	"regexp"
	"strconv"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/parser/geyser"
)

type QueryType string

const (
	TextQuery       QueryType = "text"
	RegexQuery      QueryType = "regex"
	AndQuery        QueryType = "and"
	NotQuery        QueryType = "not"
	OrQuery         QueryType = "or"
	QualifierQuery  QueryType = "qualifier"
	QueryGroup      QueryType = "group"
	NothingQuery    QueryType = "nothing"
	EverythingQuery QueryType = "everything"
	RangeQuery      QueryType = "range"
)

type QualifierType string

const (
	PathQualifier       QualifierType = "path"
	LanguageIDQualifier QualifierType = "language_id"
	TraitQualifier      QualifierType = "trait"
	OwnerIDQualifier    QualifierType = "owner_id"
	RepoIDQualifier     QualifierType = "repo_id"
	SymbolQualifier     QualifierType = "symbol"
	SymbolRefQualifier  QualifierType = "symbol_ref"
	ContentQualifier    QualifierType = "content"
	SizeQualifier       QualifierType = "size"
	PromptQualifier     QualifierType = "prompt"

	// These qualifiers are rewritten within query service to one of the others
	LanguageQualifier  QualifierType = "language"
	OwnerQualifier     QualifierType = "owner"
	RepoQualifier      QualifierType = "repo"
	IsQualifier        QualifierType = "is"
	ScopeQualifier     QualifierType = "scope"
	EmbeddingQualifier QualifierType = "embedding"
	BM25Qualifier      QualifierType = "bm25"
)

const UnspecifiedAngle = 0

type QueryTrait struct {
	// Value is the entire text of the trait, such as repo_github or
	// archived_repo. This is the value that is used in Blackbird.
	Value string
	// InverseValue will be non-empty if the QueryTrait has an opposite. For
	// example, achived_repo <=> non_archived_repo.
	InverseValue string
	// NameForIs will be non-empty if the QueryTrait can be used as a value for
	// the is: qualifier. This is the public name of the trait. For example,
	// is:archived maps to archived_repo.
	NameForIs string
}

// Query translates QueryTrait into a Query, which may be nil.
func (q *QueryTrait) Query() *Query {
	if q == nil {
		return nil
	}

	return Trait(Text(q.Value))
}

// Inverse returns the opposite of the QueryTrait, or nil if there isn't one.
func (q *QueryTrait) Inverse() *Query {
	if q == nil || q.InverseValue == "" {
		return nil
	}

	return Trait(Text(q.InverseValue))
}

// Prefix returns the prefix part of a trait's value. For example, repo_github
// would return repo_.
func (q *QueryTrait) Prefix() string {
	switch {
	case q.IsRepoNWO():
		return NWOQualifierTraitPrefix
	case q.IsRepoName():
		return RepoQualifierTraitPrefix
	case q.IsOwnerLogin():
		return OwnerQualifierTraitPrefix
	default:
		return ""
	}
}

// RequiresResolution returns true if the trait must be resolved from a name to
// an ID. For example, trait:repo_github.
func (q *QueryTrait) RequiresResolution() bool {
	return q.IsRepoName() || q.IsRepoNWO() || q.IsOwnerLogin()
}

func (q *QueryTrait) IsRepoNWO() bool {
	if q == nil {
		return false
	}

	return strings.HasPrefix(q.Value, NWOQualifierTraitPrefix)
}

func (q *QueryTrait) IsRepoName() bool {
	if q == nil {
		return false
	}

	return strings.HasPrefix(q.Value, RepoQualifierTraitPrefix)
}

func (q *QueryTrait) IsOwnerLogin() bool {
	if q == nil {
		return false
	}

	return strings.HasPrefix(q.Value, OwnerQualifierTraitPrefix)
}

func (q *QueryTrait) IsForkRepo() bool {
	if q == nil {
		return false
	}

	return strings.HasPrefix(q.Value, ForkRepoTrait.Value)
}

func (q *QueryTrait) Text() string {
	prefix := q.Prefix()
	if prefix == "" {
		return q.Value
	}

	return strings.TrimPrefix(q.Value, prefix)
}

func (q *QueryTrait) ValidForIs() bool {
	return q != nil && q.NameForIs != ""
}

// IsScoped returns true for traits that are scoped (as in scoped to a repo or org)
func (q *QueryTrait) IsScoped() bool {
	return q.IsOwnerLogin() || q.IsRepoNWO() || q.IsRepoName()
}

// Fixed value traits, defined as variables so they can be used in helper methods.
var (
	ArchivedRepoTrait        = QueryTrait{Value: "archived_repo", InverseValue: "non_archived_repo", NameForIs: "archived"}
	NonArchivedRepoTrait     = QueryTrait{Value: "non_archived_repo", InverseValue: "archived_repo"}
	DefaultBranchTrait       = QueryTrait{Value: "default_branch", InverseValue: "non_default_branch"}
	NonDefaultBranchTrait    = QueryTrait{Value: "non_default_branch", InverseValue: "default_branch"}
	PublicRepoTrait          = QueryTrait{Value: "public_repo"} // currently has no inverse
	VendoredContentTrait     = QueryTrait{Value: "vendored", InverseValue: "non_vendored", NameForIs: "vendored"}
	NonVendoredContentTrait  = QueryTrait{Value: "non_vendored", InverseValue: "vendored"}
	GeneratedContentTrait    = QueryTrait{Value: "generated", InverseValue: "non_generated", NameForIs: "generated"}
	NonGeneratedContentTrait = QueryTrait{Value: "non_generated", InverseValue: "generated"}
	ForkRepoTrait            = QueryTrait{Value: "fork", InverseValue: "non_fork", NameForIs: "fork"}
	NonForkRepoTrait         = QueryTrait{Value: "non_fork", InverseValue: "fork"}
)

var FixedValueTraits = []QueryTrait{
	ArchivedRepoTrait,
	NonArchivedRepoTrait,
	DefaultBranchTrait,
	NonDefaultBranchTrait,
	PublicRepoTrait,
	VendoredContentTrait,
	NonVendoredContentTrait,
	GeneratedContentTrait,
	NonGeneratedContentTrait,
	ForkRepoTrait,
	NonForkRepoTrait,
}

// QueryTraitForIs takes a string from an is: qualifier value and returns a
// QueryTrait if it matches a valid is: value, or nil otherwise.
//
// This is separate from QueryTraitForString to avoid making stuff like
// is:archived_repo work for users.
//
// Examples:
//
// - "archived" will return the archived repo trait.
// - "archived_repo" will return nil.
// - "foobar" will return nil.
func QueryTraitForIs(s string) *QueryTrait {
	if s == "" {
		return nil
	}

	for _, trait := range FixedValueTraits {
		if trait.NameForIs == s {
			return &trait
		}
	}

	return nil
}

// QueryTraitForString takes a string from a qualifier value and returns a
// QueryTrait if it matches a fixed name or a known prefix.
//
// This is separate from QueryTraitForIs to avoid making stuff like
// is:archived_repo work for users.

// Examples:
//
// - "archived_repo" will return the archived repo trait.
// - "repo_github" will return a query trait with that value.
// - "archived" will return nil.
// - "foobar" will return nil.
func QueryTraitForString(s string) *QueryTrait {
	for _, trait := range FixedValueTraits {
		if trait.Value == s {
			return &trait
		}
	}

	trait := &QueryTrait{Value: s}
	if trait.Prefix() == "" {
		return nil
	}

	return trait
}

const (
	RepoQualifierTraitPrefix  = "repo_"
	OwnerQualifierTraitPrefix = "owner_"
	NWOQualifierTraitPrefix   = "nwo_"
)

type Query struct {
	Kind          QueryType
	QualifierKind QualifierType
	Value         string
	IntValues     []int
	Subqueries    []*Query
	Start         uint32
	End           uint32
	IsQuoted      bool

	// Optionally attached extra metadata
	MetadataOwnerID uint32

	// Original query before rewriting (e.g. for suggestions)
	OriginalQuery *Query

	// How much to boost the score for relevant things
	ASTScore float32

	// If set, use diversity
	DivorToScore    uint32
	DivorToRetrieve uint32

	// Upper and lower bounds for numerical range query types
	LowerBound uint32
	UpperBound uint32
	Embedding  []float32
}

func (q *Query) IsDiversityEnabled() bool {
	return q.DivorToScore > 0 || q.DivorToRetrieve > 0
}

func ParseQuery(ctx context.Context, text string) (*Query, error) {
	qp := queryParser{
		Buffer:      text,
		runeMapping: NewRuneMapping(text),
		ctx:         ctx,
	}

	err := qp.Init()
	if err != nil {
		return nil, errors.Wrap(err, "could not initialize query parser")
	}
	if err := qp.Parse(); err != nil {
		return nil, err
	}

	// Drop unfinished groups: due to some strange behaviour in the parser,
	// it's possible for groups to be started but then abandoned before
	// being finished. This means that we can have accumulated groups in
	// the final stack, which must be dropped.
	for _, q := range qp.stack {
		if q.Kind == QueryGroup && len(q.Subqueries) == 0 {
			continue
		}
		return q, nil
	}

	return Nothing(), nil
}

func ClearRangeInformation(query *Query) {
	query.Start = 0
	query.End = 0

	for _, subquery := range query.Subqueries {
		ClearRangeInformation(subquery)
	}
}

func (p *queryParser) captureQuotedTextOpt(position uint32, text string) {
	opt, err := strconv.Atoi(text)
	if err != nil {
		opt = UnspecifiedAngle
	}

	p.stack[len(p.stack)-1].IntValues = []int{opt}
}

func (p *queryParser) captureQuotedText(position uint32, text string) {
	p.captureText(position-1, text)

	// Include the quotes in the start/end
	p.stack[len(p.stack)-1].Start -= 1
	p.stack[len(p.stack)-1].End += 1
	p.stack[len(p.stack)-1].IsQuoted = true
}

func (p *queryParser) captureText(position uint32, text string) {
	bytePosition := p.runeMapping.GetBytePos(position)
	unescaped := strings.Replace(text, `\"`, `"`, -1)
	unescaped = strings.Replace(unescaped, `\\`, `\`, -1)

	out := Text(unescaped)
	out.Start = bytePosition - uint32(len(text))
	out.End = bytePosition
	p.stack[len(p.stack)-1] = out

}
func parseSizeQuery(value string) (uint32, uint32, error) {
	r, err := geyser.NewIntRangeFromString(value)
	if err != nil {
		return 0, 0, err
	}

	lower := NoLowerBound
	upper := NoUpperBound
	if r.UpperLimit != nil && r.UpperLimit.Value >= 0 && r.UpperLimit.Value < math.MaxUint32 {
		upper = uint32(r.UpperLimit.Value)
		if r.UpperLimit.Inclusive {
			upper++
		}
	}
	if r.LowerLimit != nil && r.LowerLimit.Value >= 0 && r.LowerLimit.Value < math.MaxUint32 {
		lower = uint32(r.LowerLimit.Value)
		if !r.LowerLimit.Inclusive {
			lower++
		}
	}
	return lower, upper, nil
}

func (p *queryParser) captureRepo(position uint32, text string) {
	// Since repo has multiple aliases, the captured text includes the qualifier
	idx := strings.Index(text, ":")
	id, err := strconv.Atoi(text[idx+1:])

	var out *Query
	if err != nil {
		out = Repo(text[idx+1:])
	} else {
		out = RepoID(id)
	}

	bytePosition := p.runeMapping.GetBytePos(position)
	out.Start = bytePosition - uint32(len(text))
	out.End = bytePosition
	p.stack[len(p.stack)-1] = out
}

func (p *queryParser) captureLanguage(position uint32, outerText string) {
	// Since language has multiple aliases, the captured text includes the qualifier
	idx := strings.Index(outerText, ":")

	innerText := p.stack[len(p.stack)-1].Value
	id, err := strconv.Atoi(outerText[idx+1:])
	var out *Query
	if err != nil {
		out = Language(innerText)
	} else {
		out = LanguageID(id)
	}

	bytePosition := p.runeMapping.GetBytePos(position)
	out.Start = bytePosition - uint32(len(outerText))
	out.End = bytePosition
	p.stack[len(p.stack)-1] = out
}

func (p *queryParser) captureOwner(position uint32, text string) {
	idx := strings.Index(text, ":")
	out := Owner(text[idx+1:])

	bytePosition := p.runeMapping.GetBytePos(position)
	out.Start = bytePosition - uint32(len(text))
	out.End = bytePosition
	p.stack[len(p.stack)-1] = out
}

func (p *queryParser) captureSymbol(position uint32, text string) {
	// If it's a def: search with a quoted string/substring, then convert to a regex
	idx := strings.Index(text, ":")
	query := p.stack[len(p.stack)-1]
	if text[:idx] == "def" && query.Kind == TextQuery {
		// Convert to a regex
		query.Value = "(^|\\.|::)" + regexp.QuoteMeta(query.Value) + "$"
		query.Kind = RegexQuery
	}

	p.convertToQualifier(position, text, SymbolQualifier)
}

func (p *queryParser) captureSymbolRef(position uint32, text string) {
	if !experiments.IsExperimentEnabled(p.ctx, experiments.RefQualifier) {
		p.captureText(position, text)
		return
	}

	name := p.stack[len(p.stack)-1].Value
	p.convertToQualifier(position, name, SymbolRefQualifier)
}

func (p *queryParser) captureOwnerID(position uint32, text string) {
	// Since owner_id has multiple possible aliases, the captured text includes the qualifier in it
	idx := strings.Index(text, ":")
	id, err := strconv.Atoi(text[idx+1:])
	if err != nil {
		// TODO: handle this error
		id = 0
	}

	out := OwnerID(id)
	bytePosition := p.runeMapping.GetBytePos(position)
	out.Start = bytePosition - uint32(len(text))
	out.End = bytePosition
	p.stack[len(p.stack)-1] = out
}

func (p *queryParser) captureIs(position uint32, text string) {
	idx := strings.Index(text, ":")
	out := Is(text[idx+1:])

	bytePosition := p.runeMapping.GetBytePos(position)
	out.Start = bytePosition - uint32(len(text))
	out.End = bytePosition
	p.stack[len(p.stack)-1] = out
}

func (p *queryParser) capturePrompt(position uint32, text string) {
	if !experiments.IsExperimentEnabled(p.ctx, experiments.PromptQualifier) {
		p.captureText(position, text)
		return
	}

	// If we're here we've already handled quotedAt text which produces a Text query
	// with int value of the angle. Here we just transfer those values to prompt
	// qualifier.
	textQ := p.stack[len(p.stack)-1]
	maxAngle := UnspecifiedAngle
	if len(textQ.IntValues) > 0 {
		maxAngle = textQ.IntValues[0]
	}

	out := Prompt(textQ.Value, maxAngle)
	out.Start = textQ.Start - uint32(len("prompt:"))
	out.End = textQ.End

	p.stack[len(p.stack)-1] = out
}

func (p *queryParser) captureBM25(position uint32, text string) {
	if !experiments.IsExperimentEnabled(p.ctx, experiments.BM25Qualifier) {
		p.captureText(position, text)
		return
	}

	textQ := p.stack[len(p.stack)-1]
	p.stack[len(p.stack)-1] = BM25(textQ.Value)
}

func (p *queryParser) startGroup(position uint32) {
	current := p.stack[len(p.stack)-1]

	bytePosition := p.runeMapping.GetBytePos(position)
	p.stack[len(p.stack)-1] = &Query{
		Start: bytePosition,
		Kind:  QueryGroup,
	}

	p.stack = append(p.stack, current)
}

func (p *queryParser) endGroup(position uint32) {
	p.finishExpression(QueryGroup)
	bytePosition := p.runeMapping.GetBytePos(position)
	p.stack[len(p.stack)-1].End = bytePosition
}

// A group is cancelled if it finishes but didn't match. So drop the group
func (p *queryParser) cancelGroup() {
	if len(p.stack) > 1 {
		p.stack = p.stack[:len(p.stack)-1]
	}
}

func (p *queryParser) startExpression(position uint32) {
	bytePosition := p.runeMapping.GetBytePos(position)
	p.stack = append(p.stack, &Query{
		Kind:  NothingQuery,
		Start: bytePosition,
	})
}

func (p *queryParser) cancelExpression() {
	// Drop the last item on the stack
	p.stack = p.stack[:len(p.stack)-1]
}

func (p *queryParser) finishExpression(kind QueryType) {
	combinator := And
	if kind == OrQuery {
		combinator = Or
	}

	if len(p.stack) <= 1 {
		return
	}

	target := p.stack[len(p.stack)-2]
	source := p.stack[len(p.stack)-1]

	// Remove the last element of the stack
	p.stack = p.stack[:len(p.stack)-1]

	if target.Kind == NothingQuery || kind != QueryGroup && target.Kind == QueryGroup && len(target.Subqueries) == 0 {
		p.stack[len(p.stack)-1] = source
	} else if target.Kind == kind {
		// Merge nested queries into a single query
		if source.Kind == kind {
			target.Subqueries = append(target.Subqueries, source.Subqueries...)
		} else {
			target.Subqueries = append(target.Subqueries, source)
		}

		if target.Start > source.Start {
			target.Start = source.Start
		}
		if target.End < source.End {
			target.End = source.End
		}
	} else if source.Kind == OrQuery && kind == AndQuery {
		// Enforce operator precedence: AND binds tighter than OR, so steal
		// the outermost term from the OR and incorporate into the AND
		source.Subqueries[0] = And(target, source.Subqueries[0])

		// Adjust all the range boundaries to still be correct
		source.Subqueries[0].Start = target.Start
		source.Subqueries[0].End = source.Subqueries[0].Subqueries[1].End
		source.Start = target.Start

		p.stack[len(p.stack)-1] = source
	} else {
		// Merge nested queries into a single query
		if source.Kind == kind {
			source.Subqueries = append([]*Query{target}, source.Subqueries...)
			p.stack[len(p.stack)-1] = source
		} else {
			p.stack[len(p.stack)-1] = combinator(target, source)
		}

		destination := p.stack[len(p.stack)-1]
		if destination.Start > target.Start {
			destination.Start = target.Start
		}
		if destination.End < target.End {
			destination.End = target.End
		}
	}
}

func (p *queryParser) convertToQualifier(position uint32, text string, kind QualifierType) {
	out := MakeQualifier(kind, p.stack[len(p.stack)-1])

	bytePosition := p.runeMapping.GetBytePos(position)
	out.Start = bytePosition - uint32(len(text))
	out.End = bytePosition

	// Consider parsing as a glob if it's a text query using a supported qualifier.
	isSupportedQualifier := kind == PathQualifier || kind == RepoQualifier
	isUnquotedTextQuery := out.Subqueries[0].Kind == TextQuery && !out.Subqueries[0].IsQuoted

	if isSupportedQualifier && isUnquotedTextQuery {
		if IsPossibleGlobExpression(out.Subqueries[0].Value) {
			out.Subqueries[0].Kind = RegexQuery
			out.Subqueries[0].Value = ConvertGlobToRegex(out.Subqueries[0].Value)
		}
	}

	p.stack[len(p.stack)-1] = out
}

func (p *queryParser) captureNot(position uint32, text string) {
	out := Not(p.stack[len(p.stack)-1])

	bytePosition := p.runeMapping.GetBytePos(position)
	out.Start = bytePosition - uint32(len(text))
	out.End = bytePosition
	p.stack[len(p.stack)-1] = out
}

func (p *queryParser) captureRegex(position uint32, text string) {
	out := Regex(strings.Replace(text, `\/`, `/`, -1))
	bytePosition := p.runeMapping.GetBytePos(position)
	out.Start = bytePosition - uint32(len(text)) - 2
	out.End = bytePosition
	p.stack[len(p.stack)-1] = out
}
