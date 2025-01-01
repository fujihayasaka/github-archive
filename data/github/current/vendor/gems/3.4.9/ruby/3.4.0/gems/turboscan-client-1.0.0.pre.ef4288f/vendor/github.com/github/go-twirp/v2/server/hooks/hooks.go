// Package hooks provides recommended Twirp hooks.
package hooks

import "github.com/twitchtv/twirp"

// DefaultHooks provides a recommended set of twirp.ServerHooks from the hooks package that should
// be included in the chain for a service.
func DefaultHooks() *twirp.ServerHooks {
	return twirp.ChainHooks(
		TimingHooks(),
		StoreTwirpErrorHooks(),
		TracingHooks(),
	)
}
