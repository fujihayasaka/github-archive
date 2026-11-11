// Package varfetcher provides an abstracted function interface to
// provide a mechanism to fetch the values of COPILOT_MCP_-prefixed variables
// from a source (e.g. GitHub or local .env file).
package varfetcher

import (
	"context"
	"os"
	"strings"
	"sync"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/joho/godotenv"
)

// VariableFetcher fetches the values of the named COPILOT_MCP_-prefixed
// variables, handling any concurrent API calls internally. It receives the
// agentic app and repository ID so it can authenticate as the correct
// GitHub App installation when fetching variable values.
type VariableFetcher func(ctx context.Context, app sweagentd.AgenticApp, repoID int64, names []string) (map[string]string, error)

// NewGitHubVariableFetcher returns a VariableFetcher that resolves
// COPILOT_MCP_-prefixed variable values from the GitHub agent variables API.
// It creates a GitHub client per-request using the app installation credentials
// and fetches all requested variables concurrently (max 8 at a time).
// TODO (chuxel): Switch this over to a twirp endpoint that can get all vars at once.
func NewGitHubVariableFetcher(cpf github.ClientFactoryInterface, ghTwirp githubtwirp.ClientInterface) VariableFetcher {
	return func(ctx context.Context, app sweagentd.AgenticApp, repoID int64, names []string) (map[string]string, error) {
		if len(names) == 0 {
			return nil, nil
		}

		// Cached info, so won't result in multiple hits
		repoInfo, err := ghTwirp.GetInstallationInfo(ctx, app.AppID(), repoID)
		if err != nil {
			return nil, goerrors.Errorf("failed to get installation info for variable fetching: %w", err)
		}

		gh, err := cpf.NewClientFromRepo(ctx, app, repoID, repoInfo.OwnerID)
		if err != nil {
			return nil, goerrors.Errorf("failed to create GitHub client for variable fetching: %w", err)
		}

		isOrg := repoInfo.OwnerType == sweagentd.OwnerTypeOrganization
		owner := repoInfo.OwnerLogin
		repo := repoInfo.Name

		result := make(map[string]string, len(names))
		var mu sync.Mutex

		// Process in chunks of 8 for bounded concurrency.
		for i := 0; i < len(names); i += 8 {
			end := min(i+8, len(names))
			chunk := names[i:end]

			var wg sync.WaitGroup
			errs := make([]error, len(chunk))

			for j, name := range chunk {
				idx := j
				n := name
				wg.Go(func() {
					val, fetchErr := gh.GetAgentVariableValue(ctx, owner, repo, n, isOrg)
					if fetchErr != nil {
						errs[idx] = goerrors.Errorf("failed to fetch variable %q: %w", n, fetchErr)
						return
					}
					if val == "" {
						return
					}
					mu.Lock()
					result[n] = val
					mu.Unlock()
				})
			}
			wg.Wait()

			for _, chunkErr := range errs {
				if chunkErr != nil {
					return nil, goerrors.Errorf("failed to fetch variable value: %w", chunkErr)
				}
			}
		}

		return result, nil
	}
}

const mcpDevEnvFile = ".env.mcp-dev"

// NewEnvVariableFetcher returns a VariableFetcher that resolves
// COPILOT_MCP_-prefixed variable values from a local .env.mcp-dev file
func NewEnvVariableFetcher() VariableFetcher {
	return func(ctx context.Context, app sweagentd.AgenticApp, repoID int64, names []string) (map[string]string, error) {
		envMap, err := godotenv.Read(mcpDevEnvFile)
		if os.IsNotExist(err) {
			return map[string]string{}, nil
		}
		if err != nil {
			return nil, goerrors.Errorf("reading %s: %w", mcpDevEnvFile, err)
		}

		result := make(map[string]string, len(names))
		for _, name := range names {
			if val, ok := envMap[name]; ok {
				if strings.HasPrefix(name, "COPILOT_MCP_") {
					result[name] = val
				}
			}
		}

		return result, nil
	}
}
