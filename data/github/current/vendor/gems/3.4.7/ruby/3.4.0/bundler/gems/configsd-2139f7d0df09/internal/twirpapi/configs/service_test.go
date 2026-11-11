package configs_test

import (
	"errors"
	"testing"
	"time"

	"github.com/github/configsd/internal/model"
	"github.com/github/configsd/internal/twirpapi/configs"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"go.uber.org/mock/gomock"
)

func TestNewConfigsService(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	mockStore := model.NewMockStore(ctrl)
	service := configs.NewConfigsService(mockStore)

	require.NotNil(t, service)
}

func TestService_ResolveConfigsByTarget(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	mockStore := model.NewMockStore(ctrl)
	service := configs.NewConfigsService(mockStore)
	ctx := t.Context()

	t.Run("nil request", func(t *testing.T) {
		response, err := service.ResolveConfigsByTarget(ctx, nil)

		require.Nil(t, response)
		require.Error(t, err)

		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.InvalidArgument, twerr.Code())
		require.Contains(t, twerr.Msg(), "target is required")
	})

	t.Run("nil target", func(t *testing.T) {
		req := &configs.ResolveConfigsByTargetRequest{
			Target: nil,
		}

		response, err := service.ResolveConfigsByTarget(ctx, req)

		require.Nil(t, response)
		require.Error(t, err)

		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.InvalidArgument, twerr.Code())
		require.Contains(t, twerr.Msg(), "target is required")
	})

	t.Run("unsupported target type", func(t *testing.T) {
		req := &configs.ResolveConfigsByTargetRequest{
			Target: &configs.ConfigTarget{
				Type: 999, // Unsupported type
				Id:   123,
			},
		}

		response, err := service.ResolveConfigsByTarget(ctx, req)

		require.Nil(t, response)
		require.Error(t, err)

		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.InvalidArgument, twerr.Code())
		require.Contains(t, twerr.Msg(), "unsupported target type")
	})

	t.Run("store error", func(t *testing.T) {
		req := &configs.ResolveConfigsByTargetRequest{
			Target: &configs.ConfigTarget{
				Type: configs.TargetType_Business,
				Id:   123,
			},
		}

		expectedTarget := model.ConfigurationTarget{
			Type: model.Business,
			ID:   123,
		}

		storeError := errors.New("database connection failed")
		mockStore.EXPECT().
			AllProperties(ctx, expectedTarget).
			Return(nil, storeError)

		response, err := service.ResolveConfigsByTarget(ctx, req)

		require.Nil(t, response)
		require.Error(t, err)

		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.Internal, twerr.Code())
	})

	t.Run("successful business target resolution", func(t *testing.T) {
		req := &configs.ResolveConfigsByTargetRequest{
			Target: &configs.ConfigTarget{
				Type: configs.TargetType_Business,
				Id:   456,
			},
		}

		expectedTarget := model.ConfigurationTarget{
			Type: model.Business,
			ID:   456,
		}

		createdAt := time.Date(2023, 1, 1, 12, 0, 0, 0, time.UTC)
		updatedAt := time.Date(2023, 1, 2, 12, 0, 0, 0, time.UTC)

		storeConfigs := map[string]model.Configuration{
			"config1": {
				Name:  "config1",
				Value: "value1",
				Target: &model.ConfigurationTarget{
					Type: model.Business,
					ID:   456,
				},
				Final:     false,
				CreatedAt: createdAt,
				UpdatedAt: updatedAt,
			},
			"config2": {
				Name:  "config2",
				Value: "value2",
				Target: &model.ConfigurationTarget{
					Type: model.Global,
					ID:   0,
				},
				Final:     true,
				CreatedAt: createdAt,
				UpdatedAt: updatedAt,
			},
		}

		mockStore.EXPECT().
			AllProperties(ctx, expectedTarget).
			Return(storeConfigs, nil)

		response, err := service.ResolveConfigsByTarget(ctx, req)

		require.NoError(t, err)
		require.NotNil(t, response)
		require.Len(t, response.Configs.Configs, 2)

		// Verify config1
		config1 := response.Configs.Configs["config1"]
		require.NotNil(t, config1)
		require.Equal(t, "config1", config1.Name)
		require.Equal(t, "value1", config1.Value)
		require.False(t, config1.Final)
		require.NotNil(t, config1.Target)
		require.Equal(t, configs.TargetType_Business, config1.Target.Type)
		require.EqualValues(t, 456, config1.Target.Id)
		require.NotNil(t, config1.CreatedAt)
		require.NotNil(t, config1.UpdatedAt)

		// Verify config2
		config2 := response.Configs.Configs["config2"]
		require.NotNil(t, config2)
		require.Equal(t, "config2", config2.Name)
		require.Equal(t, "value2", config2.Value)
		require.True(t, config2.Final)
		require.NotNil(t, config2.Target)
		require.Equal(t, configs.TargetType_Global, config2.Target.Type)
		require.EqualValues(t, 0, config2.Target.Id)
	})

	t.Run("successful global target resolution", func(t *testing.T) {
		req := &configs.ResolveConfigsByTargetRequest{
			Target: &configs.ConfigTarget{
				Type: configs.TargetType_Global,
				Id:   0,
			},
		}

		expectedTarget := model.ConfigurationTarget{
			Type: model.Global,
			ID:   0,
		}

		storeConfigs := map[string]model.Configuration{
			"global-config": {
				Name:  "global-config",
				Value: "global-value",
				Target: &model.ConfigurationTarget{
					Type: model.Global,
					ID:   0,
				},
				Final:     false,
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			},
		}

		mockStore.EXPECT().
			AllProperties(ctx, expectedTarget).
			Return(storeConfigs, nil)

		response, err := service.ResolveConfigsByTarget(ctx, req)

		require.NoError(t, err)
		require.NotNil(t, response)
		require.Len(t, response.Configs.Configs, 1)

		globalConfig := response.Configs.Configs["global-config"]
		require.NotNil(t, globalConfig)
		require.Equal(t, "global-config", globalConfig.Name)
		require.Equal(t, "global-value", globalConfig.Value)
		require.Equal(t, configs.TargetType_Global, globalConfig.Target.Type)
	})

	t.Run("empty result from store", func(t *testing.T) {
		req := &configs.ResolveConfigsByTargetRequest{
			Target: &configs.ConfigTarget{
				Type: configs.TargetType_Business,
				Id:   789,
			},
		}

		expectedTarget := model.ConfigurationTarget{
			Type: model.Business,
			ID:   789,
		}

		mockStore.EXPECT().
			AllProperties(ctx, expectedTarget).
			Return(map[string]model.Configuration{}, nil)

		response, err := service.ResolveConfigsByTarget(ctx, req)

		require.NoError(t, err)
		require.NotNil(t, response)
		require.Empty(t, response.Configs.Configs)
	})
}

