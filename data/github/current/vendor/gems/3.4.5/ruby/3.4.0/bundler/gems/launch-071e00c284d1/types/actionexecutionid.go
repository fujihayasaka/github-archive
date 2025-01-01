package types

import (
	"database/sql/driver"

	"github.com/google/uuid"
)

// ActionExecutionID is a unique identifier for an action execution, with uniqueness enforced by database.
type ActionExecutionID uuid.UUID

// NilActionExecutionID is all zeroes.
var NilActionExecutionID ActionExecutionID

// NewRandomActionExecutionID generates a new ActionExecutionID.
func NewRandomActionExecutionID() ActionExecutionID {
	u, _ := uuid.NewRandom()
	return ActionExecutionID(u)
}

// Value returns the bytes of the ActionExecutionID, so they can be stored in the database.
func (a ActionExecutionID) Value() (driver.Value, error) {
	return uuid.UUID(a).MarshalBinary()
}

// Scan reads a ActionExecutionID from a byte array, as it's stored in the database.
func (a *ActionExecutionID) Scan(val any) error {
	u := (*uuid.UUID)(a)
	return u.Scan(val)
}

// String renders the ActionExecutionID as a UUID.
func (a ActionExecutionID) String() string {
	return uuid.UUID(a).String()
}

func (a ActionExecutionID) MarshalText() ([]byte, error) {
	return []byte(a.String()), nil
}

func (a *ActionExecutionID) UnmarshalText(text []byte) error {
	u, err := uuid.Parse(string(text))
	if err != nil {
		return err
	}
	*a = ActionExecutionID(u)
	return nil
}
