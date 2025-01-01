package mw

import (
	"bufio"
	"context"
	"errors"
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/logger"
	stats "github.com/github/launch/observability/statter"
)

// MeasureHTTP wraps the http.ResponseWriter with an responseWriter and
// outputs timing stats. It's best if this is the last handler in the chain.
func MeasureHTTP(log logger.Logger, statter stats.Statter) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			ww := newResponseWriter(w)
			t := statter.LegacyTimer() //nolint:staticcheck

			next.ServeHTTP(ww, r)

			finish := time.Now()
			ctx := r.Context()

			if rmd := GetRequestMetadata(ctx); rmd != nil {
				if rmd.ShouldSkipLogging() {
					return
				}
			}

			tags := stats.Tags{"status": strconv.Itoa(ww.StatusCode)}

			t.Log(ctx, finish, "request.time", tags) //nolint:staticcheck

			log.Log(ctx, r.URL.Path,
				kvp.String("http.response.status_code", tags["status"]),
				kvp.Duration("http.server.request.duration", finish.Sub(t.Start())), //nolint:staticcheck
			)
		}
		return http.HandlerFunc(fn)
	}
}

// SkipLogging turns off HTTP request logging for this request.
func SkipLogging(ctx context.Context) {
	if rmd := GetRequestMetadata(ctx); rmd != nil {
		rmd.SkipLogging()
	}
}

// ResponseWriter is an http.ResponseWriter that provides a timestamp for the
// point at which the HTTP headers have been written. This allows the
// calculation of a latency independent of the size of the response body.
type ResponseWriter struct {
	HeaderTime  time.Time
	StatusCode  int
	mu          sync.Mutex
	wroteHeader bool
	w           http.ResponseWriter
}

func newResponseWriter(w http.ResponseWriter) *ResponseWriter {
	return &ResponseWriter{
		w: w,
	}
}

// Header returns the header map that will be sent by WriteHeader.
func (w *ResponseWriter) Header() http.Header {
	return w.w.Header()
}

// WriteHeader sends an HTTP response header with status code.
func (w *ResponseWriter) WriteHeader(code int) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.wroteHeader {
		return
	}
	w.writeHeader(code)
}

// Write writes the data to the connection as part of an HTTP reply.
func (w *ResponseWriter) Write(b []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if !w.wroteHeader {
		w.writeHeader(http.StatusOK)
	}
	return w.w.Write(b)
}

func (w *ResponseWriter) writeHeader(code int) {
	w.wroteHeader = true
	w.w.WriteHeader(code)
	w.HeaderTime = time.Now()
	w.StatusCode = code
}

// Hijack implements the http.Hijacker interface.  This expands
// the Response to fulfill http.Hijacker if the underlying
// http.ResponseWriter supports it.
func (w *ResponseWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	hijacker, ok := w.w.(http.Hijacker)
	if !ok {
		return nil, nil, errors.New("the ResponseWriter doesn't support the Hijacker interface")
	}
	return hijacker.Hijack()
}
