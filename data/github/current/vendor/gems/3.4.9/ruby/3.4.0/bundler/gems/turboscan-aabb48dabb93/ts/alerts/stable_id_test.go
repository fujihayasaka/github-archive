package alerts

import (
	"fmt"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func TestNewStableId(t *testing.T) {
	b := NewStableID(42, "rule/js", Location{
		FilePath:    "bar/foo.js",
		Fingerprint: "f7383056e1a95596:1",
		Region: ts.Region{
			StartColumn: 1,
			EndColumn:   44,
		},
	})

	require.Equal(t, "0D334677D611FC3A7D1C9CA0C267BFF6000DDA2E00", fmt.Sprintf("%X", b))
}

func TestStableIdPutIndex(t *testing.T) {
	sid := StableAlertIdentifier{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}
	nsid := sid.PutIndex(42)
	require.Equal(t, uint8(42), nsid[20])
}
