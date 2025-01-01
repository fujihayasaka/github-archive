package selectors

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewRevisionAndPathSelector(revision *types.Revision, path *types.Path) *RevisionAndPathSelector {
	return &RevisionAndPathSelector{Revision: revision, Path: path}
}

func (r *RevisionAndPathSelector) Validate() error {
	if r == nil {
		return nil
	}

	rev := r.GetRevision()
	if rev == nil {
		return twirp.RequiredArgumentError("revision")
	}
	if err := rev.Validate(); err != nil {
		return err
	}

	p := r.GetPath()
	if p == nil {
		return twirp.RequiredArgumentError("path")
	}
	if err := p.Validate(); err != nil {
		return err
	}

	return nil
}
