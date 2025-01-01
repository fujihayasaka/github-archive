package fault

import "net/http"

// InjectorState represents the states an injector can be in.
type InjectorState int

const (
	// StateStarted when an Injector has started.
	StateStarted InjectorState = iota + 1
	// StateFinished when an Injector has finished.
	StateFinished
)

type Injector interface {
	RoundTrip(*http.Request) (*http.Response, error)
	chain(http.RoundTripper) Injector
}

func ChainInjectors(nonFault http.RoundTripper, injectors ...Injector) Injector {
	if len(injectors) == 0 {
		panic("cannot chain zero length injector")
	}

	chained := injectors[0]
	for _, i := range injectors {
		chained = i.chain(nonFault)
	}
	return chained
}
