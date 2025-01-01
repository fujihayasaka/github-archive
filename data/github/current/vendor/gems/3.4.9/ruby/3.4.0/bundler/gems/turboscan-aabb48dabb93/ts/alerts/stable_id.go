package alerts

import (
	"crypto/sha1" // nolint:gosec // G505 we need this to create a stable id
	"database/sql/driver"
	"encoding/binary"

	"github.com/github/turboscan/ts"
)

// StableAlertIdentifier is a 21-length byte array.
// It is a sha1 hash of a few different components(See NewStableID function)
// And a last byte counter for duplicated alerts.
type StableAlertIdentifier [21]byte

var _ driver.Valuer = (*StableAlertIdentifier)(nil)

func (sid StableAlertIdentifier) Value() (driver.Value, error) {
	return sid[:], nil
}

// NewStableID returns a new stable ID
func NewStableID(repoID ts.RepositoryEID, sarifIdentifier string, location Location) (stableID StableAlertIdentifier) {
	// SHA1(project, rule, filepath, location (location hash, column, length))
	del := []byte{0}
	h := sha1.New() // nolint:gosec // G401 this does not have to be cryptographically secure
	h.Write(repoID.ToBytes())
	h.Write(del)
	h.Write([]byte(sarifIdentifier))
	h.Write(del)
	h.Write([]byte(location.FilePath))
	h.Write(del)
	h.Write([]byte(location.Fingerprint))
	h.Write(del)
	h.Write(uint32ToBytes(location.Column()))
	h.Write(del)
	h.Write(uint32ToBytes(location.Length()))

	copy(stableID[:], h.Sum(nil)[:20])
	return
}

func (sid StableAlertIdentifier) PutIndex(i uint8) StableAlertIdentifier {
	sid[20] = i
	return sid
}

// FromBytes cast a byte slice into a StableAlertIdentifier
func FromBytes(slice []byte) (id StableAlertIdentifier) {
	copy(id[:], slice[:21])
	return
}

// uint32ToBytes converts an unsigned 32bit int into a 4-length byte slice
func uint32ToBytes(x uint32) []byte {
	a := make([]byte, 4)
	binary.BigEndian.PutUint32(a, x)
	return a
}
