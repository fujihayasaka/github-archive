package mu

import (
	"context"
	"net"
	"net/http"
	"time"
)

// httpServer is an HTTP server handling requests on a listener with a mux.
type httpServer struct {
	server   *http.Server
	listener net.Listener
}

func newHTTPServer(l net.Listener, mux http.Handler) *httpServer {
	if l == nil {
		return nil
	}

	return &httpServer{
		listener: l,
		server: &http.Server{
			Handler:           mux,
			ReadHeaderTimeout: 3 * time.Second, // Avoids slowloris attacks, gosec #G112 https://github.com/securego/gosec/blob/87cc45e1cd903e2038e868eaf026cbc5d1dd1a26/rules/slowloris.go#L62-L71
		},
	}
}

// Serve starts the server
func (s *httpServer) Serve() error {
	if s == nil {
		return nil
	}

	return s.server.Serve(s.listener)
}

// Shutdown shuts down the server
func (s *httpServer) Shutdown(ctx context.Context) error {
	if s == nil {
		return nil
	}

	return s.server.Shutdown(ctx)
}

func (s *httpServer) Address() string {
	if s == nil {
		return ""
	}

	return s.listener.Addr().String()
}
