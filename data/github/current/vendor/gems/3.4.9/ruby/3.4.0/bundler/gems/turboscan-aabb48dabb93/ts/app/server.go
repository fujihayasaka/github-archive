package app

import (
	"context"
	"net"
	"net/http"
	"slices"
	"time"

	"github.com/github/go-ctxutil"
)

const LongerTimeout = 60 * time.Second

// SpecialTimeoutHandler is used for defining paths that need longer timeouts
var SpecialTimeoutHandler = &lth{}

type lth struct {
	Paths []string
}

func (l *lth) Handler(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		if slices.Contains(l.Paths, r.URL.Path) {
			rc := http.NewResponseController(w) //nolint:bodyclose
			_ = rc.SetWriteDeadline(time.Now().Add(LongerTimeout))
		}
		next.ServeHTTP(w, r)
	}

	return http.HandlerFunc(fn)
}

// HTTPServer is a wrapper around http.Server that implements the Handler interface
type HTTPServer struct {
	srv *http.Server
}

var _ Server = (*HTTPServer)(nil)

func NewHTTPServer(ctx context.Context, addr string, h http.Handler) *HTTPServer {
	server := &http.Server{
		BaseContext: func(listener net.Listener) context.Context {
			return ctxutil.DetachedCancel(ctx)
		},
		Addr:              addr,
		Handler:           h,
		ReadTimeout:       5 * time.Second,
		ReadHeaderTimeout: 5 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	return &HTTPServer{srv: server}
}

func (h *HTTPServer) Start(ctx context.Context) error {
	ctx, cancel := context.WithCancelCause(ctx)
	go func() {
		if err := h.srv.ListenAndServe(); err != nil {
			cancel(err)
		}
	}()
	<-ctx.Done()
	return context.Cause(ctx)
}

func (h *HTTPServer) Stop(ctx context.Context) error {
	return h.srv.Shutdown(ctx)
}
