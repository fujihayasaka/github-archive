package enabled_status

import (
	"context"
	"testing"

	"github.com/pkg/errors"

	"go.uber.org/mock/gomock"

	"github.com/github/turboscan/ts/mocks"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

func TestSavePublishedStatus(t *testing.T) {
	db := dbtest.RequireConnectionWithoutAutoIncrement(t)
	s := &EnabledStatusService{
		db:            db,
		shouldPublish: true,
	}

	repoID := ts.RepositoryEID(1)

	// Saving works once
	err := s.savePublishedStatus(repoID, false, ts.EnablementReason_DISABLE_DEFAULT_SETUP)
	require.NoError(t, err)
	var state ts.PublishedEnabledState
	err = db.First(&state).Error
	require.NoError(t, err)
	require.Equal(t, false, state.Enabled)
	require.Equal(t, ts.EnablementReason_DISABLE_DEFAULT_SETUP, state.Reason)

	// Saving works twice
	err = s.savePublishedStatus(repoID, false, ts.EnablementReason_DISABLE_DEFAULT_SETUP)
	require.NoError(t, err)
	err = db.First(&state).Error
	require.NoError(t, err)
	require.Equal(t, false, state.Enabled)
	require.Equal(t, ts.EnablementReason_DISABLE_DEFAULT_SETUP, state.Reason)

	// And we can change values
	err = s.savePublishedStatus(repoID, true, ts.EnablementReason_ENABLE_DEFAULT_SETUP)
	require.NoError(t, err)
	err = db.First(&state).Error
	require.NoError(t, err)
	require.Equal(t, true, state.Enabled)
	require.Equal(t, ts.EnablementReason_ENABLE_DEFAULT_SETUP, state.Reason)
}

func TestIsCodeQLCheckNotOptional(t *testing.T) {
	db := dbtest.RequireConnection(t)
	mockCtrl := gomock.NewController(t)
	ma := mocks.NewMockCodeqlRepoDB(mockCtrl)

	repoID := ts.RepositoryEID(1)
	ctx := context.Background()
	s := &EnabledStatusService{
		db:            db,
		shouldPublish: true,
		maDB:          ma,
	}

	ma.EXPECT().GetCodeqlRepo(ctx, repoID).Return(nil, ts.ErrCodeqlRepoNotFound)
	v, err := s.IsCodeQLCheckOptional(ctx, repoID, false)
	require.NoError(t, err)
	require.False(t, v)
}

func TestIsCodeQLCheckNotOptionalDependabot(t *testing.T) {
	db := dbtest.RequireConnection(t)
	mockCtrl := gomock.NewController(t)
	ma := mocks.NewMockCodeqlRepoDB(mockCtrl)

	repoID := ts.RepositoryEID(1)
	ctx := context.Background()
	s := &EnabledStatusService{
		db:            db,
		shouldPublish: true,
		maDB:          ma,
	}

	ma.EXPECT().IsEnabled(ctx, repoID).Return(false, nil)
	v, err := s.IsCodeQLCheckOptional(ctx, repoID, true)
	require.NoError(t, err)
	require.False(t, v)
}

func TestIsCodeQLCheckOptionalDependabot(t *testing.T) {
	db := dbtest.RequireConnection(t)
	mockCtrl := gomock.NewController(t)
	ma := mocks.NewMockCodeqlRepoDB(mockCtrl)

	repoID := ts.RepositoryEID(1)
	ctx := context.Background()
	s := &EnabledStatusService{
		db:            db,
		shouldPublish: true,
		maDB:          ma,
	}
	ma.EXPECT().IsEnabled(ctx, repoID).Return(true, nil)
	v, err := s.IsCodeQLCheckOptional(ctx, repoID, true)
	require.NoError(t, err)
	require.True(t, v)
}

func TestIsCodeQLCheckOptionalWaiting(t *testing.T) {
	db := dbtest.RequireConnection(t)
	mockCtrl := gomock.NewController(t)
	ma := mocks.NewMockCodeqlRepoDB(mockCtrl)

	repoID := ts.RepositoryEID(1)
	ctx := context.Background()
	s := &EnabledStatusService{
		db:            db,
		shouldPublish: true,
		maDB:          ma,
	}
	ma.EXPECT().GetCodeqlRepo(ctx, repoID).Return(&ts.CodeqlRepo{}, nil)
	v, err := s.IsCodeQLCheckOptional(ctx, repoID, false)
	require.NoError(t, err)
	require.True(t, v)
}

func TestIsCodeQLCheckOptionalError(t *testing.T) {
	db := dbtest.RequireConnection(t)
	mockCtrl := gomock.NewController(t)
	ma := mocks.NewMockCodeqlRepoDB(mockCtrl)

	repoID := ts.RepositoryEID(1)
	ctx := context.Background()
	s := &EnabledStatusService{
		db:            db,
		shouldPublish: true,
		maDB:          ma,
	}
	expectedErr := errors.New("something broke")
	ma.EXPECT().GetCodeqlRepo(ctx, repoID).Return(nil, expectedErr)
	v, err := s.IsCodeQLCheckOptional(ctx, repoID, false)
	require.ErrorIs(t, err, expectedErr)
	require.False(t, v)
}
