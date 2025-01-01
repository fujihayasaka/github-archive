package mu

import (
	"crypto/rsa"

	chatops "github.com/github/go-chatops/v2"
	"github.com/go-chi/chi"
)

type chatopsConfig struct {
	Name          string
	AuthBaseURL   string
	AuthPublicKey *rsa.PublicKey
	Mux           chi.Router
}

type chatopsService struct {
	handler *chatops.Handler
	ns      *chatops.Namespace
}

func newChatopsService(cfg *chatopsConfig) (*chatopsService, error) {
	ns := chatops.NewNamespace(cfg.Name)

	ch, err := chatops.NewHandler(ns, cfg.AuthBaseURL)
	if err != nil {
		return nil, err
	}

	ch.AddBot(cfg.AuthPublicKey)
	ch.Setup(cfg.Mux)

	return &chatopsService{
		handler: ch,
		ns:      ns,
	}, nil
}

// Register registers a chantops handler
func (s *chatopsService) Register(name, help, regex string, handler chatops.CommandFunc) error {
	if s == nil {
		return nil
	}

	h, err := s.ns.Add(name)
	if err != nil {
		return err
	}
	h.Help = help
	h.Regex = regex
	h.On(handler)

	return nil
}
