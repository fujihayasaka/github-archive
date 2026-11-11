package agenticapp

import (
	"context"
	"crypto/rsa"
	"regexp"
	"slices"
	"time"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/golang-jwt/jwt/v4"
	gg "github.com/google/go-github/v75/github"
)

const (
	// CopilotBranchPrefix is the branch prefix for the Copilot agentic app.
	// If a branch with the same name as this prefix exists, Copilot coding agent can't create a new branch with the prefix.
	// There are security implications like only allowing Copilot to push to branches with this prefix.
	// If this constant needs to be changed, ensure the security guardrails are updated too.
	// See https://github.com/github/sweagentd/issues/124 for details.
	CopilotBranchPrefix = "copilot"
)

var backtickContentPattern = regexp.MustCompile("```[\\s\\S]*?```|`[^`]*`")

// Copilot represents a GitHub Copilot Agentic App.
type Copilot struct {
	id                       int64
	name                     string
	privateKey               *rsa.PrivateKey
	clientID, clientSecret   string
	botID                    int64
	botLogin                 string
	commitLogin, commitEmail string
	logins                   []string
	mentionRegexp            *regexp.Regexp
	mentionableSlug          string
}

// NewCopilotFromConfig creates a new Copilot instance from the given configuration.
func NewCopilotFromConfig(cfg *config.Config) (*Copilot, error) {
	return NewCopilotWithPEM(
		cfg.GitHubAppID,
		cfg.GitHubAppPrivateKey,
		cfg.GitHubAppLogin,
		cfg.GitHubAppBotID,
		cfg.GitHubBotLogin,
		cfg.GitHubCommitLogin,
		cfg.GitHubCommitEmail,
		cfg.GitHubAppClientID,
		cfg.GitHubAppClientSecret,
	)
}

// NewCopilotWithPEM creates a new Copilot instance with a PEM-encoded private key.
func NewCopilotWithPEM(id int64, privateKeyPEM, appLogin string, botID int64, botLogin, commitLogin, commitEmail, clientID, clientSecret string) (*Copilot, error) {
	// Parse the private key
	pk, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(privateKeyPEM))
	if err != nil {
		return nil, goerrors.Errorf("failed to parse private key: %w", err)
	}

	return NewCopilot(id, pk, appLogin, botID, botLogin, commitLogin, commitEmail, clientID, clientSecret), nil
}

// NewCopilot creates a new Copilot instance.
func NewCopilot(id int64, pk *rsa.PrivateKey, appLogin string, botID int64, botLogin, commitLogin, commitEmail, clientID, clientSecret string) *Copilot {
	logins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
		"Copilot",
	}

	name := "Copilot coding agent"
	mentionableSlug := "copilot"
	mentionRegexp := regexp.MustCompile(`(?i)(?:^|\s|\W)@` + mentionableSlug + `\b`)

	return &Copilot{
		id:              id,
		name:            name,
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
	}
}

// MentionableSlug returns the mentionable slug for the Copilot app.
func (c *Copilot) MentionableSlug() string {
	return c.mentionableSlug
}

// AppID returns the App ID of the agent.
func (c *Copilot) AppID() int64 {
	return c.id
}

// AppName returns the GitHub App name of the agent.
func (c *Copilot) AppName() string {
	return c.name
}

// BranchPrefix returns the branch prefix for the agent.
func (c *Copilot) BranchPrefix() string {
	return CopilotBranchPrefix
}

// BotID returns the Bot ID of the agent.
func (c *Copilot) BotID() int64 {
	return c.botID
}

// PrivateKey returns the RSA private key for the Copilot instance.
func (c *Copilot) PrivateKey() *rsa.PrivateKey {
	return c.privateKey
}

// BotLogin returns the bot login name for the Copilot instance.
func (c *Copilot) BotLogin() string {
	return c.botLogin
}

// CommitLogin returns the commit login name for the Copilot instance.
func (c *Copilot) CommitLogin() string {
	return c.commitLogin
}

// CommitEmail returns the commit email address for the Copilot instance.
func (c *Copilot) CommitEmail() string {
	return c.commitEmail
}

// ClientID returns the OAuth client ID for the Copilot instance.
func (c *Copilot) ClientID() string {
	return c.clientID
}

// ClientSecret returns the OAuth client secret for the Copilot instance.
func (c *Copilot) ClientSecret() string {
	return c.clientSecret
}

// MintToken creates a global access token for GitHub Copilot.
func (c *Copilot) MintToken(ctx context.Context, client *gg.Client, tokenReq sweagentd.AgenticAppMintTokenRequest) (string, time.Time, *gg.Response, error) {
	req, err := client.NewRequest("POST", "/app/global/access_tokens", tokenReq)
	if err != nil {
		return "", time.Time{}, nil, err
	}

	// Response schema https://github.com/github/github/blob/72e8ed1f089d2e3f87bdf17b2ec9198d7b423623/app/api/serializer/integrations_dependency.rb#L51-L54
	var tokenResp struct {
		Token     string    `json:"token"`
		ExpiresAt time.Time `json:"expires_at"`
	}
	resp, err := client.Do(ctx, req, &tokenResp)
	if err != nil {
		return "", time.Time{}, resp, goerrors.Errorf("failed to create global app token: %w", err)
	}
	if tokenResp.Token == "" {
		return "", time.Time{}, resp, goerrors.New("failed to create global app token: empty token")
	}

	return tokenResp.Token, tokenResp.ExpiresAt, resp, nil
}

// RevokeToken revokes the given installation or user-to-server token.
func (c *Copilot) RevokeToken(ctx context.Context, api sweagentd.GitHubAPI, token string) error {
	return revokeToken(ctx, api, c, token)
}

// SetupCompute configures the compute environment with the Copilot runtime entry point.
func (c *Copilot) SetupCompute(compute sweagentd.ComputeEnv) {
	compute.EntryPoint("dist/index.js")
}

// ComputeSlug returns the slug used in compute environments.
func (c *Copilot) ComputeSlug() string {
	return "copilot"
}

func (c *Copilot) hasLogin(login string) bool {
	return slices.Contains(c.logins, login)
}

func (c *Copilot) isMentioned(body string) bool {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := backtickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @copilot mention exists in the remaining text
	return c.mentionRegexp.MatchString(bodyWithoutBackticks)
}

// MentionWithModelPattern matches @copilot+model-id patterns.
// It captures the model ID after the + sign.
var mentionWithModelPattern = regexp.MustCompile(`(?i)(?:^|\s|\W)@copilot\+([a-zA-Z0-9._-]+)(?:\s|$|[^\w+-])`)

// isMentionedWithModel checks if the body contains a @copilot+model mention
// and returns the model ID if found.
func (c *Copilot) isMentionedWithModel(body string) (string, bool) {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := backtickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @copilot+model mention exists in the remaining text
	matches := mentionWithModelPattern.FindStringSubmatch(bodyWithoutBackticks)
	if len(matches) >= 2 {
		return matches[1], true
	}

	return "", false
}
