package tokenauth

import (
	"strings"

	"github.com/golang-jwt/jwt/v4"

	"github.com/github/launch/types"
)

const (
	scopeDelimiter      = " " // separates scopes e.g. "LocationService.Connect Actions.Runner:123:456"
	scopePartsDelimiter = ":" // separates parts of a scope e.g. "Actions.Runner:123:456"
)

type runnerClaims struct {
	OrchestrationId string         `json:"orch_id"`
	Scopes          string         `json:"scp"`
	RunnerType      string         `json:"runner_type"`
	OwnerID         types.GlobalID `json:"owner_id"`
	jwt.RegisteredClaims
}

func (r *runnerClaims) containsScopeValue(targetScope, targetValue string) bool {
	scopeList := strings.Split(r.Scopes, scopeDelimiter)
	for _, scope := range scopeList {
		name, val := scopeNameAndValue(scope)
		if name == targetScope && val == targetValue {
			return true
		}
	}

	return false
}

func scopeNameAndValue(scope string) (string, string) {
	scopeParts := strings.SplitN(scope, scopePartsDelimiter, 2) // Actions.Runner:123:456 -> ["Actions.Runner", "123:456"]
	scopeName := ""
	scopeValue := ""

	if len(scopeParts) == 2 {
		scopeName = scopeParts[0]
		scopeValue = scopeParts[1]
	} else if len(scopeParts) == 1 {
		scopeName = scopeParts[0]
	}

	return scopeName, scopeValue
}
