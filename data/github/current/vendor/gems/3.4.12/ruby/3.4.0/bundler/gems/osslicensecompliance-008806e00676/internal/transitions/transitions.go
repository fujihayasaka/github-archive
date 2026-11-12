// Package transitions provides the code which performs data transitions.
package transitions

import "github.com/github/osslicensecompliance/internal/application"

// Transition is the function that can perform a specific transition.
type Transition func(app *application.Application, args []string) error

func check(app *application.Application, args []string) error {
	app.Logger.Info("transitions can run")
	return nil
}

// GetTransitions returns the available transitions.
func GetTransitions() map[string]Transition {
	return map[string]Transition{
		"check": check,
	}
}
