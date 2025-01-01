package reqmw

import (
	"net/http"
	"testing"

	"github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/pkg/launchhttp"
)

func Test_breakerMiddleware_Do(t *testing.T) {
	tests := []struct {
		name                     string
		open                     bool
		wantIncFail, wantIncSucc bool
		wantErr                  bool
	}{
		{
			name:    "open",
			open:    true,
			wantErr: true,
		},
		{
			name:    "ready",
			open:    false,
			wantErr: false,
		},
		{
			name:        "increments fail",
			wantIncFail: true,
			wantErr:     true,
		},
		{
			name:        "increments success",
			wantIncSucc: true,
			wantErr:     false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			next, breaker := newTestBreaker(t, tt.open, tt.wantIncFail, tt.wantIncSucc)
			middleware := NewBreakerMiddleware(next, breaker)
			req, err := http.NewRequest("GET", "http://localhost", nil)
			if err != nil {
				t.Error(errors.Wrap(err, "could not build request"))
				return
			}
			_, err = middleware.Do(req)
			if !tt.wantErr && err != nil {
				t.Error(errors.Wrap(err, "did not want error"))
				return
			}

			if tt.wantIncFail {
				if breaker.Failures() != 1 {
					t.Errorf("did not increment failure count on failure")
					return
				}
			}

			if tt.wantIncSucc {
				if breaker.Successes() != 1 {
					t.Errorf("did not increment success count on success")
					return
				}
			}
		})
	}
}

func newTestBreaker(t *testing.T, open, incrementFailure, incrementSuccess bool) (launchhttp.RequestMiddleware, *circuit.Breaker) {
	b := circuit.NewBreaker()
	if open {
		b.Break()
	}

	var code int
	var err error
	if incrementFailure {
		code = 500
		err = errors.New("increment failure error")
	}

	if incrementSuccess {
		code = 200
	}

	n := &fakeBreakerMiddleware{
		throw: open,
		t:     t,
		code:  code,
		err:   err,
	}

	return n, b
}

type fakeBreakerMiddleware struct {
	throw bool
	t     *testing.T
	code  int
	err   error
}

func (fbw *fakeBreakerMiddleware) Do(req *http.Request) (*http.Response, error) {
	if fbw.throw {
		fbw.t.Errorf("call not expected")
	}
	return &http.Response{StatusCode: fbw.code}, fbw.err
}
