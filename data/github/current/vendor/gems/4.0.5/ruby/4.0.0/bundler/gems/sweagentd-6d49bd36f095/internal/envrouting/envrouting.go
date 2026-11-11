// Package envrouting gates event processing by environment using routing feature flags.
// All environments share Hydro/CosmosDB; without gating, each processes every event independently.
package envrouting

import (
	"context"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/sweagentd"
)

const (
	flagRouteToStaging    = "sweagentd_route_user_or_repo_to_staging"
	flagRouteToJediKnight = "sweagentd_route_user_or_repo_to_staging_jedi_knight"
	flagRouteToSithLord   = "sweagentd_route_user_or_repo_to_staging_sith_lord"
	flagRouteToBabyYoda   = "sweagentd_route_user_or_repo_to_staging_baby_yoda"
)

// FeatureFlags is the subset of featureflags.Client needed for routing checks.
type FeatureFlags interface {
	IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool
}

// Router checks staging routing FFs to determine which environment owns an event.
type Router struct {
	ffClient        FeatureFlags
	environment     config.Environment
	environmentName string
}

// NewRouter creates a Router for the given environment.
func NewRouter(ffClient FeatureFlags, environment config.Environment, environmentName string) *Router {
	return &Router{
		ffClient:        ffClient,
		environment:     environment,
		environmentName: environmentName,
	}
}

// routingActors implements sweagentd.RepositoryWithActor for routing FF checks.
type routingActors struct {
	actorID int64
	repoID  int64
	ownerID int64
}

func (a *routingActors) GetActorID() int64      { return a.actorID }
func (a *routingActors) GetRepositoryID() int64 { return a.repoID }
func (a *routingActors) GetOwnerID() int64      { return a.ownerID }

// ShouldProcess returns true if this environment should handle an event for the
// given actor/repo/owner.
func (r *Router) ShouldProcess(ctx context.Context, actorID, repoID, ownerID int64) bool {
	actors := &routingActors{actorID: actorID, repoID: repoID, ownerID: ownerID}
	routeToStaging := r.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, flagRouteToStaging, actors)
	routeToJediKnight := r.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, flagRouteToJediKnight, actors)
	routeToSithLord := r.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, flagRouteToSithLord, actors)
	routeToBabyYoda := r.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, flagRouteToBabyYoda, actors)
	shouldRoute := routeToStaging || routeToJediKnight || routeToSithLord || routeToBabyYoda

	if r.environment == config.EnvironmentStaging && !shouldRoute {
		return false
	}

	if r.environment != config.EnvironmentStaging && shouldRoute {
		return false
	}

	if r.environment == config.EnvironmentStaging && shouldRoute {
		target := ""
		switch {
		case routeToStaging:
			target = "staging"
		case routeToJediKnight:
			target = "staging-jedi-knight"
		case routeToSithLord:
			target = "staging-sith-lord"
		case routeToBabyYoda:
			target = "staging-baby-yoda"
		default:
		}
		return r.environmentName == target
	}

	return true
}
