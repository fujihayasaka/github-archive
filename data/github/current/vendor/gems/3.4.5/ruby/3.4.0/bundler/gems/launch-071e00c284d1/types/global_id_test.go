package types

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/utils/testutils"
)

func Test_GlobalIDType(t *testing.T) {
	ctx := context.WithValue(context.Background(), reqmeta.RMDContextKey, reqmeta.NewRequestMetadata())
	t.Run("Test GlobalID IsEquivalent method", func(t *testing.T) {
		testCases := []struct {
			Left     GlobalID
			Right    GlobalID
			Expected bool
		}{
			// Same ID, same format
			{Left: NewGlobalID(ctx, "MDQ6VXNlcjkwOTE0"), Right: NewGlobalID(ctx, "MDQ6VXNlcjkwOTE0"), Expected: true},
			{Left: NewGlobalID(ctx, "U_kgDOAAFjIg"), Right: NewGlobalID(ctx, "U_kgDOAAFjIg"), Expected: true},
			// Same ID, different format
			{Left: NewGlobalID(ctx, "U_kgDOAAFjIg"), Right: NewGlobalID(ctx, "MDQ6VXNlcjkwOTE0"), Expected: true},
			// One ID which is improperly formatted
			{Left: NewGlobalID(ctx, "U_kgDOAAFjIg"), Right: NewGlobalID(ctx, "U_fakeid"), Expected: false},
			// Different DB ID, same type
			{Left: NewGlobalID(ctx, "U_kgDOAAFjIg"), Right: NewGlobalID(ctx, "U_kgDOAMi3vg"), Expected: false},
			// Same DB ID, different type
			{Left: NewGlobalID(ctx, "U_kgDOAAFjIg"), Right: NewGlobalID(ctx, "O_kgDOAAFjIg"), Expected: false},
		}
		for _, testCase := range testCases {
			assert.Equal(t, testCase.Expected, testCase.Left.IsEquivalent(testCase.Right), "Expected NewGlobalID(%v).IsEquivalent(%v) to be %v", testCase.Left, testCase.Right, testCase.Expected)
		}
	})
	t.Run("Test GlobalID IsZeroValue method", func(t *testing.T) {
		testCases := []struct {
			ID       GlobalID
			Expected bool
		}{
			{ID: NewGlobalID(ctx, "a"), Expected: false},
			{ID: NewGlobalID(ctx, "0"), Expected: false},
			{ID: NewGlobalID(ctx, ""), Expected: true},
		}
		for _, testCase := range testCases {
			assert.Equalf(t, testCase.Expected, testCase.ID.IsZeroValue(), "Expected NewGlobalID(%v).IsZeroValue() to be %v", testCase.ID, testCase.Expected)
		}
	})
}

func Test_GlobalID_MarshalJSON(t *testing.T) {
	testCases := []struct {
		val  GlobalID
		json string
	}{
		{NilGlobalID, `{"Val":""}`},
		{GlobalID("U_kgDOAAFjIg"), `{"Val":"U_kgDOAAFjIg"}`},
		{GlobalID("MDQ6VXNlcjkwOTE0"), `{"Val":"MDQ6VXNlcjkwOTE0"}`},
		{GlobalID("InvalidValue"), `{"Val":"InvalidValue"}`},
	}

	for _, tc := range testCases {
		t.Run(tc.val.String(), func(t *testing.T) {
			data := struct {
				Val GlobalID
			}{tc.val}

			jsonBytes, err := json.Marshal(data)
			require.NoError(t, err)
			assert.Equal(t, tc.json, string(jsonBytes), "JSON form of %#v", data)
		})
	}
}

