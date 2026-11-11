package agenticapp

import (
	"context"
	"errors"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
)

// ReloadFunc fetches the current set of agentic apps from an external source.
// It is called by the Provider when a lookup misses and the in-memory registry
// may be stale.
type ReloadFunc func(ctx context.Context) (*Copilot, []sweagentd.AgenticApp, error)

// defaultReloadCooldown is the minimum interval between consecutive
// miss-triggered reloads to prevent excessive external calls.
const defaultReloadCooldown = 30 * time.Second

// DefaultVersionCheckInterval is the minimum interval between Redis version
// checks to avoid excessive cache reads on every lookup.
const DefaultVersionCheckInterval = 30 * time.Second

// versionKey is the Redis key used to track the global agentic apps version.
const versionKey = "agentic_apps:version"

// versionTTL is the TTL for the Redis version key.
const versionTTL = 1 * time.Hour

// IsAgenticFunc is a function that checks if an actor is associated with an Agentic App.
type IsAgenticFunc func(sweagentd.ActorLogin) (sweagentd.AgenticApp, bool)

// providerState holds the immutable snapshot of agentic app data.
// Each reload creates a new providerState and atomically swaps it into the Provider.
type providerState struct {
	copilotApp *Copilot
	apps       []sweagentd.AgenticApp
	allApps    []sweagentd.AgenticApp
}

func newProviderState(copilotApp *Copilot, apps ...sweagentd.AgenticApp) *providerState {
	return &providerState{
		copilotApp: copilotApp,
		apps:       apps,
		allApps:    append([]sweagentd.AgenticApp{copilotApp}, apps...),
	}
}

// Provider manages different Agentic Apps.
// It uses atomic.Pointer to allow lock-free reads and safe concurrent reloads.
type Provider struct {
	state atomic.Pointer[providerState]

	// reloadFn is an optional callback to fetch fresh app data on a cache miss.
	reloadFn ReloadFunc
	// logger for reload-on-miss diagnostics. Nil if no reload func is configured.
	logger log.Logger
	// statter for cache hit/miss metrics. Nil if no reload func is configured.
	statter stats.Client
	// reloadMu serializes miss-triggered reloads so concurrent misses coalesce
	// into a single external call. Also guards event-driven Reload() to prevent
	// a slow miss-triggered reload from overwriting a newer event-driven state.
	reloadMu sync.Mutex
	// lastReloadAt tracks the last time a reload (event-driven or miss-triggered)
	// completed, used to enforce the cooldown.
	lastReloadAt atomic.Pointer[time.Time]
	// reloadCooldown is the minimum interval between miss-triggered reloads.
	reloadCooldown time.Duration
	// nowFunc allows tests to override the clock.
	nowFunc func() time.Time

	// versionCache is an optional Redis cache for cross-pod version sync.
	versionCache cache.Store
	// localVersion tracks the last known Redis version for this pod.
	localVersion atomic.Int64
	// lastVersionCheckAt tracks the last time we checked Redis for a version bump.
	lastVersionCheckAt atomic.Pointer[time.Time]
	// versionCheckInterval is the minimum interval between Redis version checks.
	versionCheckInterval time.Duration
}

// ErrAgentNotFound is returned when an agent with the specified ID is not found.
var ErrAgentNotFound = errors.New("agent not found")

// NewProvider creates a new Provider instance.
func NewProvider(copilotApp *Copilot, apps ...sweagentd.AgenticApp) *Provider {
	p := &Provider{
		reloadCooldown: defaultReloadCooldown,
		nowFunc:        time.Now,
	}
	p.state.Store(newProviderState(copilotApp, apps...))
	return p
}

// WithReloadOnMiss configures the provider to automatically attempt a reload
// from the given function when FindByID or FindByBotID encounters a miss.
// This must be called during initialization, before the provider is used
// concurrently.
func (p *Provider) WithReloadOnMiss(fn ReloadFunc, logger log.Logger, statter stats.Client) *Provider {
	p.reloadFn = fn
	p.logger = logger
	p.statter = statter
	return p
}

