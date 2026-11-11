//go:generate peg -inline -output geyser.peg.go geyser.peg
package geyser

import (
	"fmt"
	"strings"
)

var verbose = false

type gHQualifier string

const (
	unspecifiedQualifier gHQualifier = ""
	languageIDQualifier  gHQualifier = "language_id"
	languageQualifier    gHQualifier = "language"
	inQualifier          gHQualifier = "in"
	sizeQualifier        gHQualifier = "size"
	forkQualifier        gHQualifier = "fork"
	pathQualifier        gHQualifier = "path"
	filenameQualifier    gHQualifier = "filename"
	extensionQualifier   gHQualifier = "extension"
	repoIDQualifier      gHQualifier = "repo_id"
	repoQualifier        gHQualifier = "repo"
	orgIDQualifier       gHQualifier = "org_id"
	orgQualifier         gHQualifier = "org"
	userIDQualifier      gHQualifier = "user_id"
	userQualifier        gHQualifier = "user"
	sortQualifier        gHQualifier = "sort"
)

func fieldFromGHQualifier(qual gHQualifier) (Field, error) {
	switch qual {
	case repoIDQualifier:
		return RepositoryID, nil
	case orgIDQualifier:
		return OwnerID, nil
	case userIDQualifier:
		return OwnerID, nil
	case languageIDQualifier:
		return LanguageID, nil
	case filenameQualifier:
		return Filename, nil
	case repoQualifier:
		return Repository, nil
	case userQualifier:
		return Owner, nil
	case orgQualifier:
		return Owner, nil
	case languageQualifier:
		return Language, nil
	default:
		return Unspecified, QueryParserError(fmt.Sprintf("no such qualifier \"%s\"", qual))
	}
}

// ParseQuery for v2 parses GitHub syntax.
func ParseQuery(query string) (pq *ParsedQuery, err error) {
	defer func() {
		// panic can be raised if their is a parse error outside of the grammar, see usages of `GeyserParseError`
		if r := recover(); r != nil {
			if e, ok := r.(GeyserParseError); ok {
				pq = nil
				err = &e
			} else {
				panic(r)
			}
		}
	}()
	qp := geyserParser{
		Buffer: query,
	}
	err = qp.Init()
	if err != nil {
		return nil, err
	}

	if err := qp.Parse(); err != nil {
		return nil, err
	}
	qp.Execute()
	gHQuery := qp.gHQuery
	parsedQuery, err := convertGHQueryToParsedQuery(gHQuery)
	return parsedQuery, err
}

