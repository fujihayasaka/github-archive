// Package suggested_fixes provides the resolver for the github.turboscan.SuggestedFixes Twirp endpoint.
package suggested_fixes

import (
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/sarif/store"
	"github.com/github/turboscan/ts/suggestedfixes"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

type Service struct {
	sf         *suggestedfixes.SuggestedFixes
	sarifStore store.SarifStore
	aqueduct   aqueduct.JobPerformer
	es         *elasticsearch.Service
}

func New(sf *suggestedfixes.SuggestedFixes, store store.SarifStore, jobs aqueduct.JobPerformer, es *elasticsearch.Service) *Service {
	return &Service{
		sf:         sf,
		sarifStore: store,
		aqueduct:   jobs,
		es:         es,
	}
}