// WithVersionSync configures the provider to use a shared Redis cache for
// cross-pod version synchronization. When a pod reloads apps (via Hydro event),
// it bumps a version counter in Redis. Other pods detect the version bump on
// their next FindByID/FindByBotID call (time-gated by checkInterval) and
// reload from the monolith. Requires WithReloadOnMiss to be configured first.
//
// On initialization, the current Redis version is read and stored locally so
// that a pod that just loaded fresh data from the monolith does not trigger a
// redundant reload on its first lookup.
//
// This must be called during initialization, before the provider is used
// concurrently.
func (p *Provider) WithVersionSync(versionCache cache.Store, checkInterval time.Duration) *Provider {
	p.versionCache = versionCache
	p.versionCheckInterval = checkInterval
	// Seed localVersion from Redis so we don't trigger a spurious reload
	// immediately after startup (we just loaded fresh data from monolith).
	val, ok := versionCache.Get(versionKey)
	if ok {
		ver, err := strconv.ParseInt(val, 10, 64)
		if err == nil {
			p.localVersion.Store(ver)
		}
	}
	return p
}

// Reload atomically replaces the provider's app registry with a new set of apps.
// It acquires reloadMu to prevent a concurrent reloadOnMiss from overwriting
// this newer state. It also updates the last-reload timestamp and bumps the
// Redis version counter (if version sync is configured) so other pods detect
// the change.
func (p *Provider) Reload(copilotApp *Copilot, apps ...sweagentd.AgenticApp) {
	p.reloadMu.Lock()
	defer p.reloadMu.Unlock()
	p.state.Store(newProviderState(copilotApp, apps...))
	now := p.nowFunc()
	p.lastReloadAt.Store(&now)
	// Bump Redis version so other pods detect the change.
	if p.versionCache != nil {
		newVer, ok := p.versionCache.Incr(versionKey, 1, versionTTL)
		if ok {
			p.localVersion.Store(newVer)
		}
	}
}

// CopilotApp returns the Copilot app instance managed by this provider.
func (p *Provider) CopilotApp() *Copilot {
	return p.state.Load().copilotApp
}

// IsCopilotApp returns true if the provided app ID corresponds to the Copilot app
// or the Copilot Code Review app.
func (p *Provider) IsCopilotApp(appID int64) bool {
	s := p.state.Load()
	if appID == 0 || appID == s.copilotApp.AppID() {
		return true
	}
	// CCR is considered a Copilot app
	for _, app := range s.apps {
		if ccrApp, ok := app.(*CopilotCodeReview); ok && ccrApp.AppID() == appID {
			return true
		}
	}

	return p.IsCodeScanningApp(appID)
}

// IsCopilotCodingAgentApp returns true if the provided app ID corresponds
// specifically to the Copilot coding agent (CCA) app. Unlike IsCopilotApp,
// this excludes Copilot Code Review, Code Scanning, and all other apps.
// An appID of 0 defaults to the Copilot coding agent.
func (p *Provider) IsCopilotCodingAgentApp(appID int64) bool {
	s := p.state.Load()
	return appID == 0 || appID == s.copilotApp.AppID()
}

// IsCopilotCodeReviewApp returns true if the provided app ID corresponds to the Copilot Code Review app.
func (p *Provider) IsCopilotCodeReviewApp(appID int64) bool {
	s := p.state.Load()
	for _, app := range s.apps {
		if ccrApp, ok := app.(*CopilotCodeReview); ok && ccrApp.AppID() == appID {
			return true
		}
	}
	return false
}

// IsCodeScanningApp returns true if the provided app ID corresponds to the Code Scanning (GHAS) app.
func (p *Provider) IsCodeScanningApp(appID int64) bool {
	s := p.state.Load()
	for _, app := range s.apps {
		if csApp, ok := app.(*CodeScanning); ok && csApp.AppID() == appID {
			return true
		}
	}
	return false
}

// IsAgentCheckExempt returns true if the agent with the given app ID is exempt
// from license and quota checks. Requires both the feature flag to be enabled
// for the repository and the app to declare IsQuotaExempt() = true.
func (p *Provider) IsAgentCheckExempt(ctx context.Context, ffClient featureflags.Client, agentID, repoID int64) bool {
	if agentID == 0 {
		return false
	}
	if !ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentIntegrationQuotaExempt, repoID) {
		return false
	}
	app, err := p.FindByID(ctx, agentID)
	if err != nil {
		return false
	}
	return app.IsQuotaExempt()
}

// IsAgentJobLimitExempt returns true if the agent with the given app ID is
// exempt from actor-level job concurrency limits. The app must satisfy
// AgenticAppJobLimitExempt with IsJobLimitExempt() = true.
func (p *Provider) IsAgentJobLimitExempt(ctx context.Context, agentID int64) bool {
	if agentID == 0 {
		return false
	}
	app, err := p.FindByID(ctx, agentID)
	if err != nil {
		return false
	}
	exempt, ok := app.(sweagentd.AgenticAppJobLimitExempt)
	return ok && exempt.IsJobLimitExempt()
}

