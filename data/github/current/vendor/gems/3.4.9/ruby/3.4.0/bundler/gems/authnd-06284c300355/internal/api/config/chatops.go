package config

import (
	"context"
	"crypto/rsa"
	"crypto/x509"
	"net/http"
	"os"
	"path"

	"github.com/pkg/errors"

	"github.com/github/authnd/internal/common/clients"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/go-auth/hmac"
	"github.com/github/go-chatops/v2"
	"github.com/github/go-chatops/v2/chatops/pprof"
	"github.com/github/go-chatops/v2/security"
)

func readDevChatopsKey() (*rsa.PublicKey, error) {
	baseDir := os.Getenv("HOME")
	if baseDir == "" {
		return nil, errors.New("could not identify HOME directory")
	}

	publicKeyFile := path.Join(baseDir, ".authnd", "chatops.development.public.pem")
	bytes, err := os.ReadFile(publicKeyFile)
	if err != nil {
		return nil, errors.Wrapf(err, "error reading private key '%s'", publicKeyFile)
	}

	var parsedKey interface{}
	parsedKey, err = x509.ParsePKCS1PublicKey(bytes)
	if err != nil {
		return nil, errors.Wrapf(err, "error reading private key '%s'", publicKeyFile)
	}
	return parsedKey.(*rsa.PublicKey), nil
}

// newChatopsHandler returns a new http.Handler for authnd chat operations
func newChatopsHandler(namespace string, chatopsBaseURL string, fidoURL string, securityConfig string, publicKey *rsa.PublicKey, manualKey *rsa.PublicKey, HMACKey string, chatterbox clients.ChatterboxClient, disabledFIDO bool) (http.Handler, error) {
	ns := chatops.NewNamespace(namespace)
	ns.Help = "Chatops for the authnd service"

	validator := &security.Validator{}
	if !disabledFIDO {
		securityConfig, err := security.LoadSecurityConfig(securityConfig)
		if err != nil {
			return nil, errors.Wrapf(err, "error loading security config")
		}
		validator = &security.Validator{
			Config: *securityConfig,
			Auth: security.NewFidoAuthChallengerClient(
				http.DefaultClient,
				fidoURL,
				security.WithTimeout(30), // seconds
			),
		}
	}

	chatopsArray := []chatops.Chatop{
		pprof.ProfileChatop(),
		createPingChatop(chatterbox),
		createHMACChatop(HMACKey),
	}
	for _, chatop := range chatopsArray {
		c := newAuthorizedChatop(validator, chatterbox, chatop)
		_, err := ns.Register(c)
		if err != nil {
			return nil, errors.Wrapf(err, "error registering chatop '%s'", chatop.Name())
		}
	}

	handler, err := chatops.NewHandler(ns, chatopsBaseURL)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	if publicKey != nil {
		handler.AddBot(publicKey)
	}

	if manualKey != nil {
		handler.AddBot(manualKey)
	}

	return handler, nil
}

func createPingChatop(chatter clients.ChatterboxClient) *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"ping",
		"hubot authnd ping - get a pong back from authnd service",
		"ping",
		func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
			diagnostics.Logger(ctx).Info("Pong from logs")
			chatter.PostMessageToSlack(ctx, "Pong from Chatterbox")
			return &chatops.CommandResponse{
				Result: "pong",
			}, nil
		},
	)
}

func createHMACChatop(hmacKey string) *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"hmac",
		"hubot authnd hmac - get an HMAC token for authnd service",
		"hmac",
		func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
			if hmacKey == "" {
				return nil, errors.New("HMAC key not configured")
			}

			hmac := hmac.NewRequestHMAC(hmacKey)
			return &chatops.CommandResponse{
				Result: hmac.String(),
			}, nil
		},
	)
}

type authorizedChatop struct {
	chatops.Chatop
	validator *security.Validator
	prompter  security.Prompter
}

func newAuthorizedChatop(v *security.Validator, p security.Prompter, c chatops.Chatop) chatops.Chatop {
	return &authorizedChatop{
		Chatop:    c,
		validator: v,
		prompter:  p,
	}
}

func (co *authorizedChatop) Handle(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	ctx = clients.WithChatRoom(ctx, req.RoomID)
	do := security.WrapWithAuthorization(co.validator, co.prompter, co.Chatop.Handle)
	return do(ctx, req)
}
