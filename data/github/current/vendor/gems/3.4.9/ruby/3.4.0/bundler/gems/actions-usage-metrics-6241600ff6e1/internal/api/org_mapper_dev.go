//go:build dev

package api

import (
	"strconv"
	"strings"

	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

func setMappedScope(scope *proto.Scope, kustoCfg config.KustoConfig) {
	// this is only compiled for dev (skaffold) builds
	if kustoCfg.IsDev {
		if scope.GetScopeType() == proto.ScopeType_SCOPE_TYPE_ENTERPRISE {
			newEnterpriseOrgs := []int64{9919, 33435682} //github and bbq-beets

			if scope.EnterpriseOrgs != nil && len(scope.GetEnterpriseOrgs()) > 0 {
				scope.EnterpriseOrgs = newEnterpriseOrgs // hardcode repos to github/github in dev
			}
		} else {
			for _, mapping := range kustoCfg.KustoDevOrgsMapping {
				split := strings.Split(mapping, ":")

				if len(split) == 2 {
					oldId, err1 := strconv.Atoi(split[0])
					newId, err2 := strconv.Atoi(split[1])

					if err1 != nil || err2 != nil {
						continue
					} else if int64(oldId) == *scope.OwnerId {
						newId64 := int64(newId)
						newRepoId64 := int64(3)
						scope.OwnerId = &newId64

						if scope.RepositoryId != nil {
							scope.RepositoryId = &newRepoId64 // hardcode repos to github/github in dev
						}

						log.Info("Mapping org for dev", kvp.Int("old_org", oldId), kvp.Int("new_org", newId))
						break
					}
				}

			}
		}

	}
}