// convertGHQueryToParsedQuery serves the critical role of converting the parsed github query into a ParsedQuery
// that is used in cooper to create the final ES query.
//
// As described in https://github.com/github/code-search/blob/master/docs/code-search/adrs/0018-github-search-dsl.md#queries-with-multiple-clauses
// the basic idea is that all clauses are grouped together by qualifier, the "default" qualifier-group (which typically
// corresponds to the `file` qualifier) becomes a Must clause whereas the other groups become Filter clauses.
//
// Converting the parsedGHQuery to a ParsedQuery is a 2 step process. First we iterate through the clauses  of the parsedGHQuery, create leaf ParsedQuery's
// and group these according to whether or not they're negated and according to the field they modify. Second, for each of these groups, if they're associated
// with a negation (NOT or - prefix) then we place the associated leaf ParsedQueries into a MustNot ParsedQuery; if they are not negated, then they are added
// to a parent Should ParsedQuery because each qualifier associated with the same field is ORed together. Be careful though because there are exceptions at
// both levels of the ParsedQuery construction.
func convertGHQueryToParsedQuery(gHQuery *parsedGHQuery) (*ParsedQuery, error) {
	// this is to check and make sure that the certain qualifiers are only used once
	forkQualifierUsed := false
	inQualifierUsed := false

	// collect clauses into groups according to their qualifier and whether or not they are negated
	type operatorQualifier struct {
		negated bool
		fld     Field
	}
	gHQuery.searchInField = []Field{Content}
	parsedQueryMap := map[operatorQualifier][]*ParsedQuery{}
	opQualList := []operatorQualifier{} // tracking order so that the query is constructed in a stable order
	// collect clauses
	for _, gHClause := range gHQuery.clauses {
		// for each gHClause create the corresponding ParsedQuery
		var parsedQuery *ParsedQuery
		switch gHClause.qualifier {
		case sortQualifier:
			// for now we're just dropping this because dotcom is expected to provide the "official" sorting parameters through twirp
			continue
		case inQualifier:
			if inQualifierUsed {
				return nil, QueryParserError("`in` qualifier can only be used once")
			}
			inQualifierUsed = true
			switch gHClause.value {
			case "file":
				gHQuery.searchInField = []Field{Content}
			case "path":
				gHQuery.searchInField = []Field{PathSplit}
			case "path,file", "file,path":
				gHQuery.searchInField = []Field{PathSplit, Content}
			default:
				return nil, QueryParserError(fmt.Sprintf("value for `in` qualifier must be `file`, `path`, or a CSV list of those; found `%s`", gHClause.value))
			}
			continue // `in` doesn't correspond to a real clause but instead modifies the meaning of other clauses
		case pathQualifier:
			if gHClause.value == "/" {
				parsedQuery = &ParsedQuery{
					Field:      IsRootFile,
					Value:      "true",
					IsPhrase:   true,
					ClauseType: Should,
				}
			} else {
				parsedQuery = &ParsedQuery{
					Field:      Path,
					Value:      gHClause.value,
					IsPhrase:   true,
					ClauseType: Should,
				}
			}
		case forkQualifier:
			if forkQualifierUsed {
				return nil, QueryParserError("`fork` qualifier can only be used once")
			}
			forkQualifierUsed = true
			if gHClause.value != "true" && gHClause.value != "only" {
				return nil, QueryParserError(fmt.Sprintf("value for `fork` qualifier must be one of `true` or `only`, found `%s`", gHClause.value))
			}

			// NOTE: Geyser searched forks by default, but very few forks were
			// actually indexed. Users could restrict their search to forks with
			// fork:only. This contradicts the documentation and was probably a
			// bug:
			//
			//   To include forks with more stars than their parent in the
			//   search results, you will need to add fork:true or fork:only to
			//   your query.
			//
			// To be more like the Geyser behavior, Blackbird's translator
			// excludes forks unless the user askes to search for them. To fix a
			// user complaint, I'm extending this to fork:only AND fork:true
			//
			// Original comment:
			//
			//   Because we only index "leader" forks, then, unlike the other
			//   searchables, the default behavior is to match everything, and
			//   no filter is needed. But if the user specifies "only" then we
			//   add the `fork:true` filter
			if gHClause.value == "only" || gHClause.value == "true" {
				parsedQuery = &ParsedQuery{
					Field:      Fork,
					Value:      "true",
					IsPhrase:   true,
					ClauseType: Should,
				}
			} else {
				continue
			}
		case sizeQualifier:
			_, err := NewIntRangeFromString(gHClause.value)
			if err != nil { // this should never occur because the only possible values of gHClause.qualifier are listed in the peg file
				return nil, err
			}
			parsedQuery = &ParsedQuery{
				Field:      SizeField,
				Value:      gHClause.value,
				IsPhrase:   true,
				ClauseType: Should,
			}
		case extensionQualifier:
			parsedQuery = &ParsedQuery{
				Field:      Extension,
				Value:      strings.TrimLeft(gHClause.value, "."),
				IsPhrase:   true,
				ClauseType: Should,
			}
		case unspecifiedQualifier: // this corresponds to search keywords
			boolQueryClauseType := Must
			if gHClause.negated {
				boolQueryClauseType = Should
			}
			parsedQuery = &ParsedQuery{
				Field:      Unspecified,
				Value:      gHClause.value,
				IsPhrase:   true,                // assumption: not differentiating terms and phrases due to use of "match" query
				ClauseType: boolQueryClauseType, // TODO: weird b/c no-op because opQual handles this separately
			}
		default: // these can be directly converted
			fld, err := fieldFromGHQualifier(gHClause.qualifier)
			if err != nil { // this should never occur because the only possible values of gHClause.qualifier are listed in the peg file
				return nil, err
			}
			parsedQuery = &ParsedQuery{
				Field:      fld,
				Value:      gHClause.value,
				IsPhrase:   true,
				ClauseType: Should,
			}
		}

		opQual := operatorQualifier{gHClause.negated, parsedQuery.Field}
		if _, present := parsedQueryMap[opQual]; !present {
			opQualList = append(opQualList, opQual)
		}
		parsedQueryMap[opQual] = append(parsedQueryMap[opQual], parsedQuery)
	}

	// assemble clause groups into final ParsedQuery
	finalParsedQuery := &ParsedQuery{}
	for _, opQual := range opQualList {
		subClauses := parsedQueryMap[opQual]
		qualGroupParsedQuery := &ParsedQuery{}

		// clausetype
		if opQual.negated {
			qualGroupParsedQuery.ClauseType = MustNot
		} else {
			if opQual.fld == Unspecified {
				// This corresponds to search keywords. Unlike all other non-negated groups, the keywords are Musted together rather than serving as filters
				qualGroupParsedQuery.ClauseType = Must
			} else {
				// Non-search keyword fields aren't scored and therefore get a Filter clause type
				qualGroupParsedQuery.ClauseType = Filter
			}
		}

		// qualifier
		if opQual.fld == Unspecified {
			// Rewrite all clauses with Unspecified qualifiers as ones qualified by whatever field or fields is in searchIn
			// This could be Content, Path, or Content and Path
			if len(gHQuery.searchInField) == 1 {
				// This is the simplest case in which the user has specified in:path or in:file (the default)
				for _, clause := range subClauses {
					clause.Field = gHQuery.searchInField[0]
				}
				qualGroupParsedQuery.Field = gHQuery.searchInField[0]
			} else {
				// This case is more complicated because the user has specified they need to match in one of the two fields `path` or `content`.
				// for each field we construct a clause requiring all of the keywords to match and then we SHOULD these 2 together in the existing
				// qualGroupParsedQuery which is already set to clausetype=MUST
				newSubClauses := []*ParsedQuery{}
				for _, fld := range gHQuery.searchInField {
					perFieldSubClauses := []*ParsedQuery{}
					perFieldClause := &ParsedQuery{}
					for _, clause := range subClauses {
						newClause := Clone(clause)
						newClause.Field = fld
						newClause.ClauseType = Must
						perFieldSubClauses = append(perFieldSubClauses, newClause)
					}
					perFieldClause.SubQueries = perFieldSubClauses
					perFieldClause.ClauseType = Should
					newSubClauses = append(newSubClauses, perFieldClause)
				}
				subClauses = newSubClauses
				// NOTE: at this point if there is only a single keyword, then we have an extra layer of query. For example if the user
				// searches `foo in:path,field` then the resulting query is `+( ( +path.split:"foo" ) ( +content:"foo" ) )`
				// but this could be turned into the equivalent query `+( path.split:"foo" content:"foo" )`. But the query is rare and the
				// "fix" requires making this already complicated function even more complicated, so for now I decided no to do this.
			}
		} else {
			qualGroupParsedQuery.Field = opQual.fld
		}

		// value (this just simplifies the final query by removing a level of nesting if this group only has 1 clause)
		if len(subClauses) == 1 {
			qualGroupParsedQuery.Value = subClauses[0].Value
			qualGroupParsedQuery.IsPhrase = true
		} else { // presumably len_subClauses is greater than 1
			qualGroupParsedQuery.SubQueries = subClauses
		}

		finalParsedQuery.SubQueries = append(finalParsedQuery.SubQueries, qualGroupParsedQuery)
	}

	// simplify: if there is only a single clause then don't stick it in a group
	if len(finalParsedQuery.SubQueries) == 1 && finalParsedQuery.SubQueries[0].ClauseType != MustNot {
		// NOTE: I'm excluding MustNot here because a pure negation set of SubQueries implicitly includes a match_all
		// rolling that up doesn't make sense
		wrappedQuery := finalParsedQuery.SubQueries[0]
		finalParsedQuery.Value = wrappedQuery.Value
		finalParsedQuery.Field = wrappedQuery.Field
		finalParsedQuery.SubQueries = wrappedQuery.SubQueries
		finalParsedQuery.ClauseType = wrappedQuery.ClauseType
		if finalParsedQuery.Value != "" {
			finalParsedQuery.IsPhrase = true
		}
	}
	return finalParsedQuery, nil
}

