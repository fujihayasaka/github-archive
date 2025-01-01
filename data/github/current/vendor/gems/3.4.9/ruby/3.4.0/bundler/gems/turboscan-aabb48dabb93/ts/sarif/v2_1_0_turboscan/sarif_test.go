package v210turboscan_test

import (
	"encoding/json"
	"testing"

	v210turboscan "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/stretchr/testify/require"
)

func TestOmitNegative(t *testing.T) {
	res := v210turboscan.Result{RuleIndex: -1}
	data, err := json.Marshal(&res)
	require.NoError(t, err)
	// leaves original RuleIndex unmodified
	require.Equal(t, -1, res.RuleIndex)
	require.Equal(t, []byte(`{}`), data)
}

func TestIncludeZero(t *testing.T) {
	res := v210turboscan.Result{RuleIndex: 0}
	data, err := json.Marshal(&res)
	require.NoError(t, err)
	require.Equal(t, []byte(`{"ruleIndex":0}`), data)
}

func TestIncludeNonZero(t *testing.T) {
	res := v210turboscan.Result{RuleIndex: 1}
	data, err := json.Marshal(&res)
	require.NoError(t, err)
	require.Equal(t, []byte(`{"ruleIndex":1}`), data)
}

func TestIncludeNested(t *testing.T) {
	res := v210turboscan.Result{RuleIndex: 0, Rule: &v210turboscan.ReportingDescriptorReference{
		Id:    "rule/1",
		Index: -1,
		ToolComponent: &v210turboscan.ToolComponentReference{
			Guid:  "e91e0de1-9ce6-4ed3-83ec-16bb54c8000a",
			Index: 2,
		},
	}}
	data, err := json.Marshal(&res)
	require.NoError(t, err)
	require.Equal(t, []byte(`{"rule":{"id":"rule/1","toolComponent":{"guid":"e91e0de1-9ce6-4ed3-83ec-16bb54c8000a","index":2}},"ruleIndex":0}`), data)
}
