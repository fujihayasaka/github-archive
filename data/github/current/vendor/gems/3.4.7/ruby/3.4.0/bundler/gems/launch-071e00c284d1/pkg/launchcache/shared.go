package launchcache

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/cache"
	"github.com/github/launch/pkg/cache/cachebreaker"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/cache/cacheobs"
	"github.com/github/launch/pkg/cache/cacheprefix"
	"github.com/github/launch/pkg/cache/cacheredis"
	"github.com/github/launch/pkg/cache/cachethru"
	"github.com/github/launch/types"

	"github.com/pkg/errors"
)

type CacheConfig struct {
	MemoryMaxSizeBytes int           `config:"67108864,env=LAUNCH_CACHE_MEMORY_MAX_SIZE_BYTES"`
	RedisGetTimeout    time.Duration `config:"2s,env=LAUNCH_CACHE_REDIS_GET_TIMEOUT"`
	RedisSetTimeout    time.Duration `config:"2s,env=LAUNCH_CACHE_REDIS_SET_TIMEOUT"`
}

type namespacedCache struct {
	azp              *azpCache
	s2s              *s2sCache
	gh               *ghCache
	ghTwirp          *ghTwirpCache
	launchDependency *launchDependencyCache
	healingJob       *healingJobCache
	transitions      *transitionsCache
}

func NewSharedCache(client redis.UniversalClient, breaker *circuit.Breaker, cfg CacheConfig, obs *observability.Observability) Cache {
	if cfg.MemoryMaxSizeBytes <= 0 {
		cfg.MemoryMaxSizeBytes = 64 * (1 << 20)
	}
	if cfg.RedisGetTimeout <= 0 {
		cfg.RedisGetTimeout = 2 * time.Second
	}
	if cfg.RedisSetTimeout <= 0 {
		cfg.RedisSetTimeout = 2 * time.Second
	}

	localCache := cacheobs.Observe(
		cachemem.NewExpiringCache(
			cfg.MemoryMaxSizeBytes,
			cachemem.WithExpiringCacheTelemetry(
				func(ctx context.Context, size, max int) {
					obs.Gauge(ctx, "mem.cache.current_byte_size", nil, int64(size))
					obs.Gauge(ctx, "mem.cache.max_byte_size", nil, int64(max))
				},
				func(ctx context.Context, count int) {
					obs.Gauge(ctx, "mem.cache.item_count", nil, int64(count))
				},
			),
			cachemem.WithExpiringCacheEvictionHandler(
				func(ctx context.Context, _ string, _ *cache.ExpiringValue) {
					obs.Counter(ctx, "mem.cache.evicted_count", nil, 1)
				},
			),
			cachemem.WithExpiringCacheExpiryHandler(
				func(ctx context.Context, _ string, _ *cache.ExpiringValue) {
					obs.Counter(ctx, "mem.cache.expired_count", nil, 1)
				},
			),
		),
		"mem",
		obs,
	)

	cache := localCache
	// if redis is available, write-thru redis
	if client != nil && breaker != nil {
		redisCache := cacheobs.Observe(
			cacheredis.NewExpiringCache(client),
			"redis",
			obs,
		)
		remoteCache := cacheobs.Observe(
			cachebreaker.CircuitBreaker(redisCache, breaker),
			"breaker",
			obs,
		)
		cache = cachethru.WriteThru(localCache, remoteCache)
		cache = cacheobs.Observe(cache, "writethru", obs)
	}
	cache = cacheprefix.Prefix(cache, "launch/")

	return NewNamespacedCache(cache, obs)
}

