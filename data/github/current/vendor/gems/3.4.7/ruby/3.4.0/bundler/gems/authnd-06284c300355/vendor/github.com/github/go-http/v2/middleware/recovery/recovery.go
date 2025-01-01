// Package recovery provides middleware that recovers from panics, logs the panic (and a backtrace), and returns a HTTP 500 (Internal Server Error) status if possible.
package recovery

import (
	"fmt"
	"net/http"
	"runtime/debug"
)

// Recovery is a middleware that handles panics during the normal request
// lifecycle and returns a 500 error code if possible. An optional callback is
// provided to report the panic.
type Recovery struct {
	// Response is an optional callback that will create the response for the caller.
	// It is only called in the case where the middleware recovers from a panic.
	// If this is not set, a 500 response with an empty body is returned.
	Response func(err error, rw http.ResponseWriter, r *http.Request)

	// Report is a callback that will receive the rescued panic, wrapped as an
	// error. It should ideally return right away.
	Report func(err error, req *http.Request) error
}

// Handler allows manual chaining of this middleware.
func (rec *Recovery) Handler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				var wrap error
				stack := string(debug.Stack())
				if realErr, ok := err.(error); ok {
					wrap = fmt.Errorf("panic: %w\nstacktrace:\n%s", realErr, stack)
				} else {
					wrap = fmt.Errorf("panic: %v\nstacktrace:\n%s", err, stack)
				}

				if rec.Report != nil {
					_ = rec.Report(wrap, r)
				}

				if rec.Response == nil {
					defaultResponse(wrap, rw, r)
				} else {
					rec.Response(wrap, rw, r)
				}
			}
		}()

		next.ServeHTTP(rw, r)
	})
}

func defaultResponse(err error, rw http.ResponseWriter, r *http.Request) {
	if rw.Header().Get("Content-Type") == "" {
		rw.Header().Set("Content-Type", "text/plain; charset=utf-8")
	}

	rw.WriteHeader(http.StatusInternalServerError)
}
