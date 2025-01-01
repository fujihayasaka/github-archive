package mw

import (
	"fmt"
	"net/http"
	"runtime/debug"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/logger"
)

// OMG recovers from any panics, sending them to the logs and haystack,
// responding with a 500 error code.
func OMG(log logger.Logger) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if rvr := recover(); rvr != nil {
					var err error
					if e, ok := rvr.(error); ok {
						err = e
					} else {
						err = fmt.Errorf("%v", rvr)
					}

					ctx := r.Context()
					log.Log(ctx, err.Error())
					log.Report(ctx, err, kvp.String("exception_detail", string(debug.Stack())))

					http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
				}
			}()

			next.ServeHTTP(w, r)
		}

		return http.HandlerFunc(fn)
	}
}
