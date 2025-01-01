// Package migrations provides migrations and transitions.
package migrations

import (
	"github.com/github/turboscan/ts/mysql/upgrades"
)

var Transitions = upgrades.Transitions()