// JobLimitExemptAgentIDs returns the app IDs of all agents that satisfy the
// optional AgenticAppJobLimitExempt interface and declare themselves exempt
// from job limits.
func (p *Provider) JobLimitExemptAgentIDs() []int64 {
	var ids []int64
	for _, app := range p.Apps() {
		if exempt, ok := app.(sweagentd.AgenticAppJobLimitExempt); ok && exempt.IsJobLimitExempt() {
			ids = append(ids, app.AppID())
		}
	}
	return ids
}

// IsThirdPartyAgent returns true if the provided app is a third-party agent.
// Third-party agents include Claude, Codex, and other non-GitHub agentic apps.
// First-party GitHub apps (Copilot, Copilot Code Review, Code Scanning/GHAS) return false.
func (p *Provider) IsThirdPartyAgent(app sweagentd.AgenticApp) bool {
	if app == nil {
		return false
	}
	appID := app.AppID()
	// Copilot and CCR are first-party Copilot apps
	if p.IsCopilotApp(appID) {
		return false
	}
	// Code Scanning (GHAS) is a first-party GitHub app but not a Copilot app
	if p.IsCodeScanningApp(appID) {
		return false
	}
	return true
}

// ActorLogin represents a GitHub actor's login name.
type ActorLogin struct {
	login string
}

// GetLogin returns the login string for the actor.
func (a ActorLogin) GetLogin() string {
	return a.login
}

// ActorLoginFromString creates an ActorLogin from a login string.
func ActorLoginFromString(login string) ActorLogin {
	return ActorLogin{login}
}

// ActorLoginsFromStrings creates a slice of ActorLogin from a slice of login strings.
func ActorLoginsFromStrings(logins []string) []sweagentd.ActorLogin {
	var actors []sweagentd.ActorLogin
	for _, login := range logins {
		actors = append(actors, ActorLoginFromString(login))
	}

	return actors
}

// IsAgenticActor checks if the given actor is associated with any Agentic App.
func (p *Provider) IsAgenticActor(actor sweagentd.ActorLogin) (sweagentd.AgenticApp, bool) {
	s := p.state.Load()
	if s.copilotApp.hasLogin(actor.GetLogin()) {
		return s.copilotApp, true
	}

	for _, app := range s.apps {
		if agenticApp, ok := app.(interface {
			hasLogin(string) bool
		}); ok {
			if agenticApp.hasLogin(actor.GetLogin()) {
				return app, true
			}
		}
	}

	return nil, false
}

// HasAnyAgenticActor checks if any actor in the provided list is associated with an Agentic App.
func (p *Provider) HasAnyAgenticActor(actors []sweagentd.ActorLogin) (sweagentd.AgenticApp, bool) {
	for _, actor := range actors {
		if app, ok := p.IsAgenticActor(actor); ok {
			return app, true
		}
	}

	return nil, false
}

// IsAgenticMention checks if the given body text contains a mention of any Agentic App.
func (p *Provider) IsAgenticMention(body string) (sweagentd.AgenticApp, bool) {
	s := p.state.Load()
	if s.copilotApp.isMentioned(body) {
		return s.copilotApp, true
	}

	for _, app := range s.apps {
		if agenticApp, ok := app.(interface {
			isMentioned(string) bool
		}); ok {
			if agenticApp.isMentioned(body) {
				return app, true
			}
		}
	}

	return nil, false
}

// MentionResult contains the result of parsing a mention from a body text.
type MentionResult struct {
	App   sweagentd.AgenticApp
	Model string
}

// IsAgenticMentionWithModel checks if the given body text contains a mention of any Agentic App,
// and extracts any model selection from the mention (e.g., "@copilot+claude-opus.4.5" or "@claude[agent]+claude-opus.4.5").
// Returns the app and model if found.
func (p *Provider) IsAgenticMentionWithModel(body string) (*MentionResult, bool) {
	s := p.state.Load()
	// First, check if there's a @copilot+model mention
	if model, ok := s.copilotApp.isMentionedWithModel(body); ok {
		return &MentionResult{
			App:   s.copilotApp,
			Model: model,
		}, true
	}

	// Fall back to regular mention without model
	if s.copilotApp.isMentioned(body) {
		return &MentionResult{
			App:   s.copilotApp,
			Model: "",
		}, true
	}

	// Check other apps for mention with model first, then fall back to regular mention
	for _, app := range s.apps {
		if agenticApp, ok := app.(interface {
			isMentionedWithModel(string) (string, bool)
		}); ok {
			if model, matched := agenticApp.isMentionedWithModel(body); matched {
				return &MentionResult{
					App:   app,
					Model: model,
				}, true
			}
		}

		if agenticApp, ok := app.(interface {
			isMentioned(string) bool
		}); ok {
			if agenticApp.isMentioned(body) {
				return &MentionResult{
					App:   app,
					Model: "",
				}, true
			}
		}
	}

	return nil, false
}

