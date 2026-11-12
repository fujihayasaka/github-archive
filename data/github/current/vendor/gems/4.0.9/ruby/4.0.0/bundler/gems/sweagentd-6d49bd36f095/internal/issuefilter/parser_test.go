package issuefilter

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ---------------------------------------------------------------------------
// Tokenizer tests
// ---------------------------------------------------------------------------

func TestTokenize_EmptyString(t *testing.T) {
	tokens := tokenize("")
	assert.Empty(t, tokens)
}

func TestTokenize_WhitespaceOnly(t *testing.T) {
	tokens := tokenize("   \t\n  ")
	assert.Empty(t, tokens)
}

func TestTokenize_SingleWord(t *testing.T) {
	tokens := tokenize("bug")
	require.Len(t, tokens, 1)
	assert.Equal(t, tokWord, tokens[0].typ)
	assert.Equal(t, "bug", tokens[0].value)
}

func TestTokenize_MultipleWords(t *testing.T) {
	tokens := tokenize("hello world")
	require.Len(t, tokens, 2)
	assert.Equal(t, "hello", tokens[0].value)
	assert.Equal(t, "world", tokens[1].value)
}

func TestTokenize_QualifierToken(t *testing.T) {
	tokens := tokenize("label:bug")
	require.Len(t, tokens, 1)
	assert.Equal(t, tokWord, tokens[0].typ)
	assert.Equal(t, "label:bug", tokens[0].value)
}

func TestTokenize_Parentheses(t *testing.T) {
	tokens := tokenize("(label:bug)")
	require.Len(t, tokens, 3)
	assert.Equal(t, tokLParen, tokens[0].typ)
	assert.Equal(t, tokWord, tokens[1].typ)
	assert.Equal(t, tokRParen, tokens[2].typ)
}

func TestTokenize_QuotedValue(t *testing.T) {
	tokens := tokenize(`label:"good first issue"`)
	require.Len(t, tokens, 1)
	assert.Equal(t, `label:"good first issue"`, tokens[0].value)
}

func TestTokenize_LeadingTrailingWhitespace(t *testing.T) {
	tokens := tokenize("  label:bug  ")
	require.Len(t, tokens, 1)
	assert.Equal(t, "label:bug", tokens[0].value)
}

func TestTokenize_TabsAndNewlines(t *testing.T) {
	tokens := tokenize("label:bug\thas:assignee\nno:label")
	require.Len(t, tokens, 3)
	assert.Equal(t, "label:bug", tokens[0].value)
	assert.Equal(t, "has:assignee", tokens[1].value)
	assert.Equal(t, "no:label", tokens[2].value)
}

func TestTokenize_ParensAdjacentToWords(t *testing.T) {
	tokens := tokenize("(label:bug OR label:feature)")
	require.Len(t, tokens, 5)
	assert.Equal(t, tokLParen, tokens[0].typ)
	assert.Equal(t, "label:bug", tokens[1].value)
	assert.Equal(t, "OR", tokens[2].value)
	assert.Equal(t, "label:feature", tokens[3].value)
	assert.Equal(t, tokRParen, tokens[4].typ)
}

// ---------------------------------------------------------------------------
// Parse: empty / blank input
// ---------------------------------------------------------------------------

func TestParse_EmptyQuery(t *testing.T) {
	n, err := parse("")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	assert.Empty(t, a.children)
}

func TestParse_WhitespaceOnlyQuery(t *testing.T) {
	n, err := parse("   \t  ")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	assert.Empty(t, a.children)
}

// ---------------------------------------------------------------------------
// Parse: single terms
// ---------------------------------------------------------------------------

func TestParse_SingleTextTerm(t *testing.T) {
	n, err := parse("hello")
	require.NoError(t, err)
	txt, ok := n.(*textNode)
	require.True(t, ok)
	assert.Equal(t, "hello", txt.text)
}

func TestParse_MultipleTextTerms(t *testing.T) {
	n, err := parse("hello world")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	require.Len(t, a.children, 2)
	assert.Equal(t, "hello", a.children[0].(*textNode).text)
	assert.Equal(t, "world", a.children[1].(*textNode).text)
}

