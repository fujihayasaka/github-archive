package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewHistoricalPushSelector(refUpdates []*types.ReferenceUpdate) *HistoricalPushSelector {
	return &HistoricalPushSelector{ReferenceUpdates: refUpdates}
}

func (p *HistoricalPushSelector) Validate() error {
	if p == nil {
		return nil
	}

	if len(p.ReferenceUpdates) == 0 {
		return twirp.RequiredArgumentError("reference_updates")
	}

	for _, ru := range p.GetReferenceUpdates() {
		if err := ru.Validate(); err != nil {
			return err
		}
	}

	return nil
}
