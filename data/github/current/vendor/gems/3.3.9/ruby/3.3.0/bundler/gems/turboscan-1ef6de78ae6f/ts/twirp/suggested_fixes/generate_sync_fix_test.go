package suggested_fixes

import (
	"testing"

	"github.com/github/turboscan/ts/proto"
	"github.com/stretchr/testify/require"

	sf "github.com/github/turboscan/ts/suggestedfixes"
)

func TestGenerateSyncFix_Valid(t *testing.T) {
	_, ctx, twirpServ, _, _, _, _ := setupService(t)
	req := &proto.GenerateSyncFixRequest{
		Sarif: "{}",
	}

	res, err := twirpServ.GenerateSyncFix(ctx, req)
	require.NoError(t, err)
	require.Equal(t, "some description", res.SuggestedFix.Description)
	require.Equal(t, "diff --git a/src/index.js b/src/index.js\nindex 1234567..abcdefg 100644", string(res.SuggestedFix.Files[0].DiffContent))
	require.Equal(t, proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_VALID, res.State)
}

func TestGenerateSyncFix_Invalid(t *testing.T) {
	_, ctx, twirpServ, _, _, _, _ := setupService(t)

	twirpServ.sf.FixGenerator = sf.NewMockInvalidFixGenerator()

	req := &proto.GenerateSyncFixRequest{
		Sarif: "{}",
	}

	res, err := twirpServ.GenerateSyncFix(ctx, req)
	require.NoError(t, err)
	require.Nil(t, res.SuggestedFix)
	require.Equal(t, proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_INVALID, res.State)
}