// ---------------------------------------------------------------------------
// Parse: qualifiers
// ---------------------------------------------------------------------------

func TestParse_QualifierFieldValueParsing(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		field   string
		value   string
		negated bool
	}{
		{"simple qualifier", "label:bug", "label", "bug", false},
		{"assignee qualifier", "assignee:octocat", "assignee", "octocat", false},
		{"has qualifier", "has:label", "has", "label", false},
		{"no qualifier", "no:assignee", "no", "assignee", false},
		{"negated qualifier", "-label:wontfix", "label", "wontfix", true},
		{"negated has", "-has:label", "has", "label", true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			n, err := parse(tc.input)
			require.NoError(t, err)
			q, ok := n.(*qualifierNode)
			require.True(t, ok, "expected qualifierNode, got %T", n)
			assert.Equal(t, tc.field, q.field)
			assert.Equal(t, tc.value, q.value)
			assert.Equal(t, tc.negated, q.negated)
		})
	}
}

func TestParse_FieldNameCaseNormalized(t *testing.T) {
	n, err := parse("Label:Bug")
	require.NoError(t, err)
	q, ok := n.(*qualifierNode)
	require.True(t, ok)
	assert.Equal(t, "label", q.field, "field should be lowercased")
	assert.Equal(t, "Bug", q.value, "value should preserve original case")
}

// ---------------------------------------------------------------------------
// Parse: quoted values
// ---------------------------------------------------------------------------

func TestParse_QuotedValueWithSpaces(t *testing.T) {
	n, err := parse(`label:"good first issue"`)
	require.NoError(t, err)
	q, ok := n.(*qualifierNode)
	require.True(t, ok)
	assert.Equal(t, "label", q.field)
	assert.Equal(t, "good first issue", q.value)
	assert.False(t, q.negated)
}

func TestParse_NegatedQuotedValue(t *testing.T) {
	n, err := parse(`-label:"good first issue"`)
	require.NoError(t, err)
	q, ok := n.(*qualifierNode)
	require.True(t, ok)
	assert.Equal(t, "label", q.field)
	assert.Equal(t, "good first issue", q.value)
	assert.True(t, q.negated)
}

// ---------------------------------------------------------------------------
// Parse: special characters in values
// ---------------------------------------------------------------------------

func TestParse_SpecialCharactersInValue(t *testing.T) {
	tests := []struct {
		name  string
		input string
		value string
	}{
		{"plus signs", "label:c++", "c++"},
		{"hyphens and bangs", "label:1-liner-!!!!", "1-liner-!!!!"},
		{"at sign", "label:@me", "@me"},
		{"slash", "label:area/core", "area/core"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			n, err := parse(tc.input)
			require.NoError(t, err)
			q, ok := n.(*qualifierNode)
			require.True(t, ok, "expected qualifierNode, got %T", n)
			assert.Equal(t, tc.value, q.value)
		})
	}
}

// ---------------------------------------------------------------------------
// Parse: implicit AND (space-separated)
// ---------------------------------------------------------------------------

func TestParse_ImplicitANDQualifiers(t *testing.T) {
	n, err := parse("label:bug has:assignee no:label")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	require.Len(t, a.children, 3)

	q0 := a.children[0].(*qualifierNode)
	assert.Equal(t, "label", q0.field)
	assert.Equal(t, "bug", q0.value)

	q1 := a.children[1].(*qualifierNode)
	assert.Equal(t, "has", q1.field)
	assert.Equal(t, "assignee", q1.value)

	q2 := a.children[2].(*qualifierNode)
	assert.Equal(t, "no", q2.field)
	assert.Equal(t, "label", q2.value)
}

func TestParse_ImplicitANDMixedQualifiersAndText(t *testing.T) {
	n, err := parse("label:bug fix crash")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	require.Len(t, a.children, 3)

	_, isQualifier := a.children[0].(*qualifierNode)
	assert.True(t, isQualifier)

	txt1 := a.children[1].(*textNode)
	assert.Equal(t, "fix", txt1.text)

	txt2 := a.children[2].(*textNode)
	assert.Equal(t, "crash", txt2.text)
}

// ---------------------------------------------------------------------------
// Parse: explicit AND
// ---------------------------------------------------------------------------

