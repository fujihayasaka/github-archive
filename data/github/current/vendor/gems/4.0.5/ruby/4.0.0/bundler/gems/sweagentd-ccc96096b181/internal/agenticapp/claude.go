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
	// ClaudeBranchPrefix is the branch prefix for the Claude agentic app.
	ClaudeBranchPrefix = "claude"
	// ClaudeCodeAppName is the name of the Claude app - will ultimately be the actual App name.
	ClaudeCodeAppName = "Claude"
)

// Claude represents the Claude GitHub App with its configuration and credentials.
type Claude struct {
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

// NewClaudeFromConfig creates a new Claude instance from the provided configuration.
func NewClaudeFromConfig(cfg *config.Config, ght githubtwirp.ClientInterface) (*Claude, error) {
	return NewClaudeWithPEM(
		cfg.ClaudeGitHubAppID,
		cfg.ClaudeGitHubAppPrivateKey,
		cfg.ClaudeGitHubAppLogin,
		cfg.ClaudeGitHubBotID,
		cfg.ClaudeGitHubBotLogin,
		cfg.ClaudeGitHubCommitLogin,
		cfg.ClaudeGitHubCommitEmail,
		cfg.ClaudeGitHubAppClientID,
		cfg.ClaudeGitHubAppClientSecret,
		ght,
	)
}

// NewClaudeWithPEM creates a new Claude instance with the given PEM-encoded private key.
func NewClaudeWithPEM(id int64, privateKeyPEM, appLogin string, botID int64, botLogin, commitLogin, commitEmail, clientID, clientSecret string, ght githubtwirp.ClientInterface) (*Claude, error) {
	// Parse the private key
	pk, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(privateKeyPEM))
	if err != nil {
		return nil, goerrors.Errorf("failed to parse private key: %w", err)
	}

	return NewClaude(id, pk, appLogin, botID, botLogin, commitLogin, commitEmail, clientID, clientSecret, ght), nil
}

// NewClaude creates a new Claude instance with the given RSA private key.
func NewClaude(id int64, pk *rsa.PrivateKey, appLogin string, botID int64, botLogin, commitLogin, commitEmail, clientID, clientSecret string, ght githubtwirp.ClientInterface) *Claude {
	logins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}

	mentionableSlug := "claude[agent]"
	mentionPattern := `(?i)(?:^|\s|\W)@` + regexp.QuoteMeta(mentionableSlug) + `(?:\s|\W|$)`
	mentionRegexp := regexp.MustCompile(mentionPattern)

	return &Claude{
		id:              id,
		name:            ClaudeCodeAppName,
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

// MentionableSlug returns the mentionable slug for the Claude app.
func (c *Claude) MentionableSlug() string {
	return c.mentionableSlug
}

// AppID returns the App ID of the agent.
func (c *Claude) AppID() int64 {
	return c.id
}

// AppName returns the GitHub App name of the agent.
func (c *Claude) AppName() string {
	return c.name
}

// BranchPrefix returns the branch prefix for the agent.
func (c *Claude) BranchPrefix() string {
	return ClaudeBranchPrefix
}

// PrivateKey returns the RSA private key for the Claude instance.
func (c *Claude) PrivateKey() *rsa.PrivateKey {
	return c.privateKey
}

// BotID returns the bot ID for the Claude instance.
func (c *Claude) BotID() int64 {
	return c.botID
}

// BotLogin returns the bot login name for the Claude instance.
func (c *Claude) BotLogin() string {
	return c.botLogin
}

// CommitLogin returns the commit login name for the Claude instance.
func (c *Claude) CommitLogin() string {
	return c.commitLogin
}

// CommitEmail returns the commit email address for the Claude instance.
func (c *Claude) CommitEmail() string {
	return c.commitEmail
}

// ClientID returns the OAuth client ID for the Claude instance.
func (c *Claude) ClientID() string {
	return c.clientID
}

// ClientSecret returns the OAuth client secret for the Claude instance.
func (c *Claude) ClientSecret() string {
	return c.clientSecret
}

// MintToken creates an installation access token for the given repository.
func (c *Claude) MintToken(ctx context.Context, client *gg.Client, tokenReq sweagentd.AgenticAppMintTokenRequest) (string, time.Time, *gg.Response, error) {
	return mintToken(ctx, c.ghtwirp, client, tokenReq)
}

// RevokeToken revokes the given installation or user-to-server token.
func (c *Claude) RevokeToken(ctx context.Context, api sweagentd.GitHubAPI, token string) error {
	return revokeToken(ctx, api, c, token)
}

// SetupCompute configures the compute environment with the Claude agent setup and runtime entry point.
func (c *Claude) SetupCompute(compute sweagentd.ComputeEnv) {
	compute.EntryPoint("dist-claude/index.js")
}

// ComputeSlug returns the slug used in compute environments.
func (c *Claude) ComputeSlug() string {
	return "claude"
}

func (c *Claude) hasLogin(login string) bool {
	return slices.Contains(c.logins, login)
}

func (c *Claude) isMentioned(body string) bool {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := backtickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @claude[agent] mention exists in the remaining text
	return c.mentionRegexp.MatchString(bodyWithoutBackticks)
}
