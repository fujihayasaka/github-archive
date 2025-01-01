package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// All tests cases are taken from
// https://github.com/github/launch/blob/1061024891d21b64f81d7ac79985e23121235133/utils/graphqlid/graphqlid_test.go
func TestGraphQLGlobalId(t *testing.T) {
	// Validate NextGlobalIDs
	assertDecodes(t, "Repository", "3", "R_lAHNJr8DAw")
	assertDecodes(t, "User", "29457092", "U_kgDOAcF6xA")
	assertDecodes(t, "Organization", "9919", "O_kgDNJr8")
	assertDecodes(t, "CheckRun", "355561497", "CR_kwADzhUxcBk")
	assertDecodes(t, "CheckSuite", "3722985839", "CS_kwDOFj4Y287d6EFv")
	assertDecodes(t, "Repository", "62", "R_mgA-Pz4_Pj8-Pz4")
	assertDecodes(t, "Bot", "10", "BOT_kgAK")
	assertDecodes(t, "Environment", "10", "EN_kgAK")
	// Enterprise' type should be "Business" (class name in Rails)
	// https://github.com/github/launch/blob/ed4cb201f2a41e072af5aa5e92eca0efad1361ab/types/global_id.go#L102
	assertDecodes(t, "Business", "10", "E_kgAK")
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

func assertDecodes(t *testing.T, expectedType string, expectedID string, encodedID string) {
	actor, err := DotcomActorFromGlobalID(encodedID)
	require.NoError(t, err, "decoding %q", encodedID)
	assert.Equal(t, expectedType, actor.Type(), "type extracted from %q", encodedID)
	assert.Equal(t, expectedID, actor.Id(), "ID extracted from %q", encodedID)
}

func assertDecodeError(t *testing.T, badEncodedID string) {
	_, err := DotcomActorFromGlobalID(badEncodedID)
	assert.Error(t, err)
}
