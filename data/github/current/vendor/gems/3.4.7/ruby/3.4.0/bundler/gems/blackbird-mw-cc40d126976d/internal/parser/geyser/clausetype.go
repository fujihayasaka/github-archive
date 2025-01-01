package geyser

// ClauseType is used to represent whether a clause is Must, Should, or MustNot
type ClauseType int

const (
	// Should is the default clause type. If all clauses in a group are Should, then at least one of them must match. Thus Should is analogous to a boolean OR
	Should ClauseType = iota
	// Must clauses must be matched or the overall query isn't considered a match. Thus Must is analogous to a boolean AND.
	Must
	// MustNot clauses must not be matched or otherwise the overall query isn't considered a match. Thus MustNot is analogous to a boolean Not.
	MustNot
	// Filter clauses must be matched or the overall query isn't considered a match. This is different from Must in that the clauses don't effect scoring.
	Filter
)

func (qt ClauseType) String() string {
	switch qt {
	case Should:
		return "SHOULD"
	case Must:
		return "MUST"
	case MustNot:
		return "MUST_NOT"
	case Filter:
		return "FILTER"
	default:
		return "ERROR"
	}
}
