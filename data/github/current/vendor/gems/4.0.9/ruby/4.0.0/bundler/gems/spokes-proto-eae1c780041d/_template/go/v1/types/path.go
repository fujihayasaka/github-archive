package types

import (
	"bytes"

	"github.com/twitchtv/twirp"
)

func NewPath(name []byte) *Path {
	return &Path{Name: name}
}

func (p *Path) Validate() error {
	if p == nil {
		return nil
	}

	if len(p.GetName()) == 0 {
		return twirp.RequiredArgumentError("path.name")
	}

	if bytes.Contains(p.GetName(), []byte("\x00")) {
		return twirp.InvalidArgumentError("path.name", "may not contain null byte")
	}

	return nil
}
