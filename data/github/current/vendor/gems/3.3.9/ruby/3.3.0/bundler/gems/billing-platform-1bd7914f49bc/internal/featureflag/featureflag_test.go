package featureflag

import (
	"context"
	"reflect"
	"testing"
	"time"

	"github.com/onsi/gomega"

	featurescore "github.com/github/monolith-twirp-features/core/v1"
)

func Setup(t *testing.T) (
	*mockFeaturesAPI,
	*mockFeaturesCacheClock,
	*FeatureFlagClient,
	*gomega.GomegaWithT,
) {
	g := gomega.NewGomegaWithT(t)
	now := time.Date(2022, 12, 1, 0, 0, 0, 0, time.UTC)
	featuresAPI := &mockFeaturesAPI{}
	clock := &mockFeaturesCacheClock{now: now}
	client := NewFeatureFlagClientWithClock(featuresAPI, clock)
	return featuresAPI, clock, client, g
}

func TestInitializer(t *testing.T) {
	t.Run("FeatureFlagClient returns pointer to new client", func(t *testing.T) {
		got := NewFeatureFlagClient(nil)
		gotType := reflect.TypeOf(got)
		if gotType != reflect.TypeOf(&FeatureFlagClient{}) {
			t.Errorf("expected FeatureFlagClient, got %v", gotType)
		}
	})

	t.Run("NullFeatureFlagClient returns pointer to new null client", func(t *testing.T) {
		got := NewNullFeatureFlagClient()
		gotType := reflect.TypeOf(got)
		if gotType != reflect.TypeOf(&NullFeatureFlagClient{}) {
			t.Errorf("expected NullFeatureFlagClient, got %v", gotType)
		}
	})
}

type mockFeaturesAPI struct {
	globallyEnabledByFeature map[string]bool
	enabledByFeatureAndActor map[string]map[string]bool
}

func (m *mockFeaturesAPI) setEnableGlobally(flag string, enabled bool) {
	if m.globallyEnabledByFeature == nil {
		m.globallyEnabledByFeature = make(map[string]bool)
	}
	m.globallyEnabledByFeature[flag] = enabled
}

type mockFeaturesCacheClock struct {
	now time.Time
}

func (m *mockFeaturesCacheClock) Now() time.Time {
	return m.now
}
func (m *mockFeaturesCacheClock) Later(d time.Duration) time.Time {
	return m.now.Add(d)
}

func (m *mockFeaturesAPI) setFlagForActor(flag, actorID string, enabled bool) {
	if m.enabledByFeatureAndActor == nil {
		m.enabledByFeatureAndActor = make(map[string]map[string]bool)
	}
	if m.enabledByFeatureAndActor[flag] == nil {
		m.enabledByFeatureAndActor[flag] = make(map[string]bool)
	}
	m.enabledByFeatureAndActor[flag][actorID] = enabled
}

func (m *mockFeaturesAPI) CheckActorFeature(
	_ context.Context,
	req *featurescore.CheckActorFeatureRequest,
) (*featurescore.CheckActorFeatureResponse, error) {
	if m.enabledByFeatureAndActor != nil {
		if byActor, ok := m.enabledByFeatureAndActor[req.Feature]; ok {
			if enabled, ok := byActor[req.ActorId]; ok {
				return &featurescore.CheckActorFeatureResponse{
					ActorId:   req.ActorId,
					IsEnabled: enabled,
				}, nil
			}
		}
	}
	return &featurescore.CheckActorFeatureResponse{
		ActorId:   req.ActorId,
		IsEnabled: false,
	}, nil
}

func (m *mockFeaturesAPI) CheckActorsFeature(
	context.Context,
	*featurescore.CheckActorsFeatureRequest,
) (*featurescore.CheckActorsFeatureResponse, error) {
	return nil, nil
}

func (m *mockFeaturesAPI) CheckGlobalFeature(
	_ context.Context,
	req *featurescore.CheckGlobalFeatureRequest,
) (*featurescore.CheckGlobalFeatureResponse, error) {
	if m.globallyEnabledByFeature != nil {
		if enabled, ok := m.globallyEnabledByFeature[req.Feature]; ok {
			return &featurescore.CheckGlobalFeatureResponse{
				IsEnabled: enabled,
			}, nil
		}
	}
	return &featurescore.CheckGlobalFeatureResponse{IsEnabled: false}, nil
}

