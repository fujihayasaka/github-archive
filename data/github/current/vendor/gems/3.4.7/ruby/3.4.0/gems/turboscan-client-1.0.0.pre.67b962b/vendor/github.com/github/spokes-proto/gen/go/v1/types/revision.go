package types

import (
	"github.com/twitchtv/twirp"
)

func NewRevision(name []byte) *Revision {
	return &Revision{Name: name}
}

func (r *Revision) Validate() error {
	if r == nil {
		return nil
	}

	name := r.GetName()

	if len(name) == 0 {
		return twirp.RequiredArgumentError("revision.name")
	}

	return nil
}
