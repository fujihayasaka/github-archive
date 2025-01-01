// Package chatops provides Hubot commands for Turboscan.
package chatops

import (
	"context"
	"crypto/x509"
	"encoding/pem"
	"net/http"

	"github.com/github/go-auth/hmac"
	"github.com/github/go-crpc/v2"
	"github.com/github/go-crpc/v2/chatops/pprof"
	"github.com/github/turboscan/ts/config"

	"github.com/pkg/errors"
)

// Make sure to add new chatops to this list
func defaultChatops(cfg *config.Config) []crpc.Chatop {
	return []crpc.Chatop{
		pingChatop(),
		hmacChatop(cfg),
		pprof.ProfileChatop(),
	}
}

func NewChatopsHandler(cfg *config.Config) (http.Handler, error) {
	ns := crpc.NewNamespace("ts")
	ns.Help = "Chatops for the turboscan service"

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
		"ping - get a pong back from turboscan",
		"ping",
		func(ctx context.Context, req *crpc.CommandRequest) (*crpc.CommandResponse, error) {
			return &crpc.CommandResponse{
				Result: "pong",
			}, nil
		},
	)
}

func hmacChatop(cfg *config.Config) *crpc.GenericChatop {
	return crpc.NewGenericChatop(
		"hmac",
		"hmac - get an HMAC token for turboscan",
		"hmac",
		func(ctx context.Context, req *crpc.CommandRequest) (*crpc.CommandResponse, error) {
			hmac := hmac.NewRequestHMAC(cfg.ValidHMACs()[0])
			return &crpc.CommandResponse{
				Result: hmac.String(),
			}, nil
		},
	)
}