func TestService_ResolveConfigsByTargetWithOwners(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	mockStore := model.NewMockStore(ctrl)
	service := configs.NewConfigsService(mockStore)
	ctx := t.Context()

	t.Run("nil request", func(t *testing.T) {
		response, err := service.ResolveConfigsByTargetWithOwners(ctx, nil)

		require.Nil(t, response)
		require.Error(t, err)

		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.InvalidArgument, twerr.Code())
		require.Contains(t, twerr.Msg(), "target is required")
	})

	t.Run("nil target", func(t *testing.T) {
		req := &configs.ResolveConfigsByTargetWithOwnersRequest{
			Target: nil,
		}

		response, err := service.ResolveConfigsByTargetWithOwners(ctx, req)

		require.Nil(t, response)
		require.Error(t, err)

		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.InvalidArgument, twerr.Code())
		require.Contains(t, twerr.Msg(), "target is required")
	})

	t.Run("successful resolution with all owner levels", func(t *testing.T) {
		repoID := uint64(100)
		ownerID := uint64(200)
		businessID := uint64(300)

		req := &configs.ResolveConfigsByTargetWithOwnersRequest{
			Target: &configs.ConfigTargetWithOwners{
				RepoId:     repoID,
				OwnerId:    ownerID,
				BusinessId: businessID,
			},
		}

		expectedTargets := []model.ConfigurationTarget{
			{Type: model.Repository, ID: 100},
			{Type: model.User, ID: 200},
			{Type: model.Business, ID: 300},
			{Type: model.Global, ID: 0},
		}

		createdAt := time.Date(2023, 1, 1, 12, 0, 0, 0, time.UTC)
		updatedAt := time.Date(2023, 1, 2, 12, 0, 0, 0, time.UTC)

		storeConfigs := map[string]model.Configuration{
			"repo_config": {
				Name:  "repo_config",
				Value: "repo_value",
				Target: &model.ConfigurationTarget{
					Type: model.Repository,
					ID:   100,
				},
				Final:     false,
				CreatedAt: createdAt,
				UpdatedAt: updatedAt,
			},
			"override_config": {
				Name:  "override_config",
				Value: "user_value",
				Target: &model.ConfigurationTarget{
					Type: model.User,
					ID:   200,
				},
				Final:     false,
				CreatedAt: createdAt,
				UpdatedAt: updatedAt,
			},
		}

		mockStore.EXPECT().
			ResolvedConfigsByTargetWithOwners(ctx, expectedTargets).
			Return(storeConfigs, nil)

		response, err := service.ResolveConfigsByTargetWithOwners(ctx, req)

		require.NoError(t, err)
		require.NotNil(t, response)
		require.Len(t, response.Configs.Configs, 2)

		// Verify repo_config
		repoConfig := response.Configs.Configs["repo_config"]
		require.NotNil(t, repoConfig)
		require.Equal(t, "repo_config", repoConfig.Name)
		require.Equal(t, "repo_value", repoConfig.Value)
		require.Equal(t, configs.TargetType_Repository, repoConfig.Target.Type)
		require.EqualValues(t, 100, repoConfig.Target.Id)

		// Verify override_config
		overrideConfig := response.Configs.Configs["override_config"]
		require.NotNil(t, overrideConfig)
		require.Equal(t, "override_config", overrideConfig.Name)
		require.Equal(t, "user_value", overrideConfig.Value)
		require.Equal(t, configs.TargetType_User, overrideConfig.Target.Type)
		require.EqualValues(t, 200, overrideConfig.Target.Id)
	})

	t.Run("successful resolution with only business_id", func(t *testing.T) {
		businessID := uint64(400)

		req := &configs.ResolveConfigsByTargetWithOwnersRequest{
			Target: &configs.ConfigTargetWithOwners{
				BusinessId: businessID,
			},
		}

		expectedTargets := []model.ConfigurationTarget{
			{Type: model.Business, ID: 400},
			{Type: model.Global, ID: 0},
		}

		storeConfigs := map[string]model.Configuration{
			"business_config": {
				Name:  "business_config",
				Value: "business_value",
				Target: &model.ConfigurationTarget{
					Type: model.Business,
					ID:   400,
				},
				Final:     false,
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			},
		}

		mockStore.EXPECT().
			ResolvedConfigsByTargetWithOwners(ctx, expectedTargets).
			Return(storeConfigs, nil)

		response, err := service.ResolveConfigsByTargetWithOwners(ctx, req)

		require.NoError(t, err)
		require.NotNil(t, response)
		require.Len(t, response.Configs.Configs, 1)

		businessConfig := response.Configs.Configs["business_config"]
		require.NotNil(t, businessConfig)
		require.Equal(t, "business_config", businessConfig.Name)
		require.Equal(t, "business_value", businessConfig.Value)
	})

	t.Run("successful resolution with only global (no owner params)", func(t *testing.T) {
		req := &configs.ResolveConfigsByTargetWithOwnersRequest{
			Target: &configs.ConfigTargetWithOwners{},
		}

		expectedTargets := []model.ConfigurationTarget{
			{Type: model.Global, ID: 0},
		}

		storeConfigs := map[string]model.Configuration{
			"global_config": {
				Name:  "global_config",
				Value: "global_value",
				Target: &model.ConfigurationTarget{
					Type: model.Global,
					ID:   0,
				},
				Final:     true,
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			},
		}

		mockStore.EXPECT().
			ResolvedConfigsByTargetWithOwners(ctx, expectedTargets).
			Return(storeConfigs, nil)

		response, err := service.ResolveConfigsByTargetWithOwners(ctx, req)

		require.NoError(t, err)
		require.NotNil(t, response)
		require.Len(t, response.Configs.Configs, 1)

		globalConfig := response.Configs.Configs["global_config"]
		require.NotNil(t, globalConfig)
		require.Equal(t, "global_config", globalConfig.Name)
		require.Equal(t, "global_value", globalConfig.Value)
		require.True(t, globalConfig.Final)
	})

	t.Run("successful resolution with owner_id and business_id", func(t *testing.T) {
		ownerID := uint64(500)
		businessID := uint64(600)

		req := &configs.ResolveConfigsByTargetWithOwnersRequest{
			Target: &configs.ConfigTargetWithOwners{
				OwnerId:    ownerID,
				BusinessId: businessID,
			},
		}

		expectedTargets := []model.ConfigurationTarget{
			{Type: model.User, ID: 500},
			{Type: model.Business, ID: 600},
			{Type: model.Global, ID: 0},
		}

		storeConfigs := map[string]model.Configuration{
			"user_config": {
				Name:  "user_config",
				Value: "user_value",
				Target: &model.ConfigurationTarget{
					Type: model.User,
					ID:   500,
				},
				Final:     false,
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			},
		}

		mockStore.EXPECT().
			ResolvedConfigsByTargetWithOwners(ctx, expectedTargets).
			Return(storeConfigs, nil)

		response, err := service.ResolveConfigsByTargetWithOwners(ctx, req)

		require.NoError(t, err)
		require.NotNil(t, response)
		require.Len(t, response.Configs.Configs, 1)
	})

	t.Run("empty result from store", func(t *testing.T) {
		businessID := uint64(700)

		req := &configs.ResolveConfigsByTargetWithOwnersRequest{
			Target: &configs.ConfigTargetWithOwners{
				BusinessId: businessID,
			},
		}

		expectedTargets := []model.ConfigurationTarget{
			{Type: model.Business, ID: 700},
			{Type: model.Global, ID: 0},
		}

		mockStore.EXPECT().
			ResolvedConfigsByTargetWithOwners(ctx, expectedTargets).
			Return(map[string]model.Configuration{}, nil)

		response, err := service.ResolveConfigsByTargetWithOwners(ctx, req)

		require.NoError(t, err)
		require.NotNil(t, response)
		require.Empty(t, response.Configs.Configs)
	})

	t.Run("store error", func(t *testing.T) {
		businessID := uint64(800)

		req := &configs.ResolveConfigsByTargetWithOwnersRequest{
			Target: &configs.ConfigTargetWithOwners{
				BusinessId: businessID,
			},
		}

		expectedTargets := []model.ConfigurationTarget{
			{Type: model.Business, ID: 800},
			{Type: model.Global, ID: 0},
		}

		storeError := errors.New("database connection failed")
		mockStore.EXPECT().
			ResolvedConfigsByTargetWithOwners(ctx, expectedTargets).
			Return(nil, storeError)

		response, err := service.ResolveConfigsByTargetWithOwners(ctx, req)

		require.Nil(t, response)
		require.Error(t, err)

		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.Internal, twerr.Code())
	})
}