func TestParse_ExplicitAND(t *testing.T) {
	n, err := parse("label:bug AND has:assignee")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	require.Len(t, a.children, 2)
	assert.Equal(t, "qualifier", a.children[0].nodeType())
	assert.Equal(t, "qualifier", a.children[1].nodeType())
}

func TestParse_ExplicitANDCaseInsensitive(t *testing.T) {
	n, err := parse("label:bug and has:assignee")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	require.Len(t, a.children, 2)
}

// ---------------------------------------------------------------------------
// Parse: OR
// ---------------------------------------------------------------------------

func TestParse_SimpleOR(t *testing.T) {
	n, err := parse("label:bug OR label:feature")
	require.NoError(t, err)
	o, ok := n.(*orNode)
	require.True(t, ok)
	require.Len(t, o.children, 2)

	q0 := o.children[0].(*qualifierNode)
	assert.Equal(t, "bug", q0.value)

	q1 := o.children[1].(*qualifierNode)
	assert.Equal(t, "feature", q1.value)
}

func TestParse_MultipleOR(t *testing.T) {
	n, err := parse("label:bug OR label:feature OR label:enhancement")
	require.NoError(t, err)
	o, ok := n.(*orNode)
	require.True(t, ok)
	require.Len(t, o.children, 3)
}

func TestParse_ORCaseInsensitive(t *testing.T) {
	n, err := parse("label:bug or label:feature")
	require.NoError(t, err)
	_, ok := n.(*orNode)
	assert.True(t, ok)
}

// ---------------------------------------------------------------------------
// Parse: precedence — AND binds tighter than OR
// ---------------------------------------------------------------------------

func TestParse_ANDBindsTighterThanOR(t *testing.T) {
	// is:issue OR state:open AND label:bug
	// should parse as: is:issue OR (state:open AND label:bug)
	n, err := parse("has:label OR label:bug AND no:assignee")
	require.NoError(t, err)

	o, ok := n.(*orNode)
	require.True(t, ok, "top-level should be orNode")
	require.Len(t, o.children, 2)

	// left branch: single qualifier
	_, isQ := o.children[0].(*qualifierNode)
	assert.True(t, isQ, "left branch should be qualifier")

	// right branch: andNode with two children
	a, isA := o.children[1].(*andNode)
	require.True(t, isA, "right branch should be andNode")
	assert.Len(t, a.children, 2)
}

// ---------------------------------------------------------------------------
// Parse: parentheses
// ---------------------------------------------------------------------------

func TestParse_ParenthesizedOR(t *testing.T) {
	n, err := parse("(label:bug OR label:feature) AND no:assignee")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	require.Len(t, a.children, 2)
	_, isOr := a.children[0].(*orNode)
	assert.True(t, isOr)
}

func TestParse_NestedANDInsideOR(t *testing.T) {
	// is:issue OR (state:open AND label:bug)
	n, err := parse("has:label OR (label:bug AND no:assignee)")
	require.NoError(t, err)
	o, ok := n.(*orNode)
	require.True(t, ok)
	require.Len(t, o.children, 2)

	_, isAnd := o.children[1].(*andNode)
	assert.True(t, isAnd)
}

func TestParse_ParensFlattenRedundantAND(t *testing.T) {
	// (label:bug AND label:feature) → andNode with 2 children, not nested
	n, err := parse("(label:bug AND label:feature)")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	assert.Len(t, a.children, 2)
}

func TestParse_NestedImplicitANDInParens(t *testing.T) {
	n, err := parse("has:label (label:bug label:feature)")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	require.Len(t, a.children, 2)

	inner, isAnd := a.children[1].(*andNode)
	require.True(t, isAnd)
	assert.Len(t, inner.children, 2)
}

// ---------------------------------------------------------------------------
// Parse: complex mixed expressions
// ---------------------------------------------------------------------------

func TestParse_ComplexMixed(t *testing.T) {
	// label:bug AND (has:assignee OR no:label)
	n, err := parse("label:bug AND (has:assignee OR no:label)")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok)
	require.Len(t, a.children, 2)

	q := a.children[0].(*qualifierNode)
	assert.Equal(t, "label", q.field)
	assert.Equal(t, "bug", q.value)

	o := a.children[1].(*orNode)
	require.Len(t, o.children, 2)
}

