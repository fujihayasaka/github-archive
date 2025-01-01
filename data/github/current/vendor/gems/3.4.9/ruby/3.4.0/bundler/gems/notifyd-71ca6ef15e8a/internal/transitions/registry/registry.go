// Package registry provides a small registry layer for transitions to be
// registered and easily retrieved by a chosen name from the main entrypoint
// of the transition job
package registry

import (
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
	"github.com/github/notifyd/internal/transitions"

	// transitions to register
	t2023_31_12_cleanup_list_subscription_users "github.com/github/notifyd/internal/transitions/t2023-31-12-cleanup-list-subscription-users"
	t2023_02_17_noop_test_transition "github.com/github/notifyd/internal/transitions/t2023_02_17_noop_test_transition"
)

var (
	registeredTransitions = make(map[string]transitions.IBaseTransition)
)

// Get retrieves a transition from the registry with the given name
func Get(name string) (transitions.IBaseTransition, bool) {
	if t, found := registeredTransitions[name]; found {
		return t, true
	}
	return nil, false
}

// Init initializes the registry with all available transitions and the
// provided dependencies
func Init(telem *telemetry.Provider, routingSettingsService routing.SettingsService, subscriptionsService subscriptions.Service) {
	// register all transitions we want to have available
	registeredTransitions["t2023_31_12_cleanup_list_subscription_users"] = t2023_31_12_cleanup_list_subscription_users.NewCleanupListSubscriptions(telem, routingSettingsService, subscriptionsService)
	registeredTransitions["t2023_02_17_noop_test_transition"] = t2023_02_17_noop_test_transition.NewNoopTestTransition(telem, routingSettingsService, subscriptionsService)
}
