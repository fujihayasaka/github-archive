package github

import (
	"crypto/rsa"
	"fmt"

	"github.com/github/sweagentd/internal/config"
	"github.com/golang-jwt/jwt/v4"
)

type GitHubApp struct {
	ID           int64
	PrivateKey   *rsa.PrivateKey
	ClientID     string
	ClientSecret string // Needed for revoking user tokens
	AppLogin     string
	BotLogin     string
}

func NewAppFromConfig(cfg *config.Config) (*GitHubApp, error) {
	// Parse the private key
	pk, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(cfg.GitHubAppPrivateKey))
	if err != nil {
		return nil, fmt.Errorf("failed to parse private key: %w", err)
	}

	return &GitHubApp{
		ID:           cfg.GitHubAppID,
		PrivateKey:   pk,
		ClientID:     cfg.GitHubAppClientID,
		ClientSecret: cfg.GitHubAppClientSecret,
		AppLogin:     cfg.GitHubAppLogin,
		BotLogin:     cfg.GitHubBotLogin,
	}, nil
}
