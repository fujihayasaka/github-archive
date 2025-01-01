package launchcache

import (
	"context"
	"time"

	"github.com/github/launch/types"
)

type Cache interface {
	AzureProvider() AZPCache
	S2SProvider() S2SCache
	GitHub() GitHubCache
	GitHubTwirp() GitHubTwirpCache
	LaunchDependency() LaunchDependencyCache
	HealingJob() HealingJobCache
	Transitions() TransitionsCache
}

type AZPCache interface {
	BearerTokenCacheFor(requestURL string, clientID string, resource string) AZPBearerTokenCache
	S2SAccessTokenCacheFor(clientID string) AZPS2SAccessTokenCache
}

type AZPBearerTokenCache interface {
	Get(ctx context.Context) ([]byte, time.Time, bool, error)
	Set(ctx context.Context, token []byte, expiresIn time.Duration) error
}

type AZPS2SAccessTokenCache interface {
	Get(ctx context.Context) ([]byte, time.Time, bool, error)
	Set(ctx context.Context, token []byte, expiresIn time.Duration) error
}

type S2SCache interface {
	KeyVaultCacheFor(vaultName, secretName string) KeyVaultCache
}

type KeyVaultCache interface {
	Get(ctx context.Context) ([]byte, bool, error)
	Set(ctx context.Context, token []byte, expiresIn time.Duration) error
}

type GitHubCache interface {
	SiteScopedTokenCacheFor(appID, ownerID int64, reqBody []byte) SiteScopedTokenCache
}

type GitHubInstallationTokenCache interface {
	Get(ctx context.Context) ([]byte, bool, error)
	Set(ctx context.Context, token []byte, expiresIn time.Duration) error
}

type SiteScopedTokenCache interface {
	Get(ctx context.Context) ([]byte, bool, error)
	Set(ctx context.Context, token []byte, expiresIn time.Duration) error
}

type ScopedInstallationTokenCache interface {
	Get(ctx context.Context) ([]byte, bool, error)
	Set(ctx context.Context, token []byte, expiresIn time.Duration) error
}

type GitHubTwirpCache interface {
	RepoCanUseActionsCacheFor(repoID types.GlobalID) GitHubRepoCanUseActionsCache
	FeatureFlagCacheFor(gid types.GlobalID, featureFlag string) GitHubFeatureFlagCache
	FeatureFlagActorCacheFor(actor, featureFlag string) GitHubFeatureFlagCache
	RepoOrOwnersFeatureFlagCacheFor(repoGID types.GlobalID, featureFlag string) GitHubFeatureFlagCache
	TrustTierCacheFor(id types.GlobalID) GitHubTrustTierCache
	RepositoryCacheFor(tenant int64, nwo string) GitHubRepositoryCache
	GlobalIDCacheFor(legacyGID string) GitHubGlobalIDCache
	RepoAccountDetailsCacheFor(repoGID types.GlobalID) GitHubRepositoryAccountDetailsCache
	RepositoryOwnerIDCacheFor(repoID int64) GitHubRepositoryOwnerIDCache
	UserByLoginCacheFor(login string, tenant int64) GitHubUserByLoginCache
	RepositoryVisibilityCacheFor(repoID int64) GetRepositoryVisibilityCache
}

type GitHubRepoCanUseActionsCache interface {
	Get(ctx context.Context) ([]byte, bool, error)
	Set(ctx context.Context, token []byte, expiresIn time.Duration) error
}

type GitHubFeatureFlagCache interface {
	Get(ctx context.Context) ([]byte, bool, error)
	Set(ctx context.Context, token []byte, expiresIn time.Duration) error
}

type GitHubRepoOrOwnersFeatureFlagCache interface {
	Get(ctx context.Context) ([]byte, bool, error)
	Set(ctx context.Context, token []byte, expiresIn time.Duration) error
}

type GitHubRepositoryTierCache interface {
	Get(ctx context.Context) (types.RepositoryTier, bool, error)
	Set(ctx context.Context, tier types.RepositoryTier, expiresIn time.Duration) error
}

type GitHubTrustTierCache interface {
	Get(ctx context.Context) (int64, bool, error)
	Set(ctx context.Context, tier int64, expiresIn time.Duration) error
}

type GitHubUserByLoginCache interface {
	Get(ctx context.Context) ([]byte, bool, error)
	Set(ctx context.Context, token []byte, expiresIn time.Duration) error
}

type GitHubRepositoryAccountDetailsCache interface {
	Get(ctx context.Context) ([]byte, bool, error)
	Set(ctx context.Context, tier []byte, expiresIn time.Duration) error
}

type GitHubRepositoryOwnerIDCache interface {
	Get(ctx context.Context) (int64, bool, error)
	Set(ctx context.Context, ownerID int64, expiresIn time.Duration) error
}

type GitHubRepositoryCache interface {
	Get(ctx context.Context) ([]byte, bool, error)
	Set(ctx context.Context, repository []byte, expiresIn time.Duration) error
}

type GitHubGlobalIDCache interface {
	Get(ctx context.Context) (types.GlobalID, bool, error)
	Set(ctx context.Context, nextGlobalID types.GlobalID, expiresIn time.Duration) error
}

type LaunchDependencyCache interface {
	AqueductQueueDepthCacheFor(queueName string) AqueductQueueDepthCache
}

type AqueductQueueDepthCache interface {
	Get(ctx context.Context) (int64, bool, error)
	Set(ctx context.Context, value int64, expiresIn time.Duration) error
}

type HealingJobCache interface {
	SkipWorkflowExecutionIDFor(workflowExecutionID int64) SkipWorkflowExecutionIDCache
}

type SkipWorkflowExecutionIDCache interface {
	Get(ctx context.Context) (string, bool, error)
	Set(ctx context.Context, value string, expiresIn time.Duration) error
}

type TransitionsCache interface {
	CacheFor(transitionName string) LaunchTransitionsCache
}

type LaunchTransitionsCache interface {
	Get(ctx context.Context) (int64, bool, error)
	Set(ctx context.Context, rowID int64, expiresIn time.Duration) error
}

type GetRepositoryVisibilityCache interface {
	Get(ctx context.Context) (int32, bool, error)
	Set(ctx context.Context, repoVisibility int32, expiresIn time.Duration) error
}
