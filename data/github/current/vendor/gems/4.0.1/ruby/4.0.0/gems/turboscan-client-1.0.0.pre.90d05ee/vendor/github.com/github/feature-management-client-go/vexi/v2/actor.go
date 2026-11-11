// Package vexi contains all the domain logic of the library.
package vexi

// Actor is an interface that can be implemented on any type to create valid Vexi Actor values out of that object.
type Actor interface {
	VexiID() string
}

// The actor interface for vexi is the format you provide it actors for feature flag checks by actor.
//
// If you have a valid actor as a string (something like User:234234234) you can create the vexi actor with the code
// actor.FromString("User:234234234")
//
// Complex actors can be created using the format
// actor.FromString("Copilot::CopilotApi::IntegrationActor:thingy")

// stringActor is a helper for a default actor based on a string.
type stringActor struct {
	actorValue string
}

// VexiID returns a valid Vexi actor identifier in the format TYPE:VALUE
func (a *stringActor) VexiID() string {
	return a.actorValue
}

// NewActor creates a Vexi Actor based on a string.
func NewActor(id string) Actor {
	return &stringActor{
		actorValue: id,
	}
}
