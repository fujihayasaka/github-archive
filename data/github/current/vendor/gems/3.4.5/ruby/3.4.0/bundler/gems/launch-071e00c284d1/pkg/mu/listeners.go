package mu

import (
	"context"
	"crypto/tls"
	"errors"
	"net"

	"github.com/soheilhy/cmux"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/mu/muhttp"
)

type listeners struct {
	muxedListener    net.Listener
	httpListener     net.Listener
	internalListener net.Listener
	mux              cmux.CMux
}

func setupListeners(cfg *Config, log logger.Logger) (*listeners, error) {
	l := &listeners{}

	if !cfg.hasHTTPAddrConfigured() {
		return nil, errors.New("HTTPAddr is required")
	}

	if cfg.hasHTTPAddrConfigured() && l.httpListener == nil {
		httpLis, err := muhttp.NewListener(cfg.HTTPAddr)
		if err != nil {
			return nil, err
		}

		if cfg.HTTPTLSConfig != nil {
			httpLis = tls.NewListener(httpLis, cfg.HTTPTLSConfig)
		}
		l.httpListener = httpLis
	}

	if cfg.InternalAddr == cfg.HTTPAddr || !cfg.hasInternalAddrConfigured() {
		// Don't create a separate internal listener if the addresses match
		// or if it's not configured.
		return l, nil
	}

	il, err := muhttp.NewListener(cfg.InternalAddr)
	if err != nil {
		// not fatal, but complain:
		log.Report(context.Background(), err)
	}
	l.internalListener = il

	return l, nil
}

func (l *listeners) Serve() error {
	if l.mux == nil {
		return nil
	}

	return l.mux.Serve()
}

func (l *listeners) Shutdown() error {
	// Only close the muxedListener if present. The other listeners are closed by
	// their own protocol shutdown procedures.
	if l.muxedListener != nil {
		return l.muxedListener.Close()
	}

	return nil
}