func NewNamespacedCache(cache cache.ExpiringCache, obs *observability.Observability) *namespacedCache {
	return &namespacedCache{
		// when adding new caches, add them with a prefix as done here
		azp:              &azpCache{cache: cacheobs.Observe(cacheprefix.Prefix(cache, "azp/"), "azp", obs)},
		s2s:              &s2sCache{cache: cacheobs.Observe(cacheprefix.Prefix(cache, "s2s/"), "s2s", obs)},
		gh:               &ghCache{cache: cacheobs.Observe(cacheprefix.Prefix(cache, "gh/"), "gh", obs)},
		ghTwirp:          &ghTwirpCache{cache: cacheobs.Observe(cacheprefix.Prefix(cache, "gh_twirp/"), "gh_twirp", obs)},
		launchDependency: &launchDependencyCache{cache: cacheobs.Observe(cacheprefix.Prefix(cache, "launch_dependency/"), "launch_dependency", obs)},
		healingJob:       &healingJobCache{cache: cacheobs.Observe(cacheprefix.Prefix(cache, "healingjob/"), "healingjob", obs)},
		transitions:      &transitionsCache{cache: cacheobs.Observe(cacheprefix.Prefix(cache, "transitions/"), "transitions", obs)},
	}
}

func (ca *namespacedCache) AzureProvider() AZPCache                 { return ca.azp }
func (ca *namespacedCache) S2SProvider() S2SCache                   { return ca.s2s }
func (ca *namespacedCache) GitHub() GitHubCache                     { return ca.gh }
func (ca *namespacedCache) GitHubTwirp() GitHubTwirpCache           { return ca.ghTwirp }
func (ca *namespacedCache) LaunchDependency() LaunchDependencyCache { return ca.launchDependency }
func (ca *namespacedCache) HealingJob() HealingJobCache             { return ca.healingJob }
func (ca *namespacedCache) Transitions() TransitionsCache           { return ca.transitions }

type azpCache struct {
	cache cache.ExpiringCache
}

func (ca *azpCache) BearerTokenCacheFor(requestURL string, clientID string, resource string) AZPBearerTokenCache {
	return &azpBearerTokenCache{
		cache: cacheprefix.Prefix(ca.cache, "bearer_tokens/v1/"),
		key:   fmt.Sprintf("%s|ID:%s|RS:%s", requestURL, clientID, resource),
	}
}

type azpBearerTokenCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *azpBearerTokenCache) Get(ctx context.Context) ([]byte, time.Time, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return nil, time.Time{}, ok, err
	}
	return v.Value, v.Expiry, ok, err
}

func (ca *azpBearerTokenCache) Set(ctx context.Context, token []byte, expiresIn time.Duration) error {
	return ca.cache.Set(ctx, ca.key, token, time.Now(), expiresIn)
}

type azpS2SAccessTokenCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *azpS2SAccessTokenCache) Get(ctx context.Context) ([]byte, time.Time, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return nil, time.Time{}, ok, err
	}
	return v.Value, v.Expiry, ok, err
}

func (ca *azpS2SAccessTokenCache) Set(ctx context.Context, token []byte, expiresIn time.Duration) error {
	return ca.cache.Set(ctx, ca.key, token, time.Now(), expiresIn)
}

func (ca *azpCache) S2SAccessTokenCacheFor(clientID string) AZPS2SAccessTokenCache {
	return &azpS2SAccessTokenCache{
		cache: cacheprefix.Prefix(ca.cache, "azp_s2s_tokens/v1/"),
		key:   clientID,
	}
}

type s2sCache struct {
	cache cache.ExpiringCache
}

func (ca *s2sCache) KeyVaultCacheFor(vaultName, secretName string) KeyVaultCache {
	return &kvCache{
		cache: cacheprefix.Prefix(ca.cache, "key_vault/v1/"),
		key:   fmt.Sprintf("V:%s|S:%s", vaultName, secretName),
	}
}

type kvCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *kvCache) Get(ctx context.Context) ([]byte, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return nil, ok, err
	}
	return v.Value, ok, err
}

func (ca *kvCache) Set(ctx context.Context, token []byte, expiresIn time.Duration) error {
	return ca.cache.Set(ctx, ca.key, token, time.Now(), expiresIn)
}

type ghCache struct {
	cache cache.ExpiringCache
}

func (ca *ghCache) SiteScopedTokenCacheFor(appID, ownerID int64, reqBody []byte) SiteScopedTokenCache {
	sha256sum := sha256.Sum256(reqBody)
	cacheKey := fmt.Sprintf("%d:%d:%s", appID, ownerID, base64.StdEncoding.EncodeToString(sha256sum[:]))
	return &siteScopedTokenCache{
		cache: cacheprefix.Prefix(ca.cache, "site_scoped_token/v3/"),
		key:   cacheKey,
	}
}

type siteScopedTokenCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *siteScopedTokenCache) Get(ctx context.Context) ([]byte, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return nil, ok, err
	}
	return v.Value, ok, err
}

func (ca *siteScopedTokenCache) Set(ctx context.Context, token []byte, expiresIn time.Duration) error {
	return ca.cache.Set(ctx, ca.key, token, time.Now(), expiresIn)
}

type ghTwirpCache struct {
	cache cache.ExpiringCache
}

func (ca *ghTwirpCache) RepoCanUseActionsCacheFor(gid types.GlobalID) GitHubRepoCanUseActionsCache {
	return &ghRepoCanUseCache{
		cache: cacheprefix.Prefix(ca.cache, "repo_can_use/v1/"),
		key:   gid.String(),
	}
}

type ghRepoCanUseCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *ghRepoCanUseCache) Get(ctx context.Context) ([]byte, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return nil, ok, err
	}
	return v.Value, ok, err
}

func (ca *ghRepoCanUseCache) Set(ctx context.Context, token []byte, expiresIn time.Duration) error {
	return ca.cache.Set(ctx, ca.key, token, time.Now(), expiresIn)
}

func (ca *ghTwirpCache) FeatureFlagCacheFor(gid types.GlobalID, featureFlag string) GitHubFeatureFlagCache {
	return &ghFeatureFlagCache{
		cache: cacheprefix.Prefix(ca.cache, "feature_flag/v1/"),
		key:   fmt.Sprintf("%s:%s", gid.String(), featureFlag),
	}
}

func (ca *ghTwirpCache) FeatureFlagActorCacheFor(actor, featureFlag string) GitHubFeatureFlagCache {
	return &ghFeatureFlagCache{
		cache: cacheprefix.Prefix(ca.cache, "feature_flag_actor/v1/"),
		key:   fmt.Sprintf("%s:%s", actor, featureFlag),
	}
}

func (ca *ghTwirpCache) RepoOrOwnersFeatureFlagCacheFor(repoGID types.GlobalID, featureFlag string) GitHubFeatureFlagCache {
	return &ghFeatureFlagCache{
		cache: cacheprefix.Prefix(ca.cache, "repo_or_owners_feature_flag/v1/"),
		key:   fmt.Sprintf("%s:%s", repoGID.String(), featureFlag),
	}
}

type ghFeatureFlagCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *ghFeatureFlagCache) Get(ctx context.Context) ([]byte, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return nil, ok, err
	}
	return v.Value, ok, err
}

func (ca *ghFeatureFlagCache) Set(ctx context.Context, token []byte, expiresIn time.Duration) error {
	return ca.cache.Set(ctx, ca.key, token, time.Now(), expiresIn)
}

func (ca *ghTwirpCache) TrustTierCacheFor(id types.GlobalID) GitHubTrustTierCache {
	return &ghTrustTierCache{
		cache: cacheprefix.Prefix(ca.cache, "trusttier/v1/"),
		key:   id.String(),
	}
}

type ghTrustTierCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *ghTrustTierCache) Get(ctx context.Context) (int64, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return 0, ok, err
	}
	var out int64
	return out, true, json.Unmarshal(v.Value, &out)
}

func (ca *ghTrustTierCache) Set(ctx context.Context, tier int64, expiresIn time.Duration) error {
	value, err := json.Marshal(tier)
	if err != nil {
		return errors.Wrap(err, "marshaling to json")
	}
	return ca.cache.Set(ctx, ca.key, value, time.Now(), expiresIn)
}

func (ca *ghTwirpCache) RepoAccountDetailsCacheFor(id types.GlobalID) GitHubRepositoryAccountDetailsCache {
	return &ghRepoAccountDetailsCache{
		cache: cacheprefix.Prefix(ca.cache, "repoaccountdetails/v1/"),
		key:   id.String(),
	}
}

func (ca *ghTwirpCache) UserByLoginCacheFor(login string, tenant int64) GitHubUserByLoginCache {
	return &ghUserByLoginCache{
		cache: cacheprefix.Prefix(ca.cache, "userbylogin/v1/"),
		key:   fmt.Sprintf("%s:%d", login, tenant),
	}
}

type ghUserByLoginCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *ghUserByLoginCache) Get(ctx context.Context) ([]byte, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return nil, ok, err
	}
	return v.Value, ok, err
}

func (ca *ghUserByLoginCache) Set(ctx context.Context, token []byte, expiresIn time.Duration) error {
	return ca.cache.Set(ctx, ca.key, token, time.Now(), expiresIn)
}

type ghRepoAccountDetailsCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *ghRepoAccountDetailsCache) Get(ctx context.Context) ([]byte, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return nil, ok, err
	}
	var out []byte
	return out, true, json.Unmarshal(v.Value, &out)
}

func (ca *ghRepoAccountDetailsCache) Set(ctx context.Context, tier []byte, expiresIn time.Duration) error {
	value, err := json.Marshal(tier)
	if err != nil {
		return errors.Wrap(err, "marshaling to json")
	}
	return ca.cache.Set(ctx, ca.key, value, time.Now(), expiresIn)
}

func (ca *ghTwirpCache) RepositoryOwnerIDCacheFor(ownerID int64) GitHubRepositoryOwnerIDCache {
	return &ghRepositoryOwnerIDCache{
		cache: cacheprefix.Prefix(ca.cache, "repositoryownerid/v1/"),
		key:   fmt.Sprintf("%d", ownerID),
	}
}

type ghRepositoryOwnerIDCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *ghRepositoryOwnerIDCache) Get(ctx context.Context) (int64, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return 0, false, err
	}
	var out int64
	return out, true, json.Unmarshal(v.Value, &out)
}

func (ca *ghRepositoryOwnerIDCache) Set(ctx context.Context, ownerID int64, expiresIn time.Duration) error {
	value, err := json.Marshal(ownerID)
	if err != nil {
		return errors.Wrap(err, "marshaling to []byte from int64")
	}
	return ca.cache.Set(ctx, ca.key, value, time.Now(), expiresIn)
}

func (ca *ghTwirpCache) RepositoryCacheFor(tenant int64, nwo string) GitHubRepositoryCache {
	return &ghRepoCache{
		cache: cacheprefix.Prefix(ca.cache, "repo/v2/"),
		key:   fmt.Sprintf("%d:%s", tenant, strings.ToLower(nwo)),
	}
}

type ghRepoCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *ghRepoCache) Get(ctx context.Context) ([]byte, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return nil, ok, err
	}
	return v.Value, ok, err
}

func (ca *ghRepoCache) Set(ctx context.Context, repository []byte, expiresIn time.Duration) error {
	return ca.cache.Set(ctx, ca.key, repository, time.Now(), expiresIn)
}

type launchDependencyCache struct {
	cache cache.ExpiringCache
}

func (ca *launchDependencyCache) AqueductQueueDepthCacheFor(queueName string) AqueductQueueDepthCache {
	return &aqueductQueueDepthCache{
		cache: cacheprefix.Prefix(ca.cache, "queue_depth/v1/"),
		key:   queueName,
	}
}

type aqueductQueueDepthCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *aqueductQueueDepthCache) Get(ctx context.Context) (int64, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return 0, ok, err
	}

	var out int64
	return out, true, json.Unmarshal(v.Value, &out)
}

func (ca *aqueductQueueDepthCache) Set(ctx context.Context, depth int64, expiresIn time.Duration) error {
	value, err := json.Marshal(depth)
	if err != nil {
		return errors.Wrap(err, "marshaling to data[] from int64")
	}

	return ca.cache.Set(ctx, ca.key, value, time.Now(), expiresIn)
}

type healingJobCache struct {
	cache cache.ExpiringCache
}

func (hc *healingJobCache) SkipWorkflowExecutionIDFor(workflowExecutionID int64) SkipWorkflowExecutionIDCache {
	return &healingJobSkippableWorkflowsCache{
		cache: cacheprefix.Prefix(hc.cache, "skippable_workflow_execution_id/v1/"),
		key:   fmt.Sprintf("%d", workflowExecutionID),
	}
}

