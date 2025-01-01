package tiers

import (
	"context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

func TestDefaultToTier3OnError(t *testing.T) {
	ctx := context.Background()
	repoID := types.GlobalID("foo")

	recordingLogger := testutils.NewRecordingLogger()

	ghTwirpClient := &ghtwirp.MockClient{}
	ghTwirpClient.EXPECT().GetTrustTier(mock.Anything, mock.Anything).Return(types.RepositoryTier(0), errors.New("error"))

	tier, err := FetchRepositoryTier(ctx, recordingLogger.Logger, ghTwirpClient, repoID)

	require.NotNil(t, err)
	require.Equal(t, types.RepositoryTier3, tier)
}

func TestTrustTierToTier3NoError(t *testing.T) {
	ctx := context.Background()
	repoID := types.GlobalID("foo")

	recordingLogger := testutils.NewRecordingLogger()

	ghTwirpClient := &ghtwirp.MockClient{}
	ghTwirpClient.EXPECT().GetTrustTier(mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)

	tier, err := FetchRepositoryTier(ctx, recordingLogger.Logger, ghTwirpClient, repoID)

	require.NoError(t, err)
	require.Equal(t, types.RepositoryTier3, tier)
}
