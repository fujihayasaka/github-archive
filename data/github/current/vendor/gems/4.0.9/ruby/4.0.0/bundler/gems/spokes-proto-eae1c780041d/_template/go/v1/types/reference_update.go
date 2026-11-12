package types

import (
	"fmt"

	"github.com/twitchtv/twirp"
)

func NewReferenceUpdate(ref *Reference, before, after *ObjectID) *ReferenceUpdate {
	return &ReferenceUpdate{
		Reference: ref,
		Before:    before,
		After:     after,
	}
}

func (r *ReferenceUpdate) Validate() error {
	if r == nil {
		return nil
	}

	if r.GetReference() == nil {
		return twirp.RequiredArgumentError("reference")
	}

	if r.GetBefore() == nil && r.GetAfter() == nil {
		return twirp.InvalidArgumentError("reference_update", fmt.Sprintf("is invalid as before and after are both nil, only one of them can be nil at any time"))
	}

	if r.GetBefore() != nil {
		if err := r.GetBefore().Validate(); err != nil {
			return twirp.InvalidArgumentError("reference_update.before", fmt.Sprintf("contains an invalid object id %s", r.GetBefore().GetId()))
		}
	}

	if r.GetAfter() != nil {
		if err := r.GetAfter().Validate(); err != nil {
			return twirp.InvalidArgumentError("reference_update.after", fmt.Sprintf("contains an invalid object id %s", r.GetAfter().GetId()))
		}
	}

	return nil
}
