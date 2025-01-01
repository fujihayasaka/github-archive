// Package resync contains methods to keep the TurboGHAS cache of monolith data up-to-date.
package resync

import (
	"github.com/github/turboghas/internal/data"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
)

type Sync struct {
	githubAPI twirpTurboghas.TurboghasAPI
	db        *data.Data
}

func New(db *data.Data, githubAPI twirpTurboghas.TurboghasAPI) *Sync {
	return &Sync{
		githubAPI: githubAPI,
		db:        db,
	}
}
