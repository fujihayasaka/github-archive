package flipper

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/turboscan/ts"

	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/stretchr/testify/suite"
)

type flipperTS struct {
	suite.Suite
	ffs  *featureFlagService
	mock *mockFeaturesAPI
}

// mockFeaureAPI provides a mock implementation of the Features API.
// The main method we use in flipper is CheckActorFeature.
// To enable a feature use the enableForRepo method.
type mockFeaturesAPI struct {
	enabled         map[string]bool
	globallyEnabled bool
}

func (m *mockFeaturesAPI) CheckActorFeature(ctx context.Context, req *twirpFeatures.CheckActorFeatureRequest) (*twirpFeatures.CheckActorFeatureResponse, error) {
	return &twirpFeatures.CheckActorFeatureResponse{

		ActorId:   req.ActorId,
		IsEnabled: m.enabled[req.ActorId],
	}, nil
}

func (m *mockFeaturesAPI) CheckActorsFeature(context.Context, *twirpFeatures.CheckActorsFeatureRequest) (*twirpFeatures.CheckActorsFeatureResponse, error) {
	return nil, nil
}
func (m *mockFeaturesAPI) CheckGlobalFeature(context.Context, *twirpFeatures.CheckGlobalFeatureRequest) (*twirpFeatures.CheckGlobalFeatureResponse, error) {
	return &twirpFeatures.CheckGlobalFeatureResponse{

		IsEnabled: m.globallyEnabled,
	}, nil
}
func (m *mockFeaturesAPI) CheckActorFeatures(context.Context, *twirpFeatures.CheckActorFeaturesRequest) (*twirpFeatures.CheckActorFeaturesResponse, error) {
	return nil, nil
}

func (m *mockFeaturesAPI) enableForRepo(repoID int64) {
	m.enabled[fmt.Sprintf("Repository:%d", repoID)] = true
}

func (m *mockFeaturesAPI) enableGlobally() {
	m.globallyEnabled = true
}

func TestFlipperTestSuite(t *testing.T) {
	suite.Run(t, new(flipperTS))
}

func (s *flipperTS) SetupTest() {
	s.mock = &mockFeaturesAPI{enabled: make(map[string]bool)}
	s.ffs = &featureFlagService{
		client: s.mock,
	}
}

const demoFF = "code_scanning_demo_feature_flag"

func (s *flipperTS) TestBasicNotEnabled() {
	ctx := context.Background()
	resp, err := s.ffs.isRepoEnabled(ctx, 1, demoFF)
	s.NoError(err)
	s.False(resp)
}

func (s *flipperTS) TestBasicRepoRequest() {
	s.mock.enableForRepo(1)
	ctx := context.Background()
	resp, err := s.ffs.isRepoEnabled(ctx, 1, demoFF)
	s.NoError(err)
	s.True(resp)
}

func (s *flipperTS) TestBasicGlobalRequest() {
	s.mock.enableGlobally()
	ctx := context.Background()
	resp, err := s.ffs.isRepoEnabled(ctx, 1, demoFF)
	s.NoError(err)
	s.True(resp)
}

func (s *flipperTS) TestOverrideViaContext() {
	ctx := context.Background()
	resp1, err := s.ffs.isRepoEnabled(ctx, 1, demoFF)
	s.NoError(err)
	s.False(resp1)

	ctxEnabledForRepo := WithFeatureEnabledFor(ctx, demoFF, ts.RepositoryEID(1))
	resp2, err := s.ffs.isRepoEnabled(ctxEnabledForRepo, 1, demoFF)
	s.NoError(err)
	s.True(resp2)

	resp3, err := s.ffs.isRepoEnabled(ctxEnabledForRepo, 2, demoFF)
	s.NoError(err)
	s.False(resp3)
}

func (s *flipperTS) TestGlobalOverride() {
	ctx := context.Background()
	resp1, err := s.ffs.isRepoEnabled(ctx, 1, demoFF)
	s.NoError(err)
	s.False(resp1)

	ctxGloballyEnabled := WithFeatureEnabled(ctx, demoFF)
	resp2, err := s.ffs.isRepoEnabled(ctxGloballyEnabled, 1, demoFF)
	s.NoError(err)
	s.True(resp2)
}

func (s *flipperTS) TestCache() {
	ctx := context.Background()
	s.mock.enableForRepo(1)
	resp1, err := s.ffs.isRepoEnabled(ctx, 1, demoFF)
	s.NoError(err)
	s.True(resp1)

	// Unset the mock
	s.mock.enabled = make(map[string]bool)
	resp2, err := s.ffs.isRepoEnabled(ctx, 1, demoFF)
	s.NoError(err)
	s.True(resp2)
}
