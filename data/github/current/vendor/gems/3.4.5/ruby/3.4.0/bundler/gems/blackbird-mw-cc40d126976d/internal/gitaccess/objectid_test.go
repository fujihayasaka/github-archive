package gitaccess

import (
	"testing"

	"github.com/stretchr/testify/require"
)

const sha = "804ce3ea1b0aa65de79897f738d146f26dfb6f66"

var shaBytes = []byte{0x80, 0x4c, 0xe3, 0xea, 0x1b, 0xa, 0xa6, 0x5d, 0xe7, 0x98, 0x97, 0xf7, 0x38, 0xd1, 0x46, 0xf2, 0x6d, 0xfb, 0x6f, 0x66}

func Test_OIDFromSHA(t *testing.T) {
	oid, err := NewObjectIDFromSHA(sha)
	require.NoError(t, err)
	require.Equal(t, shaBytes, oid.Bytes())
	require.Equal(t, sha, oid.String())
}

func Test_OIDFromSHAWrongStringLength(t *testing.T) {
	sha := sha[:len(sha)-1]
	oid, err := NewObjectIDFromSHA(sha)
	require.EqualError(t, err, "expected 40 char hexadecimal string but got only 39 chars")
	require.Equal(t, NullObjectID, oid)
}

func Test_OIDFromInvalidSHA(t *testing.T) {
	oid, err := NewObjectIDFromSHA("$04ce3ea1b0aa65de79897f738d146f26dfb6f66")
	require.EqualError(t, err, "not a valid sha")
	require.Equal(t, NullObjectID, oid)
}

func Test_NullOIDIsNull(t *testing.T) {
	require.True(t, NullObjectID.IsNull())

	oid := NewObjectIDFromBytes(make([]byte, 20))
	require.True(t, oid.IsNull())

	// zero value is null
	oid = ObjectID{}
	require.True(t, oid.IsNull())
}

func Test_IsEmptyBlobOID(t *testing.T) {
	oid, err := NewObjectIDFromSHA(sha)
	require.NoError(t, err)
	require.False(t, oid.IsEmptyBlob())

	oid, err = NewObjectIDFromSHA("e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")
	require.NoError(t, err)
	require.True(t, oid.IsEmptyBlob())
}

func Test_OIDFromBytes(t *testing.T) {
	oid := NewObjectIDFromBytes(shaBytes)
	require.Equal(t, sha, oid.String())
	require.Equal(t, shaBytes, oid.Bytes())
}

func Test_OIDFromBytesWrongLen(t *testing.T) {
	require.PanicsWithValue(t, "invalid object id, expected 20 bytes but got 19", func() {
		NewObjectIDFromBytes([]byte{0x80, 0x4c, 0xe3, 0xea, 0x1b, 0xa, 0xa6, 0x5d, 0xe7, 0x98, 0x97, 0xf7, 0x38, 0xd1, 0x46, 0xf2, 0x6d, 0xfb, 0x6f})
	})
}

// If this compiles, it works.
func Test_ObjectIDCanBeKey(t *testing.T) {
	m := map[ObjectID]bool{}
	m[NullObjectID] = true
	require.True(t, m[NullObjectID])
}

func Test_ObjectIDsAreComparable(t *testing.T) {
	oid1, err := NewObjectIDFromSHA("62cda453ad56db8d6903f6cf5541353d80ee9505")
	require.NoError(t, err)
	oid2, err := NewObjectIDFromSHA("62cda453ad56db8d6903f6cf5541353d80ee9505")
	require.NoError(t, err)
	require.True(t, oid1 == oid2, "oids should be directly comparable")
}

func Test_Equal(t *testing.T) {
	oid1, err := NewObjectIDFromSHA("62cda453ad56db8d6903f6cf5541353d80ee9505")
	require.NoError(t, err)
	oid2, err := NewObjectIDFromSHA("62cda453ad56db8d6903f6cf5541353d80ee9505")
	require.NoError(t, err)
	require.Equal(t, oid1, oid2)
}

func Test_TrailingZeros(t *testing.T) {
	oid, err := NewObjectIDFromSHA("62cda453ad56db8d6903f6cf5541353d80ee9505")
	require.NoError(t, err)
	require.Equal(t, 0, oid.TrailingZeros())
	oid, err = NewObjectIDFromSHA("62cda453ad56db8d6903f6cf5541353d80ee9550")
	require.NoError(t, err)
	require.Equal(t, 4, oid.TrailingZeros())
}
