package types

import (
	"database/sql/driver"
	"regexp"
	"strings"
)

// CommitSha represents the Commit SHA within a Repository
type CommitSha string

var commitShaRegex = regexp.MustCompile(`\b[0-9a-f]{40}\b`)

func IsCommitSha(s string) bool {
	return commitShaRegex.MatchString(s)
}

const CommitShaZeroValue = CommitSha("")
const NullCommitSha = CommitSha("0000000000000000000000000000000000000000")

func (CommitSha) isCommitish() {}

func (c CommitSha) IsZeroValue() bool {
	return c.IsEqual(CommitShaZeroValue)
}

// IsNullSha indicates whether the CommitSha is the null SHA (40x'0')
func (c CommitSha) IsNullSha() bool {
	return c.IsEqual(NullCommitSha)
}

// IsEqual indicates whether the CommitSha is considered equal to another CommitSha
func (c CommitSha) IsEqual(that CommitSha) bool {
	return strings.EqualFold(string(c), string(that))
}

// Value converts the CommitSha to a value suitable for use by the database/sql/driver
func (c CommitSha) Value() (driver.Value, error) {
	return string(c), nil
}

// String returns the string form of the CommitSha.
func (c CommitSha) String() string {
	return string(c)
}
