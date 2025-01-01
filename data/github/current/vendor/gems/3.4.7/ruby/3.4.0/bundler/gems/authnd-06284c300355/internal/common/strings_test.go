package common

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestTruncateStringUnderMaxChars(t *testing.T) {
	maxChars := 100
	str := "123456789" // under maxChars
	expectedResult := str
	result := TruncateString(str, maxChars)
	require.Equal(t, expectedResult, result)
}

func TestTruncateStringEqualMaxChars(t *testing.T) {
	maxChars := 9
	str := "123456789" // equals maxChars
	expectedResult := str
	result := TruncateString(str, maxChars)
	require.Equal(t, expectedResult, result)
}

func TestTruncateStringOverMaxChars(t *testing.T) {
	maxChars := 7
	str := "123456789123456789" // 18 chars
	expectedResult := "1...789"
	result := TruncateString(str, maxChars)
	require.Equal(t, expectedResult, result)

	maxChars = 9
	str = "123456789123456789" // 18 chars
	expectedResult = "123...789"
	result = TruncateString(str, maxChars)
	require.Equal(t, expectedResult, result)
}

// if max chars is <=6, truncate doesn't apply the trailing info
func TestTruncateStringOverSmallMaxChars(t *testing.T) {
	maxChars := 6
	str := "123456789" // over maxChars
	expectedResult := "123456"
	result := TruncateString(str, maxChars)
	require.Equal(t, expectedResult, result)
}

func TestTruncateStringCloseToMaxChars(t *testing.T) {
	maxChars := 8
	str := "123456789" // maxChars is one char short of the string length
	expectedResult := "12...789"
	result := TruncateString(str, maxChars)
	require.Equal(t, expectedResult, result)
}

func TestTruncateStringLowValues(t *testing.T) {
	maxChars := 1
	str := "12"
	expectedResult := "1"
	result := TruncateString(str, maxChars)
	require.Equal(t, expectedResult, result)
}

func TestTruncateStringOneChar(t *testing.T) {
	maxChars := 1
	str := "1"
	expectedResult := "1"
	result := TruncateString(str, maxChars)
	require.Equal(t, expectedResult, result)
}

// we use TruncateString to print info related to a generated
// "WHERE id in" clause. This test is mainly to provide an
// example / coverage for a string that we'd expect in this case
func TestTruncateStringWhereClauseExample(t *testing.T) {
	whereClause := "id in (1, 2, 3, 4, 5, 6)" // over 20 characters
	expectedResult := "id in (1, 2, 3... 6)"
	result := TruncateString(whereClause, 20)
	require.Equal(t, expectedResult, result)
}

func TestInt64sToString(t *testing.T) {
	expectedResult := "1, 2, 3"
	result := Int64sToString([]int64{1, 2, 3}, ", ")
	require.Equal(t, expectedResult, result)
}

func TestInt64sToStringSingleItem(t *testing.T) {
	expectedResult := "1"
	result := Int64sToString([]int64{1}, "doesntmatter")
	require.Equal(t, expectedResult, result)
}

func TestInt64sToStringNoDelimiter(t *testing.T) {
	expectedResult := "12345"
	result := Int64sToString([]int64{1, 2, 3, 4, 5}, "")
	require.Equal(t, expectedResult, result)
}
