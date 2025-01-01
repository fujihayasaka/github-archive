// Package chatopsserver constructs a Chatops server
package chatopsserver

import (
	"crypto/x509"
	"encoding/pem"
	"errors"
	"net/http"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-chatops/v2"
	"github.com/github/go-http/v2/middleware/requestid"
)

// NewChatopsServer creates a new Chatops server
func NewChatopsServer(chatops http.Handler) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("/", chatops)
	handler := secureHeadersHandler(mux)
	handler = requestid.Handler(handler)

	return handler
}

// SecureHeadersMiddleware unconditionally adds "Strict-Transport-Security",
// "Content-Security-Policy" headers to all responses.
func secureHeadersHandler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(rw http.ResponseWriter, req *http.Request) {
		rw.Header().Set("Strict-Transport-Security", "max-age=31536000")
		rw.Header().Set("Content-Security-Policy", "default-src 'none'; sandbox")
		next.ServeHTTP(rw, req)
	})
}

// NewChatopsHandler creates a handler for the service
func NewChatopsHandler(cfg Config, telem *telemetry.Provider, ops []chatops.Chatop) (http.Handler, error) {
	ns := chatops.NewNamespace("notifyd")
	ns.Help = "Chatops for the Notifyd service"

	// first of all, check if the public key is set
	// TODO(abeaumont): if the server is optional, make it more explicit.
	if cfg.BotPublicKey == "" {
		return nil, errors.New("CHATOPS_BOT_PUBLIC_KEY is empty")
	}

	for _, chatop := range ops {
		_, err := ns.Register(chatop)
		if err != nil {
			return nil, err
		}
	}

	handler, err := chatops.NewHandler(ns, cfg.BaseURL)
	if err != nil {
		return nil, err
	}

	block, _ := pem.Decode([]byte(cfg.BotPublicKey))
	if block == nil {
		return nil, errors.New("pem decoding failed")
	}

	botKey, err := x509.ParsePKCS1PublicKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	handler.AddBot(botKey)

	return handler, nil
}
