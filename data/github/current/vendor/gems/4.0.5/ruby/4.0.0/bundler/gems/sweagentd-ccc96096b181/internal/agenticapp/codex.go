package agenticapp

import (
	"context"
	"crypto/rsa"
	"regexp"
	"slices"
	"time"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/golang-jwt/jwt/v4"

	gg "github.com/google/go-github/v75/github"
)

const (
	// CodexBranchPrefix is the branch prefix for the Codex agentic app.
	CodexBranchPrefix = "codex"
	// CodexAppName is the name of the Codex agentic app - will ultimately be the actual App name.
	CodexAppName = "OpenAI Codex"
)

// Codex represents the Codex GitHub App with its configuration and credentials.
type Codex struct {
	id                       int64
	name                     string
	privateKey               *rsa.PrivateKey
	clientID, clientSecret   string
	botID                    int64
	botLogin                 string
	commitLogin, commitEmail string
	logins                   []string
	mentionableSlug          string
	mentionRegexp            *regexp.Regexp

	ghtwirp githubtwirp.ClientInterface
}

// NewCodexFromConfig creates a new Codex instance from the provided configuration.
func NewCodexFromConfig(cfg *config.Config, ght githubtwirp.ClientInterface) (*Codex, error) {
	return NewCodexWithPEM(
		cfg.CodexGitHubAppID,
		cfg.CodexGitHubAppPrivateKey,
		cfg.CodexGitHubAppLogin,
		cfg.CodexGitHubAppBotID,
		cfg.CodexGitHubBotLogin,
		cfg.CodexGitHubCommitLogin,
		cfg.CodexGitHubCommitEmail,
		cfg.CodexGitHubAppClientID,
		cfg.CodexGitHubAppClientSecret,
		ght,
	)
}

// NewCodexWithPEM creates a new Codex instance with the given PEM-encoded private key.
func NewCodexWithPEM(id int64, privateKeyPEM, appLogin string, botID int64, botLogin, commitLogin, commitEmail, clientID, clientSecret string, ght githubtwirp.ClientInterface) (*Codex, error) {
	// Parse the private key
	pk, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(privateKeyPEM))
	if err != nil {
		return nil, goerrors.Errorf("failed to parse private key: %w", err)
	}

	return NewCodex(id, pk, appLogin, botID, botLogin, commitLogin, commitEmail, clientID, clientSecret, ght), nil
}

// NewCodex creates a new Codex instance with the given RSA private key.
func NewCodex(id int64, pk *rsa.PrivateKey, appLogin string, botID int64, botLogin, commitLogin, commitEmail, clientID, clientSecret string, ght githubtwirp.ClientInterface) *Codex {
	logins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}

	mentionableSlug := "codex[agent]"
	mentionRegexp := regexp.MustCompile(`(?i)(?:^|\s|\W)@` + regexp.QuoteMeta(mentionableSlug) + `(?:\s|\W|$)`)

	return &Codex{
		id:              id,
		name:            CodexAppName,
		privateKey:      pk,
		botID:           botID,
		botLogin:        botLogin,
		commitLogin:     commitLogin,
		commitEmail:     commitEmail,
		clientID:        clientID,
		clientSecret:    clientSecret,
		logins:          logins,
		mentionableSlug: mentionableSlug,
		mentionRegexp:   mentionRegexp,

		ghtwirp: ght,
	}
}

// MentionableSlug returns the mentionable slug for the Codex app.
func (c *Codex) MentionableSlug() string {
	return c.mentionableSlug
}

// AppID returns the App ID of the agent.
func (c *Codex) AppID() int64 {
	return c.id
}

// AppName returns the GitHub App name of the agent.
func (c *Codex) AppName() string {
	return c.name
}

// BranchPrefix returns the branch prefix for the agent.
func (c *Codex) BranchPrefix() string {
	return CodexBranchPrefix
}

// PrivateKey returns the RSA private key for the Codex instance.
func (c *Codex) PrivateKey() *rsa.PrivateKey {
	return c.privateKey
}

// BotID returns the Bot ID of the agent.
func (c *Codex) BotID() int64 {
	return c.botID
}

// BotLogin returns the bot login name for the Codex instance.
func (c *Codex) BotLogin() string {
	return c.botLogin
}

// CommitLogin returns the commit login name for the Codex instance.
func (c *Codex) CommitLogin() string {
	return c.commitLogin
}

// CommitEmail returns the commit email address for the Codex instance.
func (c *Codex) CommitEmail() string {
	return c.commitEmail
}

// ClientID returns the OAuth client ID for the Codex instance.
func (c *Codex) ClientID() string {
	return c.clientID
}

// ClientSecret returns the OAuth client secret for the Codex instance.
func (c *Codex) ClientSecret() string {
	return c.clientSecret
}

// MintToken creates an installation access token for the given repository.
func (c *Codex) MintToken(ctx context.Context, client *gg.Client, tokenReq sweagentd.AgenticAppMintTokenRequest) (string, time.Time, *gg.Response, error) {
	return mintToken(ctx, c.ghtwirp, client, tokenReq)
}

// RevokeToken revokes the given installation or user-to-server token.
func (c *Codex) RevokeToken(ctx context.Context, api sweagentd.GitHubAPI, token string) error {
	return revokeToken(ctx, api, c, token)
}

// SetupCompute configures the compute environment with the Codex agent setup and runtime entry point.
func (c *Codex) SetupCompute(compute sweagentd.ComputeEnv) {
	compute.SetupAgent("npm install -g @openai/codex@0.66.0")
	compute.EntryPoint("dist-codex/index.js")
}

// ComputeSlug returns the slug used in compute environments.
func (c *Codex) ComputeSlug() string {
	return "codex"
}

func (c *Codex) hasLogin(login string) bool {
	return slices.Contains(c.logins, login)
}

func (c *Codex) isMentioned(body string) bool {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := backtickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @codex[agent] mention exists in the remaining text
	return c.mentionRegexp.MatchString(bodyWithoutBackticks)
}
