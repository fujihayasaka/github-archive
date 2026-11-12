package sweagentd

import (
	"context"
	"crypto/rsa"
	"time"

	gg "github.com/google/go-github/v75/github"
)

// AgenticAppMintTokenRequest represents a request to mint a token for an agentic app.
type AgenticAppMintTokenRequest struct {
	Target        string   `json:"target,omitempty"`
	TargetID      int64    `json:"target_id,omitempty"`
	RepositoryIDs []int64  `json:"repository_ids,omitempty"`
	Repositories  []string `json:"repositories,omitempty"`
}

// ComputeEnv represents the compute environment for an agent.
type ComputeEnv interface {
	// SetupAgent prepares the compute environment for the agent.
	// The cmd parameter specifies the command to execute for setting up the agent.
	SetupAgent(cmd string)

	// EntryPoint defines the entry point for the agent in the compute environment.
	// The cmd parameter represents the path or command to the entry point to be executed.
	EntryPoint(cmd string)
}

// AgenticApp represents a GitHub App that manages an agent.
//
//nolint:interfacebloat // agents get bloated sometimes
type AgenticApp interface {
	AppID() int64
	AppName() string
	BranchPrefix() string
	PrivateKey() *rsa.PrivateKey
	ClientID() string
	ClientSecret() string
	BotID() int64
	BotLogin() string
	CommitLogin() string
	CommitEmail() string
	MentionableSlug() string
	ComputeSlug() string

	MintToken(ctx context.Context, client *gg.Client, tokenReq AgenticAppMintTokenRequest) (string, time.Time, *gg.Response, error)
	RevokeToken(ctx context.Context, api GitHubAPI, token string) error
	SetupCompute(compute ComputeEnv)
}
