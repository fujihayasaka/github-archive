package codediff

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNeedleman(t *testing.T) {
	haystackTokens := LexTokenize("A B C D E F G H I J K L M N O P Q R S T U V W X Y Z")

	score := NeedlemanWunsch(LexTokenize("A"), haystackTokens)
	require.Equal(t, 0, score)
	score = NeedlemanWunsch(LexTokenize("F G"), haystackTokens)
	require.Equal(t, 0, score)
	score = NeedlemanWunsch(LexTokenize(""), haystackTokens)
	require.Equal(t, 0, score)

	score = NeedlemanWunsch(LexTokenize("Y Z x"), haystackTokens)
	require.Equal(t, 1, score)

	score = NeedlemanWunsch(LexTokenize("A J Z"), haystackTokens)
	require.Equal(t, 2, score)
	score = NeedlemanWunsch(LexTokenize("A F C Z"), haystackTokens)
	require.Equal(t, 2, score)

	score = NeedlemanWunsch(LexTokenize("ABA BBB AAA"), haystackTokens)
	require.Equal(t, 3, score)
	score = NeedlemanWunsch(LexTokenize("ABC DEF ZZ"), haystackTokens)
	require.Equal(t, 3, score)

	a := []string{"import", "{", "foo,", "baz,", "bar", "}", "from", "'bar';", "foo(\"hello\");"}
	b := []string{"import", "{", "foo,", "baz", "}", "from", "'bar';"}
	score = NeedlemanWunsch(simple{b}, simple{a})
	require.Equal(t, 2, score)

	score = NeedlemanWunsch(LexTokenize("G A T T A C A"), LexTokenize(" G C A T G C A"))
	require.Equal(t, 3, score)

	score = NeedlemanWunsch(LexTokenize("foo bar"), LexTokenize(""))
	require.Equal(t, 2, score)

	score = NeedlemanWunsch(LexTokenize(""), LexTokenize("zoo bar"))
	require.Equal(t, 0, score)
}
