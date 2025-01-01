package fault

import (
	"context"
)

type Participator interface {
	Participate(ctx context.Context) bool
}

func NewAlwaysParticipator() Participator {
	return &alwaysParticipate{}
}

type alwaysParticipate struct{}

func (ap *alwaysParticipate) Participate(_ context.Context) bool {
	return true
}

func WithParticipator(p Participator) Option {
	return func(f *Fault) {
		f.participateFunc = p.Participate
	}
}
