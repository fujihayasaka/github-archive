package models

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLicenseeUnmarshalJSON(t *testing.T) {
	jsonWithIDAsString := []byte(`{"type":"` + LicenseeTypeUser.String() + `","id":"1","globalId":"gid://git-hub/User/1"}`)

	var unmarshalled Licensee
	err := json.Unmarshal(jsonWithIDAsString, &unmarshalled)

	require.NoError(t, err)
	assert.Equal(t, "1", unmarshalled.ID)
}

func TestLicenseeUnmarshalJSONWithIDAsNumber(t *testing.T) {
	jsonWithIDAsString := []byte(`{"type":"` + LicenseeTypeUser.String() + `","id":1,"globalId":"gid://git-hub/User/1"}`)

	var unmarshalled Licensee
	err := json.Unmarshal(jsonWithIDAsString, &unmarshalled)

	require.NoError(t, err)
	assert.Equal(t, "1", unmarshalled.ID)
}

func TestLicenseeMarshal(t *testing.T) {
	licensee := NewLicensee(LicenseeTypeUser, "1")

	marshalled, err := json.Marshal(licensee)
	require.NoError(t, err)

	expected := strings.ToLower(`{"type":"` + LicenseeTypeUser.String() + `","id":"1","globalId":"gid://git-hub/User/1"}`)
	assert.Equal(t, expected, strings.ToLower(string(marshalled)))
}
