package gitaccess

import (
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"math/bits"

	"regexp"

	"github.com/pkg/errors"
)

// ObjectID holds a Git object ID. Internally, the data is stored as bytes for
// the most compact representation. This matches our database OID columns and
// the format Blackbird sends/receives.
type ObjectID struct {
	// NOTE: data is an array, not a slice, to enable using ObjectID as keys
	// in a map. Valid OIDs are always 20 bytes long.
	data [20]byte
}

// NullObjectID is the empty object id.
var NullObjectID = ObjectID{[20]byte{}}

// EmptyBlobOID is the OID for an empty git blob.
var EmptyBlobOID = ObjectID{[20]byte{230, 157, 226, 155, 178, 209, 214, 67, 75, 139, 41, 174, 119, 90, 216, 194, 228, 140, 83, 145}}

func NewObjectIDFromSHA(sha string) (ObjectID, error) {
	if len(sha) != 40 {
		return NullObjectID, errors.Errorf("expected 40 char hexadecimal string but got only %d chars", len(sha))
	}

	if !validObjectID.MatchString(sha) {
		return NullObjectID, errors.New("not a valid sha")
	}

	data, err := hex.DecodeString(sha)
	if err != nil {
		return NullObjectID, errors.Wrap(err, "failed to decode")
	}

	return ObjectID{data: *(*[20]byte)(data)}, nil
}

func NewObjectIDFromBytes(data []byte) ObjectID {
	if len(data) != 20 {
		panic(fmt.Sprintf("invalid object id, expected 20 bytes but got %d", len(data)))
	}

	return ObjectID{data: *(*[20]byte)(data)}
}

func (o ObjectID) String() string {
	return fmt.Sprintf("%x", o.data)
}

// TrailingZeros returns the number of trailing zero bits in the last u64 of the
// byte array representation of the OID.
func (o ObjectID) TrailingZeros() int {
	return bits.TrailingZeros64(binary.BigEndian.Uint64(o.data[12:20]))
}

func (o ObjectID) Bytes() []byte {
	return o.data[:]
}

func (o ObjectID) IsNull() bool {
	return o == NullObjectID
}

func (o ObjectID) Equal(other ObjectID) bool {
	return o == other
}

// IsEmptyBlob returns true if the OID is the same as the Git hash for the empty blob.
// See: https://blog.waleedkhan.name/e69de29bb2d1d6434b8b29ae775ad8c2e48c5391/
func (o ObjectID) IsEmptyBlob() bool {
	return o == EmptyBlobOID
}

var validObjectID = regexp.MustCompile(`^[a-f0-9]{40}$`)
