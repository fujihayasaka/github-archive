package reqmw

import (
	"net/http"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/pkg/launchhttp"
)

type breakerMiddleware struct {
	next    launchhttp.RequestMiddleware
	breaker *circuit.Breaker
}

// NewBreakerMiddleware returns a new RequestMiddleware that adds a circuit breaker to the chain
func NewBreakerMiddleware(next launchhttp.RequestMiddleware, breaker *circuit.Breaker) launchhttp.RequestMiddleware {
	return &breakerMiddleware{
		next:    next,
		breaker: breaker,
	}
}

func (b *breakerMiddleware) Do(req *http.Request) (*http.Response, error) {
	if b.breaker == nil {
		return b.next.Do(req)
	}

	if !b.breaker.Ready() {
		return nil, circuit.ErrBreakerOpen
	}

	resp, err := b.next.Do(req)

	if err != nil || resp.StatusCode >= 500 {
		b.breaker.Fail()
	} else {
		b.breaker.Success()
	}

	return resp, err
}