// FindByID returns the agentic app to use based on the provided appID.
// If the provided appID is 0, it defaults to the Copilot agentic app.
// Returns ErrAgentNotFound if the provided appID doesn't match any known agents.
//
// When a ReloadFunc is configured via WithReloadOnMiss, a miss triggers a
// reload attempt (subject to cooldown) before returning an error.
func (p *Provider) FindByID(ctx context.Context, appID int64) (sweagentd.AgenticApp, error) {
	// Check if another pod bumped the Redis version and reload if needed.
	// Runs before the state lookup so that updates to existing apps are detected.
	p.maybeRefreshFromVersion(ctx)

	if app, ok := p.findByIDInState(p.state.Load(), appID); ok {
		p.incrementStat("agenticapp.find_by_id", stats.Tags{"result": "hit"})
		return app, nil
	}

	if p.reloadFn != nil {
		p.incrementStat("agenticapp.find_by_id", stats.Tags{"result": "miss"})
		reloaded, err := p.reloadOnMiss(ctx)
		if err != nil {
			p.logError("agenticapp: reload on miss failed", err, kvp.Int64("app_id", appID))
			p.incrementStat("agenticapp.reload_on_miss", stats.Tags{"result": "error"})
		} else if app, ok := p.findByIDInState(p.state.Load(), appID); ok {
			if reloaded {
				p.logInfo("agenticapp: FindByID resolved after reload", kvp.Int64("app_id", appID))
				p.incrementStat("agenticapp.reload_on_miss", stats.Tags{"result": "resolved"})
			}
			return app, nil
		} else if reloaded {
			p.incrementStat("agenticapp.reload_on_miss", stats.Tags{"result": "still_not_found"})
		}
	}

	return nil, goerrors.Errorf("%w: application ID %d is not recognized. Please ensure you are using a valid GitHub Copilot token", ErrAgentNotFound, appID)
}

// FindByBotID finds an agentic app by bot ID.
//
// When a ReloadFunc is configured via WithReloadOnMiss, a miss triggers a
// reload attempt (subject to cooldown) before returning an error.
func (p *Provider) FindByBotID(ctx context.Context, botID int64) (sweagentd.AgenticApp, error) {
	// Check if another pod bumped the Redis version and reload if needed.
	// Runs before the state lookup so that updates to existing apps are detected.
	p.maybeRefreshFromVersion(ctx)

	if app, ok := p.findByBotIDInState(p.state.Load(), botID); ok {
		p.incrementStat("agenticapp.find_by_bot_id", stats.Tags{"result": "hit"})
		return app, nil
	}

	if p.reloadFn != nil {
		p.incrementStat("agenticapp.find_by_bot_id", stats.Tags{"result": "miss"})
		reloaded, err := p.reloadOnMiss(ctx)
		if err != nil {
			p.logError("agenticapp: reload on miss failed", err, kvp.Int64("bot_id", botID))
			p.incrementStat("agenticapp.reload_on_miss", stats.Tags{"result": "error"})
		} else if app, ok := p.findByBotIDInState(p.state.Load(), botID); ok {
			if reloaded {
				p.logInfo("agenticapp: FindByBotID resolved after reload", kvp.Int64("bot_id", botID))
				p.incrementStat("agenticapp.reload_on_miss", stats.Tags{"result": "resolved"})
			}
			return app, nil
		} else if reloaded {
			p.incrementStat("agenticapp.reload_on_miss", stats.Tags{"result": "still_not_found"})
		}
	}

	return nil, ErrAgentNotFound
}

// LookupBotID performs a local-only lookup of an agentic app by bot ID.
// Unlike FindByBotID, it does NOT trigger a reload-on-miss or version check.
// Use this for callers where a miss is an expected outcome (e.g., checking
// whether a PR author is a known agent) rather than an indicator of stale data.
func (p *Provider) LookupBotID(botID int64) (sweagentd.AgenticApp, bool) {
	return p.findByBotIDInState(p.state.Load(), botID)
}

// Apps returns all managed agentic apps including the Copilot app.
func (p *Provider) Apps() []sweagentd.AgenticApp {
	return p.state.Load().allApps
}

