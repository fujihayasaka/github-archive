package fault

import (
	"context"
	"errors"
	"net/http"
)

var (
	// ErrNilInjector when a nil Injector is passed.
	ErrNilInjector = errors.New("injector cannot be nil")
)

type Fault struct {
	injector, next  http.RoundTripper
	participateFunc func(context.Context) bool

	// pathBlocklist is a map of paths that the Injector will never run against.
	pathBlocklist map[string]struct{}

	// pathAllowlist, if set, is a map of the only paths that the Injector will run against.
	pathAllowlist map[string]struct{}
}

func WithFilters(pathAllowList, pathBlockList []string) Option {
	return func(f *Fault) {
		pathAllow := make(map[string]struct{})
		pathBlock := make(map[string]struct{})
		for _, path := range pathAllowList {
			pathAllow[path] = struct{}{}
		}
		f.pathAllowlist = pathAllow
		for _, path := range pathBlockList {
			pathBlock[path] = struct{}{}
		}
		f.pathBlocklist = pathBlock
	}
}

type Option func(f *Fault)

func NewFault(nonFault http.RoundTripper, i Injector, opts ...Option) *Fault {
	defaultParticipator := &alwaysParticipate{}
	f := &Fault{
		injector:        i,
		participateFunc: defaultParticipator.Participate,
		next:            nonFault,
	}

	for _, opt := range opts {
		opt(f)
	}

	return f
}

func (f *Fault) RoundTrip(req *http.Request) (*http.Response, error) {
	shouldEvaluate := f.checkFilterLists(req) && f.participateFunc(req.Context())

	if shouldEvaluate {
		return f.injector.RoundTrip(req)
	}

	return f.next.RoundTrip(req)
}

// checkFilterLists checks the request against the provided allowlists and blocklists, returning
// true if the request may proceed and false otherwise.
func (f *Fault) checkFilterLists(r *http.Request) bool {
	_, pathBlocked := f.pathBlocklist[r.URL.Path]
	if pathBlocked {
		return false
	}

	if len(f.pathAllowlist) > 0 {
		_, pathAllowed := f.pathAllowlist[r.URL.Path]
		if !pathAllowed {
			return false
		}
	}

	return true
}
