// Package flipper contains a caching wrapper around the GitHub Flipper API.
package flipper

import (
	"context"
	"time"

	"github.com/github/go-stats"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	lru "github.com/hashicorp/golang-lru/v2/expirable"
	"github.com/pkg/errors"
)

type FeaturesAPI interface {
	CheckActorFeature(context.Context, *twirpFeatures.CheckActorFeatureRequest) (*twirpFeatures.CheckActorFeatureResponse, error)
	CheckGlobalFeature(context.Context, *twirpFeatures.CheckGlobalFeatureRequest) (*twirpFeatures.CheckGlobalFeatureResponse, error)
}

type Flipper interface {
	IsEnabled(ctx context.Context, feature, actorID string) (bool, error)
	IsGloballyEnabled(ctx context.Context, feature string) (bool, error)
}

type nullFlipper struct{}

func (*nullFlipper) IsEnabled(ctx context.Context, feature, actorID string) (bool, error) {
	return false, nil
}

func (*nullFlipper) IsGloballyEnabled(ctx context.Context, feature string) (bool, error) {
	return false, nil
}

var NullFlipper Flipper = &nullFlipper{}

type Client struct {
	cache   *lru.LRU[key, bool]
	statter stats.Client
	api     FeaturesAPI
}

func New(api FeaturesAPI, statter stats.Client) (*Client, error) {
	return &Client{
		cache:   lru.NewLRU[key, bool](10000, nil, time.Minute),
		api:     api,
		statter: statter,
	}, nil
}

type key struct {
	actorID string
	feature string
}

func (f *Client) fetch(key key, fn func() (bool, error)) (bool, error) {
	if cachedValue, ok := f.cache.Peek(key); ok {
		f.statter.Counter("hit", stats.Tags{}, 1)
		return cachedValue, nil
	}
	f.statter.Counter("miss", stats.Tags{}, 1)
	value, err := fn()
	if err != nil {
		return value, err
	}
	evicted := f.cache.Add(key, value)
	if evicted {
		f.statter.Counter("evicted", stats.Tags{}, 1)
	}
	return value, err
}

func (f *Client) IsEnabled(ctx context.Context, feature, actorID string) (bool, error) {
	k := key{
		actorID: actorID,
		feature: feature,
	}
	return f.fetch(k, func() (bool, error) {
		res, err := f.api.CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{
			ActorId: actorID,
			Feature: feature,
		})
		if err != nil {
			return false, errors.Wrap(err, "failed to check flipper")
		}
		return res.IsEnabled, nil
	})
}

func (f *Client) IsGloballyEnabled(ctx context.Context, feature string) (bool, error) {
	return f.fetch(key{feature: feature}, func() (bool, error) {
		res, err := f.api.CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{
			Feature: feature,
		})
		if err != nil {
			return false, errors.Wrap(err, "failed to check flipper")
		}
		return res.IsEnabled, nil
	})
}
