package types

import (
	"database/sql/driver"

	"github.com/github/go-kvp"
	"github.com/google/uuid"

	"github.com/github/launch/observability/kvperrors"
)

// ScaleUnitID is a generic identifier for storing uuid.UUID as binary(16).
type ScaleUnitID uuid.UUID

// NilScaleUnitID is all zeroes.
var NilScaleUnitID ScaleUnitID

// ParseUUID converts the string form of a uuid.UUID into a ScaleUnitID.
func ParseScaleUnitID(id string) (ScaleUnitID, error) {
	parsed, err := uuid.Parse(id)
	if err != nil {
		return NilScaleUnitID, kvperrors.WrapWith(err, kvp.String("code.function", "UUIDParseError"))
	}
	return ScaleUnitID(parsed), nil
}

// NewRandomScaleUnitID generates a new ScaleUnitID.
func NewRandomScaleUnitID() ScaleUnitID {
	u, _ := uuid.NewRandom()
	return ScaleUnitID(u)
}

// Value returns the bytes of the uuid.UUID, so they can be stored in the database.
func (f ScaleUnitID) Value() (driver.Value, error) {
	if f == NilScaleUnitID {
		return nil, nil
	}
	return uuid.UUID(f).MarshalBinary()
}

// Scan reads a uuid.UUID from a byte array, as it's stored in the database.
func (f *ScaleUnitID) Scan(val any) error {
	u := (*uuid.UUID)(f)
	return u.Scan(val)
}

// String returns the string form of this uuid.UUID.
func (f ScaleUnitID) String() string {
	return uuid.UUID(f).String()
}
