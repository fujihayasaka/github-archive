package codediff

import "strings"

type Tokenizer interface {
	Tokens() []string
	TokensLen() int
}

func splitLines(text string) []string {
	lines := strings.SplitAfter(text, "\n")
	if lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	return lines
}

type simple struct {
	tokens []string
}

func (l simple) Tokens() []string {
	return l.tokens
}
func (l simple) TokensLen() int {
	return len(l.tokens)
}
func (l simple) LexTokenizer() Tokenizer {
	var t simple

	for _, a := range l.tokens {
		t.tokens = append(t.tokens, LexTokenize(a).Tokens()...)
	}
	return t
}

func LexTokenize(s string) Tokenizer {
	t := strings.Fields(s)
	return simple{t}
}