// HasAppID returns true if the provider contains an app with the given ID.
func (p *Provider) HasAppID(appID int64) bool {
	s := p.state.Load()
	if s.copilotApp.AppID() == appID {
		return true
	}
	for _, app := range s.apps {
		if app.AppID() == appID {
			return true
		}
	}
	return false
}

// findByIDInState searches for an app by ID in the given state snapshot.
func (p *Provider) findByIDInState(s *providerState, appID int64) (sweagentd.AgenticApp, bool) {
	if appID == 0 || appID == s.copilotApp.AppID() {
		return s.copilotApp, true
	}
	for _, app := range s.apps {
		if appID == app.AppID() {
			return app, true
		}
	}
	return nil, false
}

// findByBotIDInState searches for an app by bot ID in the given state snapshot.
func (p *Provider) findByBotIDInState(s *providerState, botID int64) (sweagentd.AgenticApp, bool) {
	if botID == s.copilotApp.BotID() {
		return s.copilotApp, true
	}
	for _, app := range s.apps {
		if botID == app.BotID() {
			return app, true
		}
	}
	return nil, false
}

// reloadOnMiss attempts to refresh the app registry from the external source.
// It coalesces concurrent callers under a mutex and skips if the cooldown has
// not elapsed since the last reload (event-driven or miss-triggered).
// Returns (true, nil) if a reload was performed, (false, nil) if skipped
// because another goroutine already reloaded recently, or (false, err) if
// the reload call itself failed.
func (p *Provider) reloadOnMiss(ctx context.Context) (bool, error) {
	p.reloadMu.Lock()
	defer p.reloadMu.Unlock()

	// Double-check: another goroutine may have reloaded while we waited.
	if t := p.lastReloadAt.Load(); t != nil && p.nowFunc().Sub(*t) < p.reloadCooldown {
		p.logDebug("agenticapp: reload skipped, within cooldown")
		return false, nil
	}

	copilotApp, apps, err := p.reloadFn(ctx)

	// Update cooldown on success or non-context errors to prevent thundering
	// herd on a failing endpoint. Skip cooldown for context cancellation so
	// other requests with valid contexts can retry immediately.
	if err == nil || (!errors.Is(err, context.Canceled) && !errors.Is(err, context.DeadlineExceeded)) {
		now := p.nowFunc()
		p.lastReloadAt.Store(&now)
	}

	if err != nil {
		return false, err
	}

	p.state.Store(newProviderState(copilotApp, apps...))
	p.logInfo("agenticapp: reload on miss completed", kvp.Int("app_count", len(apps)+1))
	return true, nil
}

func (p *Provider) logInfo(msg string, fields ...kvp.Field) {
	if p.logger != nil {
		p.logger.Info(msg, fields...)
	}
}

func (p *Provider) logDebug(msg string, fields ...kvp.Field) {
	if p.logger != nil {
		p.logger.Debug(msg, fields...)
	}
}

func (p *Provider) logError(msg string, err error, fields ...kvp.Field) {
	if p.logger != nil {
		p.logger.WithError(err).Error(msg, fields...)
	}
}

func (p *Provider) incrementStat(name string, tags stats.Tags) {
	if p.statter != nil {
		p.statter.Increment(name, tags)
	}
}

// maybeRefreshFromVersion checks the Redis version counter and triggers a
// reload if the remote version is newer than the local one. The check is
// time-gated by versionCheckInterval to avoid hitting Redis on every lookup.
func (p *Provider) maybeRefreshFromVersion(ctx context.Context) {
	if p.versionCache == nil || p.reloadFn == nil {
		return
	}

	// Time-gate: only check Redis at most once per interval.
	if t := p.lastVersionCheckAt.Load(); t != nil && p.nowFunc().Sub(*t) < p.versionCheckInterval {
		return
	}
	now := p.nowFunc()
	p.lastVersionCheckAt.Store(&now)

	remoteVal, ok := p.versionCache.Get(versionKey)
	if !ok {
		return
	}
	remoteVer, err := strconv.ParseInt(remoteVal, 10, 64)
	if err != nil {
		return
	}
	if remoteVer <= p.localVersion.Load() {
		return
	}

	p.logInfo("agenticapp: version mismatch detected, reloading",
		kvp.Int64("local_version", p.localVersion.Load()),
		kvp.Int64("remote_version", remoteVer),
	)
	p.incrementStat("agenticapp.version_sync", stats.Tags{"result": "reload"})

	reloaded, reloadErr := p.reloadOnMiss(ctx)
	if reloadErr != nil {
		p.logError("agenticapp: version sync reload failed", reloadErr)
		return
	}
	if reloaded {
		p.localVersion.Store(remoteVer)
	}
}