func (m *mockFeaturesAPI) CheckActorFeatures(context.Context, *featurescore.CheckActorFeaturesRequest) (*featurescore.CheckActorFeaturesResponse, error) {
	return nil, nil
}

func TestCheckGlobalFeature(t *testing.T) {
	t.Run("returns true when feature is enabled", func(t *testing.T) {
		featureName := "feature"
		featuresAPI := &mockFeaturesAPI{}
		featuresAPI.setEnableGlobally(featureName, true)

		enabled, err := NewFeatureFlagClient(featuresAPI).
			CheckGlobalFeature(context.Background(), featureName)

		if err != nil {
			t.Errorf("expected nil, got %v", err)
		}
		if !enabled {
			t.Errorf("expected true, got %v", enabled)
		}
	})

	t.Run("returns false when feature is enabled", func(t *testing.T) {
		featureName := "feature"
		featuresAPI := &mockFeaturesAPI{}
		featuresAPI.setEnableGlobally(featureName, false)

		enabled, err := NewFeatureFlagClient(featuresAPI).
			CheckGlobalFeature(context.Background(), featureName)

		if err != nil {
			t.Errorf("expected nil, got %v", err)
		}
		if enabled {
			t.Errorf("expected false, got %v", enabled)
		}
	})
}

func TestCheckActorFeature(t *testing.T) {
	featureName := "feature"
	actorID := "Repository:1234"
	otherFeatureName := "notthefeature"
	otherActorID := "Repository:7890"

	assertFeatureState := func(
		g *gomega.GomegaWithT,
		client *FeatureFlagClient,
		expectedActorEnabled bool,
		expectedOtherActorEnabled bool,
	) {
		ctx := context.Background()

		enabled, err := client.CheckActorFeature(ctx, featureName, actorID)
		g.Expect(err).To(gomega.BeNil())
		g.Expect(enabled).To(gomega.Equal(expectedActorEnabled))

		enabled, err = client.CheckActorFeature(ctx, featureName, otherActorID)
		g.Expect(err).To(gomega.BeNil())
		g.Expect(enabled).To(gomega.Equal(expectedOtherActorEnabled))

		enabled, err = client.CheckActorFeature(ctx, otherFeatureName, actorID)
		g.Expect(err).To(gomega.BeNil())
		g.Expect(enabled).To(gomega.Equal(false))

		enabled, err = client.CheckActorFeature(ctx, otherFeatureName, otherActorID)
		g.Expect(err).To(gomega.BeNil())
		g.Expect(enabled).To(gomega.Equal(false))
	}

	t.Run("returns the state of a feature flag for a given feature and actor when globally enabled", func(t *testing.T) {
		mockFeaturesAPI, mockClock, client, g := Setup(t)

		assertFeatureState(g, client, false, false)
		mockFeaturesAPI.setEnableGlobally(featureName, true)
		assertFeatureState(g, client, false, false)
		mockClock.now = mockClock.now.Add(time.Minute * 5)
		assertFeatureState(g, client, true, true)
		mockFeaturesAPI.setEnableGlobally(featureName, false)
		assertFeatureState(g, client, true, true)
		mockClock.now = mockClock.now.Add(time.Minute * 5)
		assertFeatureState(g, client, false, false)
	})

	t.Run("returns the cached state of feature flag for a given feature and actor", func(t *testing.T) {
		mockFeaturesAPI, mockClock, client, g := Setup(t)

		assertFeatureState(g, client, false, false)
		mockFeaturesAPI.setFlagForActor(featureName, actorID, true)
		assertFeatureState(g, client, false, false)
		mockClock.now = mockClock.now.Add(time.Minute * 5)
		assertFeatureState(g, client, true, false)
		mockFeaturesAPI.setFlagForActor(featureName, actorID, false)
		assertFeatureState(g, client, true, false)
		mockClock.now = mockClock.now.Add(time.Minute * 5)
		assertFeatureState(g, client, false, false)
	})
}