func Test_GlobalID_UnmarshalJSON(t *testing.T) {
	testCases := []struct {
		json string
		val  GlobalID
	}{
		{`{"Val":"U_kgDOAAFjIg"}`, GlobalID("U_kgDOAAFjIg")},
		{`{"Val":"MDQ6VXNlcjkwOTE0"}`, GlobalID("MDQ6VXNlcjkwOTE0")},
		{`{"Val":""}`, NilGlobalID},
		{`{"Val":null}`, NilGlobalID},
		{`{}`, NilGlobalID},
	}

	for _, tc := range testCases {
		t.Run(tc.val.String(), func(t *testing.T) {
			var data struct {
				Val GlobalID
			}

			err := json.Unmarshal([]byte(tc.json), &data)
			require.NoError(t, err)
			assert.Equal(t, tc.val, data.Val, "Val, as decoded from %q", string(tc.json))
		})
	}
}

func TestGlobalID_ScanFromNull(t *testing.T) {
	var id GlobalID
	err := id.Scan(nil)
	require.NoError(t, err)
	assert.Equal(t, NilGlobalID, id)
}

func TestGlobalID_Scan(t *testing.T) {
	var id GlobalID
	err := id.Scan("abc")
	require.NoError(t, err)
	assert.Equal(t, "abc", id.String())
}

func Test_IsNextGlobalID(t *testing.T) {
	ctx := context.WithValue(context.Background(), reqmeta.RMDContextKey, reqmeta.NewRequestMetadata())
	legacyID := NewGlobalID(ctx, "MDExOlR5cGVPZlRoaW5nYWJjZGVm")
	nextID := NewGlobalID(ctx, "R_lAHNJr8DAw")
	assert.False(t, legacyID.IsNextGlobalID())
	assert.True(t, nextID.IsNextGlobalID())
}

func TestGlobalID_ToFeaturesActorID(t *testing.T) {
	ctx := context.WithValue(context.Background(), reqmeta.RMDContextKey, reqmeta.NewRequestMetadata())
	testCases := []struct {
		Input    GlobalID
		Expected string
	}{
		{Input: NewGlobalID(ctx, testutils.EncodeGlobalID("User", 1123)), Expected: "User:1123"},
		{Input: NewGlobalID(ctx, testutils.EncodeGlobalID("Organization", 1123)), Expected: "Organization:1123"},
		{Input: NewGlobalID(ctx, testutils.EncodeGlobalID("Foo", 1123)), Expected: "Foo:1123"},
		{Input: NewGlobalID(ctx, testutils.EncodeGlobalID("Enterprise", 1123)), Expected: "Business:1123"},
	}
	for _, testCase := range testCases {
		output, err := testCase.Input.ToFeaturesActorID()
		assert.Nil(t, err)
		assert.Equal(t, testCase.Expected, output)
	}
}

func Test_GlobalID_checkFormat(t *testing.T) {
	testCases := []struct {
		name            string
		usingNextFormat bool
		globalID        string
		errorContains   string
	}{
		{
			name:            "empty global id on enterprise is ok",
			usingNextFormat: false,
			globalID:        "",
		},
		{
			name:            "empty global id on hosted is ok",
			usingNextFormat: true,
			globalID:        "",
		},
		{
			name:            "legacy global id is okay on enterprise",
			usingNextFormat: false,
			globalID:        "MDQ6VXNlcjE1Ng==",
		},
		{
			name:            "legacy global id returns an error on hosted",
			usingNextFormat: true,
			globalID:        "MDQ6VXNlcjE1Ng==",
			errorContains:   "legacy global id format used",
		},
		{
			name:            "next global id is okay on hosted",
			usingNextFormat: true,
			globalID:        "U_kgAB",
		},
		{
			name:            "next global id returns an error on enterprise",
			usingNextFormat: false,
			globalID:        "U_kgAB",
			errorContains:   "next global id format used",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			gid := GlobalID(tc.globalID)
			err := gid.checkFormat(tc.usingNextFormat)
			if tc.errorContains != "" {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tc.errorContains)
			} else {
				require.NoError(t, err)
			}
		})
	}
}
