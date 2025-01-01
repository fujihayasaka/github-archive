package types

import (
	"database/sql/driver"
)

// CommitMessage represents the message of a Commit within a Repository
type CommitMessage string

// CommitMessageZeroValue is the zero value for CommitMessage.
const CommitMessageZeroValue CommitMessage = ""

// IsZeroValue returns whether this value is the zero value for this type.
func (c CommitMessage) IsZeroValue() bool {
	return c.IsEqual(CommitMessageZeroValue)
}

// IsEqual indicates whether the CommitMessage is considered equal to another CommitMessage
func (c CommitMessage) IsEqual(that CommitMessage) bool {
	return c == that
}

// Value converts the CommitMessage to a value suitable for use by the database/sql/driver
func (c CommitMessage) Value() (driver.Value, error) {
	return string(c), nil
}

// String returns the string form of the CommitMessage.
func (c CommitMessage) String() string {
	return string(c)
}
