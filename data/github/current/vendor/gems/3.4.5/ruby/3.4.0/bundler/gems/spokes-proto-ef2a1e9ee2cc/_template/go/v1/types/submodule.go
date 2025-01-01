package types

import "github.com/twitchtv/twirp"

func NewSubmodule(path *Path, oid *ObjectID, name string, url string) *Submodule {
	return &Submodule{
		Path: path,
		Oid:  oid,
		Name: name,
		Url:  url,
	}
}

func (s *Submodule) Validate() error {
	if s == nil {
		return nil
	}

	if s.GetPath() == nil {
		return twirp.RequiredArgumentError("submodule.path")
	}

	if err := s.GetPath().Validate(); err != nil {
		return err
	}

	if s.GetOid() == nil {
		return twirp.RequiredArgumentError("submodule.oid")
	}

	if err := s.GetOid().Validate(); err != nil {
		return err
	}

	return nil
}
