package types

import (
	"strings"

	"github.com/twitchtv/twirp"
)

func NewRepository(id uint64) *Repository {
	return &Repository{
		Type: Repository_TYPE_REPOSITORY,
		Id:   id,
	}
}

func NewWiki(id uint64) *Repository {
	return &Repository{
		Type: Repository_TYPE_WIKI,
		Id:   id,
	}
}

func NewGist(id uint64) *Repository {
	return &Repository{
		Type: Repository_TYPE_GIST,
		Id:   id,
	}
}

func (r *Repository) Validate() error {
	if r == nil {
		return nil
	}

	if r.GetId() == 0 {
		return twirp.RequiredArgumentError("repository.id")
	}

	if r.GetType() == Repository_TYPE_INVALID {
		return twirp.InvalidArgumentError("repository.type", "type must be set")
	}

	if !strings.HasPrefix(r.GetType().String(), "TYPE_") {
		return twirp.InvalidArgumentError("repository.type", "type must be repository, wiki or gist")
	}

	return nil
}
