package server

import (
	"fmt"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/kube"
)

// BuildHTTPMux creates HTTP Mux with default endpoints
func buildHTTPMux(config env.Config) http.Handler {
	mux := chi.NewRouter()
	mux.Mount("/debug", middleware.Profiler())
	mux.HandleFunc("/ready", kube.Ready(config))

	return mux
}

func New(config env.Config) *http.Server {
	return &http.Server{
		Addr:    fmt.Sprintf(":%d", config.GetHTTPPort()),
		Handler: buildHTTPMux(config),
	}
}