type gHClause struct {
	qualifier gHQualifier
	value     string
	negated   bool
}

type parsedGHQuery struct {
	clauses       []*gHClause
	searchInField []Field
}

func (pq *parsedGHQuery) String() string {
	clauseStrings := []string{}
	for _, gHClause := range pq.clauses {
		var negated string
		if gHClause.negated {
			negated = "-"
		} else {
			negated = ""
		}
		var clauseString string
		if gHClause.qualifier != "" {
			qualifier := string(gHClause.qualifier)
			clauseString = fmt.Sprintf("%s%s:%s", negated, qualifier, gHClause.value)
		} else {
			clauseString = fmt.Sprintf("%s%s", negated, gHClause.value)
		}
		clauseStrings = append(clauseStrings, clauseString)
	}
	return strings.Join(clauseStrings, " ")
}

func (qp *geyserParser) start() {
	qp.gHQuery = &parsedGHQuery{}
	qp.gHClause = &gHClause{}
	qp.printState("Start")
}

func (qp *geyserParser) finalizeClause() {
	qp.gHQuery.clauses = append(qp.gHQuery.clauses, qp.gHClause)
	qp.gHClause = &gHClause{}
	qp.printState("FinalizeClause")
}

func (qp *geyserParser) captureNegation() {
	qp.gHClause.negated = true
	qp.printState("Negation")
}

func (qp *geyserParser) captureQualifier(text string) {
	qp.gHClause.qualifier = gHQualifier(text)
	qp.printState("Qualifier>", text)
}

func (qp *geyserParser) captureQuotedValue(text string) {
	text = strings.Replace(text, `\"`, `"`, -1)
	text = strings.Replace(text, `\\`, `\`, -1)
	qp.gHClause.value = text
	qp.printState("QuotedValue>", text)
}

func (qp *geyserParser) captureLikelyValue(text string) {
	qp.gHClause.value = text
	qp.printState("LikelyValue>", text)
}

func (qp *geyserParser) printState(messages ...string) {
	if verbose {
		message := strings.Join(messages, " ")
		fmt.Println(message)
	}
}
