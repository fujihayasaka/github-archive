package launchchaos

import (
	"context"
	"errors"
	"math/rand"
	"sync"

	"github.com/github/launch/pkg/fault"
)

const (
	defaultRandSeed      = 1
	DefaultFeatureFlag   = "launch_chaos_engaged"
	DefaultParticipation = 0.9
)

var (
	// ErrInvalidPercent when a percent is outside of [0.0,1.0].
	ErrInvalidPercent = errors.New("percent must be 0.0 <= percent <= 1.0")
)

type featureFlagParticipator struct {
	featureFlag string
	checkF      func(ctx context.Context, featureFlag string) bool

	// participation is the percent of requests that run the injector. 0.0 <= p <= 1.0.
	participation float32

	// randFunc is a function that returns a float32 [0.0,1.0).
	randFunc func() float32

	// randMtx protects Fault.rand, which is not thread safe.
	randMtx sync.Mutex
}

func NewFeatureFlagParticipator(featureFlag string, checkF func(context.Context, string) bool, participation float32) (fault.Participator, error) {
	if participation < 0.0 || participation > 1.0 {
		return nil, ErrInvalidPercent
	}
	r := rand.New(rand.NewSource(defaultRandSeed))
	rf := r.Float32

	ffp := &featureFlagParticipator{
		featureFlag:   featureFlag,
		checkF:        checkF,
		participation: participation,
		randFunc:      rf,
	}

	return ffp, nil
}

func (ffp *featureFlagParticipator) Participate(ctx context.Context) bool {
	ffEnabled := ffp.checkF(ctx, ffp.featureFlag)
	if !ffEnabled {
		return false
	}

	ffp.randMtx.Lock()
	rn := ffp.randFunc()
	ffp.randMtx.Unlock()

	if rn < ffp.participation && ffp.participation <= 1.0 {
		return true
	}

	return false
}
