package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewRevisionSelector(revs ...*types.Revision) *RevisionSelector {
	return &RevisionSelector{Revisions: revs}
}

func (r *RevisionSelector) Validate() error {
	if r == nil {
		return nil
	}

	if len(r.GetRevisions()) == 0 {
		return twirp.RequiredArgumentError("revisions")
	}

	for _, rev := range r.GetRevisions() {
		if err := rev.Validate(); err != nil {
			return err
		}
	}

	return nil
}
