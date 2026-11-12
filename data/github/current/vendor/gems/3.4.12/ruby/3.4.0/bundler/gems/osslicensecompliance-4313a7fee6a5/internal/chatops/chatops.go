// Package chatops contains osscompliance's chatops
package chatops

import (
	"context"
	"crypto/rsa"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/github/go-auth/hmac"
	"github.com/github/go-chatops/v2"
)

const (
	// ServiceName is the name of the service.
	ServiceName = "osscompliance"
	// Namespace is a namespace.
	Namespace = "oss"
	// NamespaceHelp is helpful.
	NamespaceHelp = "see a osscompliance docs"
)

// Chatops contains information necessary to do chatops.
type Chatops struct {
	AuthBaseURL      string
	HTTPAddr         string
	HealthHTTPAddr   string
	AuthPublicKey    []byte
	AuthAltPublicKey []byte
	Namespace        string
	HMACSecret       string
}

// HealthServer contains info about the health of a server.
type HealthServer struct {
	handler      http.Handler
	addr         string
	readTimeout  time.Duration
	writeTimeout time.Duration
}

// Run helps us startup the NewHealthServer.
func (s *HealthServer) Run() {
	fmt.Printf("Starting health server... %s\n", s.addr)
	server := &http.Server{
		Addr:         s.addr,
		Handler:      s.handler,
		ReadTimeout:  s.readTimeout,
		WriteTimeout: s.writeTimeout,
	}

	if err := server.ListenAndServe(); err != nil {
		panic(fmt.Errorf("failed to start health server: %w", err))
	}
}

// NewHealthServer helps us setup a new ping listener for k8s readyness probes
// the method is unprotected from signature verification but has miniscul security
// risk because it's used as an internal service problem for the service itself.
// For this reason it will listen on a separate port than the chatops service
// from the same binary.
func NewHealthServer(mux *http.ServeMux, addr string, readTimeout, writeTimeout time.Duration) *HealthServer {
	mux.HandleFunc("/_ping", func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, http.StatusText(http.StatusOK), http.StatusOK)
	})

	return &HealthServer{
		handler:      mux,
		addr:         addr,
		readTimeout:  readTimeout,
		writeTimeout: writeTimeout,
	}
}

const readTimeout = 5 * time.Second
const writeTimeout = 10 * time.Second

// ListenAndServe starts a chatops server.
func (c *Chatops) ListenAndServe() error {
	handler, err := c.NewChatopsHandler()
	if err != nil {
		return err
	}
	mux := http.NewServeMux()
	handler.Setup(mux)

	// handle k8s readiness probes
	healthServer := NewHealthServer(mux, c.HealthHTTPAddr, readTimeout, writeTimeout)
	go func() {
		healthServer.Run()
	}()

	fmt.Printf("Starting chatops service... %s\n", c.AuthBaseURL)
	server := &http.Server{
		Addr:         c.HTTPAddr,
		Handler:      handler,
		ReadTimeout:  readTimeout,
		WriteTimeout: writeTimeout,
	}
	return server.ListenAndServe()
}

// Make sure to add new chatops to this list.
func defaultChatops(hmacSecret string) []chatops.Chatop {
	return []chatops.Chatop{
		pingChatop(),
		hmacChatop(hmacSecret),
	}
}

// NewChatopsHandler is the constructor for chatops.Handler.
func (c *Chatops) NewChatopsHandler() (*chatops.Handler, error) {
	ns, err := NewNamespaceHandler(c.Namespace)
	if err != nil {
		return nil, fmt.Errorf("couldn't create namespace: %w", err)
	}

	for _, chatop := range defaultChatops(c.HMACSecret) {
		_, err := ns.Register(chatop)
		if err != nil {
			return nil, err
		}
	}

	handler, err := chatops.NewHandler(ns, c.AuthBaseURL)
	if err != nil {
		return nil, fmt.Errorf("couldn't build handler: %w", err)
	}

	validKeys, err := c.authKey(c.AuthPublicKey, c.AuthAltPublicKey)
	if err != nil {
		return nil, fmt.Errorf("couldn't decode auth key: %w", err)
	}

	fmt.Printf("No of valid keys: %d\n", len(validKeys))

	for _, key := range validKeys {
		handler.AddBot(key)
	}

	return handler, nil
}

// NewNamespaceHandler is a constructor for chatops.Namespace.
func NewNamespaceHandler(name string) (*chatops.Namespace, error) {
	ns := chatops.NewNamespace(name)
	ns.Help = NamespaceHelp

	lm, err := ns.Add("link")
	if err != nil {
		return nil, errors.New(`error from ns.Add("link")`)
	}
	lm.Help = "link to godoc"
	return ns, nil
}

func (c *Chatops) authKey(primaryKey, alternateKey []byte) ([]*rsa.PublicKey, error) {
	var validKeys []*rsa.PublicKey

	if len(primaryKey) != 0 {
		key, err := chatops.ReadPEMPublicKey(primaryKey)
		if err != nil {
			fmt.Printf("skipped using `CHATOPS_AUTH_PUBLIC_KEY`") // should use logger
		} else {
			validKeys = append(validKeys, key)
		}
	}

	if len(alternateKey) != 0 {
		key, err := chatops.ReadPEMPublicKey(alternateKey)
		if err != nil {
			fmt.Printf("skipped using `CHATOPS_AUTH_ALT_PUBLIC_KEY`") // should use logger
		} else {
			validKeys = append(validKeys, key)
		}
	}

	if len(validKeys) == 0 {
		return validKeys, errors.New("no auth keys setup")
	}

	return validKeys, nil
}

// Chatops ping command.
func pingChatop() *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"ping",
		"hubot ping - get a pong back from "+ServiceName,
		"ping",
		func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
			return &chatops.CommandResponse{
				Result: "pong",
			}, nil
		},
	)
}

// Chatops hmac command.
func hmacChatop(hmacSecret string) *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"hmac",
		"hubot hmac - get an HMAC token for "+ServiceName,
		"hmac",
		func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
			hmac := hmac.NewRequestHMAC(hmacSecret)
			return &chatops.CommandResponse{
				Result: hmac.String(),
			}, nil
		},
	)
}
