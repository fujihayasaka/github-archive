package graphqlid

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/utils/testutils"
)

func TestGraphQLGlobalID(t *testing.T) {
	// irb(main):001:0> Platform::Helpers::NodeIdentification.to_global_id("TypeOfThing", "abcdef")
	// => "MDExOlR5cGVPZlRoaW5nYWJjZGVm"
	assertEncodesAndDecodes(t, "TypeOfThing", "abcdef", "MDExOlR5cGVPZlRoaW5nYWJjZGVm")

	// irb(main):002:0> Platform::Helpers::NodeIdentification.to_global_id("TypeOfThing", "1")
	// => "MDExOlR5cGVPZlRoaW5nMQ=="
	assertEncodesAndDecodes(t, "TypeOfThing", "1", "MDExOlR5cGVPZlRoaW5nMQ==")

	// irb(main):003:0> Platform::Helpers::NodeIdentification.to_global_id("TypeOfThing", "really-long-id-that-should-make-the-base-64-string-wrap-if-it-is-configured-to-do-so")
	// => "MDExOlR5cGVPZlRoaW5ncmVhbGx5LWxvbmctaWQtdGhhdC1zaG91bGQtbWFrZS10aGUtYmFzZS02NC1zdHJpbmctd3JhcC1pZi1pdC1pcy1jb25maWd1cmVkLXRvLWRvLXNv"
	assertEncodesAndDecodes(t, "TypeOfThing", "really-long-id-that-should-make-the-base-64-string-wrap-if-it-is-configured-to-do-so", "MDExOlR5cGVPZlRoaW5ncmVhbGx5LWxvbmctaWQtdGhhdC1zaG91bGQtbWFrZS10aGUtYmFzZS02NC1zdHJpbmctd3JhcC1pZi1pdC1pcy1jb25maWd1cmVkLXRvLWRvLXNv")

	// Validate NextGlobalIDs
	assertDecodes(t, "Repository", "3", "R_lAHNJr8DAw")
	assertDecodes(t, "User", "29457092", "U_kgDOAcF6xA")
	assertDecodes(t, "Organization", "9919", "O_kgDNJr8")
	assertDecodes(t, "CheckRun", "355561497", "CR_kwADzhUxcBk")
	assertDecodes(t, "CheckSuite", "3722985839", "CS_kwDOFj4Y287d6EFv")
	assertDecodes(t, "Repository", "62", "R_mgA-Pz4_Pj8-Pz4")
	assertDecodes(t, "Bot", "10", "BOT_kgAK")
	assertDecodes(t, "Environment", "10", "EN_kgAK")
	assertDecodes(t, "Enterprise", "10", "E_kgAK")
	assertDecodes(t, "Mannequin", "92404385", "M_kgDOBYH6oQ")
	assertDecodes(t, "App", "15368", "A_kwHNJr_NPAg")
	assertDecodes(t, "Gate", "173", "GA_kwDOC8UXKcyt")

	enc := func(s string) string {
		return encoding.EncodeToString([]byte(s))
	}
	assertDecodeError(t, enc("011:notenough"))
	assertDecodeError(t, enc("011:"))
	assertDecodeError(t, enc("waaaaat"))
	assertDecodeError(t, "not even close to base64 :(")
	assertDecodeError(t, "")
	assertDecodeError(t, "R_")
	assertDecodeError(t, "R_notareadglob&&&al-()id")
	assertDecodeError(t, "R_kQA=")
	assertDecodeError(t, "INVALIDPREFIX_kQA=")
	assertDecodeError(t, "R_lAHNJr8DAw==")
	assertDecodeError(t, "R_lAHNJr8DAw=")
}

func assertEncodesAndDecodes(t *testing.T, typeName, id, encoded string) {
	assert.Equal(t, encoded, testutils.EncodeGlobalIDString(typeName, id), "encoding of %q with ID %q", typeName, id)
	assertDecodes(t, typeName, id, encoded)
}

func Test_DecodeInt64ID(t *testing.T) {
	intID := testutils.EncodeGlobalID("Foo", 12)
	id, err := DecodeInt64ID(intID)
	require.NoError(t, err)
	assert.Equal(t, int64(12), id)

	strID := testutils.EncodeGlobalIDString("Foo", "snail")
	_, err = DecodeInt64ID(strID)
	assert.EqualError(t, err, "Relay ID id part `snail' was not an int")
}

func assertDecodes(t *testing.T, expectedType string, expectedID string, encodedID string) {
	actualType, actualID, err := Decode(encodedID)
	require.NoError(t, err, "decoding %q", encodedID)
	assert.Equal(t, expectedType, actualType, "type extracted from %q", encodedID)
	assert.Equal(t, expectedID, actualID, "ID extracted from %q", encodedID)
}

func assertDecodeError(t *testing.T, badEncodedID string) {
	_, _, err := Decode(badEncodedID)
	assert.Error(t, err)
	assertClassNameForNeedle(t, err)
}

// Make sure that the needle's "graphql.operation.name" field will be filled in, which helps haystack generate good rollup IDs.
// TODO - move this someplace more generic than the graphqlid package, and use it in more places where we wrap/generate errors.
func assertClassNameForNeedle(t *testing.T, err error) {
	if !assert.NotNil(t, err) {
		return
	}

	k := kvperrors.Context(err)
	if !assert.NotNil(t, k, "expect KVP to be attached to error %q", err) {
		return
	}

	f := k.Field("graphql.operation.name")
	if !assert.NotNil(t, f, "expect KVP to include 'graphql.operation.name' field on error %q", err) {
		return
	}

	assert.NotEmpty(t, f.String(), "expect KVP 'graphql.operation.name' to have a value on error %q", err)
}
