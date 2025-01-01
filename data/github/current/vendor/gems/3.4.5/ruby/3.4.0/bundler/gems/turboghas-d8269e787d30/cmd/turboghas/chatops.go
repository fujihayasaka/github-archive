// chatops.go provides Hubot commands for TurboGHAS.
package main

import (
	"context"
	"crypto/x509"
	"encoding/pem"
	"net/http"

	"github.com/github/go-auth/hmac"
	"github.com/github/go-crpc/v2"
	"github.com/github/turboghas/cmd/turboghas/configuration"
	"github.com/pkg/errors"
)

// Make sure to add new chatops to this list
func defaultChatops(cfg *configuration.Configuration) []crpc.Chatop {
	return []crpc.Chatop{
		pingChatop(),
		hmacChatop(cfg),
	}
}

func NewChatopsHandler(cfg *configuration.Configuration) (http.Handler, error) {
	ns := crpc.NewNamespace("tg")
	ns.Help = "Chatops for the Advanced Security Billing service (turboghas)"

	for _, chatop := range defaultChatops(cfg) {
		_, err := ns.Register(chatop)
		if err != nil {
			return nil, err
		}
	}

	handler, err := crpc.NewHandler(ns, cfg.ChatopsBaseURL)
	if err != nil {
		return nil, err
	}

	if cfg.ChatopsBotPublicKey != "" {
		block, _ := pem.Decode([]byte(cfg.ChatopsBotPublicKey))
		if block == nil {
			return nil, errors.New("pem decoding failed")
		}

		botKey, err := x509.ParsePKCS1PublicKey(block.Bytes)
		if err != nil {
			return nil, err
		}
		handler.AddBot(botKey)
	}

	return handler, nil
}

func pingChatop() *crpc.GenericChatop {
	return crpc.NewGenericChatop(
		"ping",
		"ping - get a pong back from turboghas",
		"ping",
		func(ctx context.Context, req *crpc.CommandRequest) (*crpc.CommandResponse, error) {
			return &crpc.CommandResponse{
				Result: "pong",
			}, nil
		},
	)
}

func hmacChatop(cfg *configuration.Configuration) *crpc.GenericChatop {
	return crpc.NewGenericChatop(
		"hmac",
		"hmac - get an HMAC token for turboghas",
		"hmac",
		func(ctx context.Context, req *crpc.CommandRequest) (*crpc.CommandResponse, error) {
			if len(cfg.HMACKeys) == 0 {
				return nil, errors.New("no hmac key set")
			}
			return &crpc.CommandResponse{
				Result: hmac.NewRequestHMAC(cfg.HMACKeys[0]).String(),
			}, nil
		},
	)
}
