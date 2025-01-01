package types

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestCommitShaType(t *testing.T) {
	t.Run("Test CommitSha IsEqual method", func(t *testing.T) {
		testCases := []struct {
			Left     CommitSha
			Right    CommitSha
			Expected bool
		}{
			{Left: CommitSha(""), Right: CommitSha(""), Expected: true},
			{Left: CommitSha("a1"), Right: CommitSha("A1"), Expected: true},
			{Left: CommitSha("a"), Right: CommitSha("a"), Expected: true},
			{Left: CommitSha("a"), Right: CommitSha(""), Expected: false},
			{Left: CommitSha(""), Right: CommitSha("a"), Expected: false},
		}
		for _, testCase := range testCases {
			assert.Equalf(t, testCase.Expected, testCase.Left.IsEqual(testCase.Right), "Expected CommitSha(%v).IsEqual(%v) to be %v", testCase.Left, testCase.Right, testCase.Expected)
		}
	})
	t.Run("Test CommitSha IsZeroValue method", func(t *testing.T) {
		testCases := []struct {
			ID          CommitSha
			IsZeroValue bool
		}{
			{ID: CommitSha("a"), IsZeroValue: false},
			{ID: CommitSha("0"), IsZeroValue: false},
			{ID: CommitSha(""), IsZeroValue: true},
		}
		for _, testCase := range testCases {
			assert.Equalf(t, testCase.IsZeroValue, testCase.ID.IsZeroValue(), "Expected CommitSha(%v).IsZeroValue() to be %v", testCase.ID, testCase.IsZeroValue)
		}
	})
}
