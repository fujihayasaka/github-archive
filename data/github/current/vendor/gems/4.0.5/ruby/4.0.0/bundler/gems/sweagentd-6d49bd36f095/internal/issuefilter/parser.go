package issuefilter

import (
	"strings"

	"github.com/github/sweagentd/internal/goerrors"
)

// AST node types for the parsed query.
type node interface {
	nodeType() string
}

type andNode struct {
	children []node
}

func (n *andNode) nodeType() string { return "and" }

type orNode struct {
	children []node
}

func (n *orNode) nodeType() string { return "or" }

type qualifierNode struct {
	field   string
	value   string
	negated bool
}

func (n *qualifierNode) nodeType() string { return "qualifier" }

type textNode struct {
	text string
}

func (n *textNode) nodeType() string { return "text" }

// parse parses a GitHub-style search query into an AST.
//
// Grammar (simplified):
//
//	orExpr    = andExpr ("OR" andExpr)*
//	andExpr   = atom (("AND" | implicit) atom)*
//	atom      = "(" expr ")" | qualifier | text
//	qualifier = ["-"] field ":" value
//	text      = word (free-text, ignored in evaluation)
func parse(query string) (node, error) {
	tokens := tokenize(query)
	if len(tokens) == 0 {
		return &andNode{}, nil
	}
	p := &parser{tokens: tokens}
	n, err := p.parseOrExpr()
	if err != nil {
		return nil, err
	}
	if p.pos < len(p.tokens) {
		return nil, goerrors.Errorf("unexpected token: %q (type %s)", p.tokens[p.pos].value, p.tokens[p.pos].typ)
	}
	return n, nil
}

// token types
const (
	tokWord   = "word"
	tokLParen = "("
	tokRParen = ")"
)

type token struct {
	typ   string
	value string
}

// tokenize splits a query string into tokens.
// Handles quoted strings, parentheses, and qualifier:value pairs.
func tokenize(query string) []token {
	var tokens []token
	r := []rune(query)
	i := 0

	for i < len(r) {
		// skip whitespace
		if r[i] == ' ' || r[i] == '\t' || r[i] == '\n' {
			i++
			continue
		}

		// parentheses
		if r[i] == '(' {
			tokens = append(tokens, token{typ: tokLParen, value: "("})
			i++
			continue
		}
		if r[i] == ')' {
			tokens = append(tokens, token{typ: tokRParen, value: ")"})
			i++
			continue
		}

		// read a word (possibly containing : for qualifiers, or quoted values)
		start := i
		for i < len(r) && r[i] != ' ' && r[i] != '\t' && r[i] != '\n' && r[i] != '(' && r[i] != ')' {
			if r[i] == '"' {
				// consume quoted string
				i++
				for i < len(r) && r[i] != '"' {
					i++
				}
				if i < len(r) {
					i++ // consume closing quote
				}
			} else {
				i++
			}
		}
		word := string(r[start:i])
		if word != "" {
			tokens = append(tokens, token{typ: tokWord, value: word})
		}
	}

	return tokens
}

type parser struct {
	tokens []token
	pos    int
}

func (p *parser) peek() *token {
	if p.pos >= len(p.tokens) {
		return nil
	}
	return &p.tokens[p.pos]
}

func (p *parser) advance() token {
	t := p.tokens[p.pos]
	p.pos++
	return t
}

// parseOrExpr parses: andExpr ("OR" andExpr)*
func (p *parser) parseOrExpr() (node, error) {
	left, err := p.parseAndExpr()
	if err != nil {
		return nil, err
	}

	var children []node
	children = append(children, left)
	isOr := false

	for {
		t := p.peek()
		if t == nil {
			break
		}
		if t.typ != tokWord || !strings.EqualFold(t.value, "OR") {
			break
		}
		isOr = true
		p.advance() // consume OR
		right, err := p.parseAndExpr()
		if err != nil {
			return nil, err
		}
		children = append(children, right)
	}

	if isOr {
		return &orNode{children: children}, nil
	}
	return left, nil
}

// parseAndExpr parses: atom (("AND" | implicit) atom)*
func (p *parser) parseAndExpr() (node, error) {
	left, err := p.parseAtom()
	if err != nil {
		return nil, err
	}

	var children []node
	children = append(children, left)
	isAnd := false

	for {
		t := p.peek()
		if t == nil {
			break
		}
		// explicit AND
		if t.typ == tokWord && strings.EqualFold(t.value, "AND") {
			isAnd = true
			p.advance() // consume AND
			right, err := p.parseAtom()
			if err != nil {
				return nil, err
			}
			children = append(children, right)
			continue
		}
		// stop on OR (lower precedence) or close paren
		if t.typ == tokWord && strings.EqualFold(t.value, "OR") {
			break
		}
		if t.typ == tokRParen {
			break
		}
		// implicit AND between atoms
		isAnd = true
		right, err := p.parseAtom()
		if err != nil {
			return nil, err
		}
		children = append(children, right)
	}

	if isAnd {
		return &andNode{children: children}, nil
	}
	return left, nil
}

// parseAtom parses: "(" orExpr ")" | qualifier | text
func (p *parser) parseAtom() (node, error) {
	t := p.peek()
	if t == nil {
		return nil, goerrors.New("unexpected end of query")
	}

	// parenthesized expression
	if t.typ == tokLParen {
		p.advance() // consume (
		inner, err := p.parseOrExpr()
		if err != nil {
			return nil, err
		}
		closing := p.peek()
		if closing == nil || closing.typ != tokRParen {
			return nil, goerrors.New("expected closing parenthesis")
		}
		p.advance() // consume )
		return inner, nil
	}

	if t.typ == tokRParen {
		return nil, goerrors.New("unexpected closing parenthesis")
	}

	// word token — could be qualifier or free-text
	tok := p.advance()
	return parseWordToken(tok.value), nil
}

// parseWordToken converts a word token into a qualifier node or text node.
// Examples:
//
//	"label:bug"     → qualifierNode{field:"label", value:"bug"}
//	"-label:bug"    → qualifierNode{field:"label", value:"bug", negated:true}
//	"hello"         → textNode{text:"hello"}
//	"label:\"good first issue\"" → qualifierNode{field:"label", value:"good first issue"}
func parseWordToken(word string) node {
	negated := false
	w := word
	if strings.HasPrefix(w, "-") {
		negated = true
		w = w[1:]
	}

	// Check for qualifier pattern: field:value
	idx := strings.Index(w, ":")
	if idx > 0 && idx < len(w)-1 {
		field := strings.ToLower(w[:idx])
		value := w[idx+1:]
		// Strip quotes from value
		value = strings.Trim(value, "\"")
		return &qualifierNode{field: field, value: value, negated: negated}
	}

	return &textNode{text: word}
}