func TestParse_ORAndANDMixed(t *testing.T) {
	// is:issue OR state:open label:bug  →  is:issue OR (state:open AND label:bug)
	n, err := parse("has:label OR label:bug label:feature")
	require.NoError(t, err)
	o, ok := n.(*orNode)
	require.True(t, ok)
	require.Len(t, o.children, 2)

	_, isAnd := o.children[1].(*andNode)
	assert.True(t, isAnd, "implicit AND should group the right side")
}

// ---------------------------------------------------------------------------
// Parse: error cases
// ---------------------------------------------------------------------------

func TestParse_UnmatchedOpenParen(t *testing.T) {
	_, err := parse("(label:bug")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "expected closing parenthesis")
}

func TestParse_UnmatchedCloseParen(t *testing.T) {
	_, err := parse("label:bug)")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "unexpected token")
}

func TestParse_DoubleOpenParen(t *testing.T) {
	_, err := parse("((label:bug)")
	assert.Error(t, err)
}

func TestParse_EmptyParens(t *testing.T) {
	_, err := parse("()")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "unexpected closing parenthesis")
}

func TestParse_TrailingAND(t *testing.T) {
	_, err := parse("label:bug AND")
	assert.Error(t, err)
}

func TestParse_TrailingOR(t *testing.T) {
	_, err := parse("label:bug OR")
	assert.Error(t, err)
}

func TestParse_LeadingANDKeyword(t *testing.T) {
	// "AND" at the start is treated as a text word, not a keyword
	n, err := parse("AND label:bug")
	require.NoError(t, err)
	a, ok := n.(*andNode)
	require.True(t, ok, "AND followed by qualifier should be implicit AND of text + qualifier")
	require.Len(t, a.children, 2)
	txt := a.children[0].(*textNode)
	assert.Equal(t, "AND", txt.text)
}

// ---------------------------------------------------------------------------
// Parse: qualifier-only (no value after colon)
// ---------------------------------------------------------------------------

func TestParse_ColonOnlyNoValue(t *testing.T) {
	// "label:" with no value — should become a text node (no value after colon)
	n, err := parse("label:")
	require.NoError(t, err)
	_, ok := n.(*textNode)
	assert.True(t, ok, "qualifier with empty value should be treated as text")
}

// ---------------------------------------------------------------------------
// parseWordToken unit tests
// ---------------------------------------------------------------------------

func TestParseWordToken_Qualifier(t *testing.T) {
	n := parseWordToken("label:bug")
	q, ok := n.(*qualifierNode)
	require.True(t, ok)
	assert.Equal(t, "label", q.field)
	assert.Equal(t, "bug", q.value)
	assert.False(t, q.negated)
}

func TestParseWordToken_NegatedQualifier(t *testing.T) {
	n := parseWordToken("-assignee:octocat")
	q, ok := n.(*qualifierNode)
	require.True(t, ok)
	assert.Equal(t, "assignee", q.field)
	assert.Equal(t, "octocat", q.value)
	assert.True(t, q.negated)
}

func TestParseWordToken_QuotedValue(t *testing.T) {
	n := parseWordToken(`label:"good first issue"`)
	q, ok := n.(*qualifierNode)
	require.True(t, ok)
	assert.Equal(t, "good first issue", q.value)
}

func TestParseWordToken_PlainText(t *testing.T) {
	n := parseWordToken("hello")
	txt, ok := n.(*textNode)
	require.True(t, ok)
	assert.Equal(t, "hello", txt.text)
}

func TestParseWordToken_NegatedPlainText(t *testing.T) {
	// "-hello" has no colon → text node with the original word
	n := parseWordToken("-hello")
	txt, ok := n.(*textNode)
	require.True(t, ok)
	assert.Equal(t, "-hello", txt.text)
}

func TestParseWordToken_ColonAtStart(t *testing.T) {
	// ":value" — colon at position 0, not a valid qualifier
	n := parseWordToken(":value")
	txt, ok := n.(*textNode)
	require.True(t, ok)
	assert.Equal(t, ":value", txt.text)
}
