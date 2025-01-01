package httpserver

import (
	"context"
	"fmt"
	"net/http"
	"os"

	"github.com/github/github-telemetry-go/log"
)

type HttpServer struct {
	Server *http.Server
}

func NewHttpServer(port int, handler http.Handler) *HttpServer {
	server := &HttpServer{
		Server: &http.Server{
			Addr:    fmt.Sprintf(":%d", port),
			Handler: handler,
		},
	}
	return server
}
func (s *HttpServer) Run() {
	err := s.Server.ListenAndServe()
	if err != nil && err != http.ErrServerClosed {
		log.WithError(err).Error("unexpected server error, aborting")
		os.Exit(1)
	}
}

func (s *HttpServer) Shutdown(ctx context.Context) error {
	// attempt graceful shutdown, but fallback to aborting connections if needed
	logger := log.WithContext(ctx)
	err := s.Server.Shutdown(ctx)
	logger.WithError(err).Error("failed to shutdown http server")
	err = s.Server.Close()
	if err != nil {
		logger.WithError(err).Error("failed to force shutdown server")
	}
	return err
}