type healingJobSkippableWorkflowsCache struct {
	cache cache.ExpiringCache
	key   string
}

func (hj *healingJobSkippableWorkflowsCache) Get(ctx context.Context) (string, bool, error) {
	v, ok, err := hj.cache.Get(ctx, hj.key, time.Now())
	if err != nil || !ok {
		return "", ok, err
	}

	var reason string
	return reason, true, json.Unmarshal(v.Value, &reason)
}

func (hj *healingJobSkippableWorkflowsCache) Set(ctx context.Context, reason string, expiresIn time.Duration) error {
	value, err := json.Marshal(reason)
	if err != nil {
		return errors.Wrap(err, "marshaling to data[] from int64")
	}

	return hj.cache.Set(ctx, hj.key, value, time.Now(), expiresIn)
}

func (ca *ghTwirpCache) GlobalIDCacheFor(legacyGID string) GitHubGlobalIDCache {
	return &ghGlobalIDCache{
		cache: cacheprefix.Prefix(ca.cache, "global_id/v1/"),
		key:   legacyGID,
	}
}

type ghGlobalIDCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ca *ghGlobalIDCache) Get(ctx context.Context) (types.GlobalID, bool, error) {
	v, ok, err := ca.cache.Get(ctx, ca.key, time.Now())
	if err != nil || !ok {
		return "", ok, err
	}

	var globalID types.GlobalID
	return globalID, true, json.Unmarshal(v.Value, &globalID)
}

func (ca *ghGlobalIDCache) Set(ctx context.Context, nextGlobalID types.GlobalID, expiresIn time.Duration) error {
	value, err := json.Marshal(nextGlobalID)
	if err != nil {
		return errors.Wrap(err, "marshaling to json")
	}
	return ca.cache.Set(ctx, ca.key, value, time.Now(), expiresIn)
}

type transitionsCache struct {
	cache cache.ExpiringCache
}

func (tc *transitionsCache) CacheFor(transitionName string) LaunchTransitionsCache {
	return &launchTransitionsCache{
		cache: cacheprefix.Prefix(tc.cache, fmt.Sprintf("%s_cache/v1/", strings.ToLower(transitionName))),
		key:   "latest_processed_row_id",
	}
}

type launchTransitionsCache struct {
	cache cache.ExpiringCache
	key   string
}

func (ltc *launchTransitionsCache) Get(ctx context.Context) (int64, bool, error) {
	v, ok, err := ltc.cache.Get(ctx, ltc.key, time.Now())
	if err != nil || !ok {
		return 0, ok, err
	}

	var rowID int64
	return rowID, true, json.Unmarshal(v.Value, &rowID)
}

func (ltc *launchTransitionsCache) Set(ctx context.Context, rowID int64, expiresIn time.Duration) error {
	value, err := json.Marshal(rowID)
	if err != nil {
		return errors.Wrap(err, "failed to marshal rowID")
	}

	return ltc.cache.Set(ctx, ltc.key, value, time.Now(), expiresIn)
}

func (rvc *ghTwirpCache) RepositoryVisibilityCacheFor(repoID int64) GetRepositoryVisibilityCache {
	return &ghRepositoryVisibilityCache{
		cache: cacheprefix.Prefix(rvc.cache, "repositoryvisibility/v1/"),
		key:   fmt.Sprintf("%d", repoID),
	}
}

type ghRepositoryVisibilityCache struct {
	cache cache.ExpiringCache
	key   string
}

func (rvc *ghRepositoryVisibilityCache) Get(ctx context.Context) (int32, bool, error) {
	v, ok, err := rvc.cache.Get(ctx, rvc.key, time.Now())
	if err != nil || !ok {
		return 0, ok, err
	}

	var out int32
	return out, true, json.Unmarshal(v.Value, &out)
}

func (rvc *ghRepositoryVisibilityCache) Set(ctx context.Context, visibility int32, expiresIn time.Duration) error {
	value, err := json.Marshal(visibility)
	if err != nil {
		return errors.Wrap(err, "marshaling to json")
	}
	return rvc.cache.Set(ctx, rvc.key, value, time.Now(), expiresIn)
}
