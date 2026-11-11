// Package main is the entry point for the Twirp testbed application.
//
// TEMPORARY CODE
// This code is a temporary testbed for the Twirp client.
// It will be removed once the Twirp client is fully integrated into the service.
package main

import (
	"context"
	"fmt"
	"math"
	"os"
	"strconv"

	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	sweagentdAPITwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

func main() {
	err := realMain()
	if err != nil {
		fmt.Println("failed to run command:", err)
		os.Exit(1)
	}
}

func realMain() error {
	cfg, err := config.Load()
	if err != nil {
		return goerrors.Errorf("failed to load config: %w", err)
	}

	client, err := githubtwirp.NewClient(cfg.GitHubTwirpAPIURL, cfg.GitHubTwirpHMACKey, cfg.LimiterTwirpAPIURL, cfg.LimiterTwirpHMAC, cfg.LimiterTwirpRequestTimeoutMs, cfg.BillingClientURL, cfg.BillingClientHMACKey, observability.NewNoopExporters(), featureflags.NewNoopClient(nil), nil)
	if err != nil {
		return goerrors.Errorf("failed to create twirp client: %w", err)
	}

	ctx := context.Background()

	githubUserID := os.Getenv("GITHUB_USER_ID")
	githubUserIDInt, err := strconv.ParseUint(githubUserID, 10, 64)
	copilotTrackingID := ""
	if githubUserID != "" && err != nil {
		return goerrors.Errorf("failed to parse GITHUB_USER_ID: %w", err)
	}

	if githubUserIDInt != 0 {
		user, err := client.UserDetailAPI().GetCopilotUser(ctx, &copilotUsersTwirp.GetCopilotUserRequest{
			Id: githubUserIDInt,
		})

		if err != nil {
			return goerrors.Errorf("failed to get copilot user: %w", err)
		}
		copilotTrackingID = user.UserDetails.AnalyticsTrackingId

		fmt.Printf("user analytics tracking id: %v", user.UserDetails.AnalyticsTrackingId)
		fmt.Println()
	}

	githubRepositoryID := os.Getenv("GITHUB_REPOSITORY_ID")
	githubRepositoryIDInt, err := strconv.ParseUint(githubRepositoryID, 10, 64)
	if githubRepositoryID != "" && err != nil {
		return goerrors.Errorf("failed to parse GITHUB_REPOSITORY_ID: %w", err)
	}

	if githubUserIDInt != 0 && githubRepositoryIDInt != 0 {
		if githubRepositoryIDInt > uint64(math.MaxInt64) {
			return goerrors.New("value of GITHUB_REPOSITORY_ID is out of valid int64 range. If this is hit, it's time to change the API")
		}
		foundConfig, err := client.SweagentdAPI().ConfigurationForRepository(ctx, &sweagentdAPITwirp.ConfigurationForRepositoryRequest{
			RepositoryId: int64(githubRepositoryIDInt),
			UserId:       githubUserIDInt,
		})

		if err != nil {
			return goerrors.Errorf("failed to get repository configuration: %w", err)
		}

		fmt.Printf("issweagentd enabled: %v", foundConfig.IsSweagentdEnabled) //nolint:staticcheck // testing code
		fmt.Println()
	}

	if githubUserIDInt != 0 && githubRepositoryIDInt != 0 {
		foundConfig, err := client.SweagentdAPI().MCPConfigurationForRepository(ctx, &sweagentdAPITwirp.MCPConfigurationForRepositoryRequest{
			RepositoryId: githubRepositoryIDInt,
			UserId:       githubUserIDInt,
		})

		if err != nil {
			return goerrors.Errorf("failed to get repository configuration: %w", err)
		}

		fmt.Printf("isMCP enabled: %v", foundConfig.IsMcpEnabled)
		fmt.Println()
		fmt.Println("MCP configuration for repository:")
		fmt.Println(foundConfig.McpConfigurationJson)
		fmt.Println()
	}

	if githubUserIDInt != 0 && githubRepositoryIDInt != 0 {
		foundToken, err := client.SweagentdAPI().MintUserToServerTokenForRepo(ctx, &sweagentdAPITwirp.MintUserToServerTokenForRepoRequest{
			UserId:       githubUserIDInt,
			RepositoryId: githubRepositoryIDInt,
		})

		if err != nil {
			return goerrors.Errorf("failed to mint user to server token for repo: %w", err)
		}

		if foundToken == nil || foundToken.Token == "" {
			return goerrors.New("failed to mint user to server token for repo. token is invalid or empty")
		}

		fmt.Println("successfully minted user to server token for repo")
		fmt.Println()
	}

	if githubUserIDInt != 0 && githubRepositoryIDInt != 0 {
		enterpriseAgents, err := client.SweagentdAPI().EnterpriseAgents(ctx, &sweagentdAPITwirp.EnterpriseAgentsRequest{
			UserId: githubUserIDInt,
			FindAgentsBy: &sweagentdAPITwirp.EnterpriseAgentsRequest_RepositoryId{
				RepositoryId: githubRepositoryIDInt,
			},
		})

		if err != nil {
			return goerrors.Errorf("failed to get enterprise agents: %w", err)
		}

		fmt.Printf("Enterprise agents repository ID: %d\n", enterpriseAgents.RepositoryId)
		fmt.Println()
	}

	if copilotTrackingID != "" {
		quotaRemaining, err := client.LimiterAPI().GetQuotaRemaining(ctx, &copilotLimitersTwirp.GetQuotaRemainingRequest{
			CopilotTrackingId: copilotTrackingID,
		})

		if err != nil {
			return goerrors.Errorf("failed to get quota remaining: %w", err)
		}

		fmt.Printf("quota remaining: %v", quotaRemaining)
		fmt.Println()
	}

	return nil
}
