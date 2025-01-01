package types

import (
	"database/sql/driver"

	"github.com/github/go-kvp"
	"github.com/google/uuid"

	"github.com/github/launch/observability/kvperrors"
)

// WorkflowExecutionID is an identifier for a workflow execution.
type WorkflowExecutionID uuid.UUID

// NilWorkflowExecutionID is all zeroes.
var NilWorkflowExecutionID WorkflowExecutionID

// ParseWorkflowExecutionID converts the string form of a UUID into a WorkflowExecutionID.
func ParseWorkflowExecutionID(id string) (WorkflowExecutionID, error) {
	parsed, err := uuid.Parse(id)
	if err != nil {
		return NilWorkflowExecutionID, kvperrors.WrapWith(err, kvp.String("code.function", "UUIDParseError"))
	}
	return WorkflowExecutionID(parsed), nil
}

// NewRandomWorkflowExecutionID generates a new WorkflowExecutionID.
func NewRandomWorkflowExecutionID() WorkflowExecutionID {
	u, _ := uuid.NewRandom()
	return WorkflowExecutionID(u)
}

// Value returns the bytes of the UUID, so they can be stored in the database.
func (f WorkflowExecutionID) Value() (driver.Value, error) {
	return uuid.UUID(f).MarshalBinary()
}

// Scan reads a UUID from a byte array, as it's stored in the database.
func (f *WorkflowExecutionID) Scan(val any) error {
	u := (*uuid.UUID)(f)
	return u.Scan(val)
}

// String returns the string form of this UUID.
func (f WorkflowExecutionID) String() string {
	return uuid.UUID(f).String()
}
