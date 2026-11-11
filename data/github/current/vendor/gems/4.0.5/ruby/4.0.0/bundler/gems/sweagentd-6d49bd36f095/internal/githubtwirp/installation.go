package githubtwirp

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	v1 "github.com/github/sweagentd/proto/sweagentd/v1"
)

const (
	installationCacheKeyPrefix = "githubtwirp:get_repository_installation:"
	installationCacheTTL       = 60 * time.Minute
)

// InstallationInfo holds the subset of repository installation data needed for OIDC token exchange.
type InstallationInfo struct {
	ID                int64               `json:"id"`
	Name              string              `json:"name"`
	OwnerID           int64               `json:"owner_id"`
	OwnerLogin        string              `json:"owner_login"`
	OwnerType         sweagentd.OwnerType `json:"owner_type"`
	AppClientID       string              `json:"app_client_id"`
	AppIsGlobal       bool                `json:"app_is_global"`
	AppInstallationID int64               `json:"app_installation_id"`
	// Permissions is the GitHub App installation's permissions on the
	// repository (e.g., "contents": "write"). May be empty if the dotcom
	// handler has not yet been updated to populate it.
	Permissions map[string]string `json:"permissions,omitempty"`
}

// installationCacheKey generates a cache key for a repository installation lookup.
// Includes tenant ID to prevent cross-tenant cache collisions.
func installationCacheKey(ctx context.Context, appID, repoID int64) string {
	tenantID := requestctx.TenantID(ctx)
	if tenantID == "" {
		tenantID = "no-tenant"
	}
	return fmt.Sprintf("%s%d:%s:%d", installationCacheKeyPrefix, appID, tenantID, repoID)
}

// GetInstallationPermissions fetches the GitHub App installation's permissions on the
// repository, bypassing the InstallationInfo cache to avoid serving stale authorization
// data after the App's permissions have changed on dotcom. Returns a possibly-empty map
// of permission name (e.g., "contents") to access level (e.g., "write").
func (c *Client) GetInstallationPermissions(ctx context.Context, appID, repoID int64) (map[string]string, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "githubtwirp.Client.GetInstallationPermissions")
	defer span.End()

	fetchCtx, endFetchSpan := c.startFetchSubspanIfEnabled(ctx, "githubtwirp.Client.GetInstallationPermissions.fetch")
	resp, err := c.sweagentdAPI.GetRepositoryInstallation(fetchCtx, &v1.GetRepositoryInstallationRequest{
		AgentId:      appID,
		RepositoryId: uint64(repoID),
	})
	endFetchSpan()
	if err != nil {
		return nil, goerrors.Errorf("failed to get repository installation permissions: %w", err)
	}

	return resp.GetPermissions(), nil
}

// GetInstallationInfo fetches the repository installation info needed for token exchange, using the cache.
func (c *Client) GetInstallationInfo(ctx context.Context, appID, repoID int64) (*InstallationInfo, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "githubtwirp.Client.GetInstallationInfo")
	defer span.End()

	key := installationCacheKey(ctx, appID, repoID)

	if c.cacheStore != nil {
		if cached, ok := c.cacheStore.Get(key); ok && cached != "" {
			var info InstallationInfo
			err := json.Unmarshal([]byte(cached), &info)
			if err == nil {
				return &info, nil
			}
		}
	}

	fetchCtx, endFetchSpan := c.startFetchSubspanIfEnabled(ctx, "githubtwirp.Client.GetInstallationInfo.fetch")
	resp, err := c.sweagentdAPI.GetRepositoryInstallation(fetchCtx, &v1.GetRepositoryInstallationRequest{
		AgentId:      appID,
		RepositoryId: uint64(repoID),
	})
	endFetchSpan()
	if err != nil {
		return nil, goerrors.Errorf("failed to get repository installation: %w", err)
	}

	ownerType := sweagentd.OwnerTypeOrganization
	if resp.OwnerType != v1.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_ORGANIZATION {
		ownerType = sweagentd.OwnerTypeUser
	}

	result := &InstallationInfo{
		ID:                repoID,
		Name:              resp.RepoName,
		OwnerID:           int64(resp.OwnerId),
		OwnerLogin:        resp.OwnerLogin,
		OwnerType:         ownerType,
		AppClientID:       resp.ClientId,
		AppIsGlobal:       resp.IsGlobal,
		AppInstallationID: resp.InstallationId,
		Permissions:       resp.GetPermissions(),
	}

	if c.cacheStore != nil {
		marshaled, err := json.Marshal(result)
		if err == nil {
			c.cacheStore.Set(key, string(marshaled), installationCacheTTL)
		}
	}

	return result, nil
}
