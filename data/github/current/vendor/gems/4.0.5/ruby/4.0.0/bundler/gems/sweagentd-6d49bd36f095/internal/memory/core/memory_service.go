package core

import (
	"context"
	"errors"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

// Telemetry metric names for memory service operations.
const (
	metricServiceOperationDuration      = "memory_service.operation_duration"
	metricServiceErrorCount             = "memory_service.error_count"
	metricSecretScanningDuration        = "memory_service.secret_scanning_duration"
	metricSecretScanningInvocations     = "memory_service.secret_scanning_invocations"
	metricSecretScanningFailures        = "memory_service.secret_scanning_failures"
	metricSecretScanningBlocked         = "memory_service.secret_scanning_blocked"
	metricEnablementCheckDuration       = "memory_service.enablement_check_duration"
	metricMemoryContentSize             = "memory_service.memory_content_size"
	metricMemoriesPerRepository         = "memory_service.memories_per_repository"
	metricMemoriesPerRepositoryFiltered = "memory_service.memories_per_repository_filtered"
	metricMemoriesPerUser               = "memory_service.memories_per_user"
	metricMemoriesPerUserFiltered       = "memory_service.memories_per_user_filtered"
	metricVotesPerMemory                = "memory_service.votes_per_memory"
	metricTotalMemoriesPerRepository    = "memory_service.total_memories_per_repository"
	metricTotalMemoriesPerUser          = "memory_service.total_memories_per_user"
	metricVoteAsyncLaunched             = "memory_service.vote_async_launched"
	metricVoteAsyncError                = "memory_service.vote_async_error"
)

// asyncVoteTimeout bounds the lifetime of background vote goroutines to
// prevent goroutine leaks if downstream dependencies (Cosmos, secret scanner)
// stall. This is generous enough for secret scanning + up to 3 Cosmos retries.
const asyncVoteTimeout = 30 * time.Second

// MemoryService defines the interface for memory management operations.
type MemoryService interface { //nolint:interfacebloat // Explicit per-scope methods are intentional
	// Repository-scoped operations
	CreateMemory(ctx context.Context, memory *Memory, repository *Repository) error
	GetMemories(ctx context.Context, user User, repository *Repository) ([]*Memory, error)
	GetRecentMemories(ctx context.Context, user User, repository *Repository, limit uint) ([]*Memory, error)
	GetTopMemories(ctx context.Context, user User, repository *Repository, limit uint) ([]*Memory, error)
	DeleteMemory(ctx context.Context, user User, repository *Repository, memoryID MemoryID) error
	DeleteMemories(ctx context.Context, user User, repository *Repository, memoryIDs []MemoryID) (*BatchDeleteResult, error)
	DeleteAllMemories(ctx context.Context, user User, repository *Repository) error
	CheckMemoryEnabled(ctx context.Context, userID int64, repository *Repository) (bool, error)
	VoteOnMemory(ctx context.Context, user User, repository *Repository, fact string, vote *Vote) error
	CountMemories(ctx context.Context, user User, repository *Repository) (int, error)

	// User-scoped operations
	CreateUserMemory(ctx context.Context, memory *Memory, user User) error
	GetUserMemories(ctx context.Context, user User, query UserMemoryQuery) ([]*Memory, error)
	GetRecentUserMemories(ctx context.Context, user User, limit uint, query UserMemoryQuery) ([]*Memory, error)
	GetTopUserMemories(ctx context.Context, user User, limit uint, query UserMemoryQuery) ([]*Memory, error)
	DeleteUserMemory(ctx context.Context, user User, memoryID MemoryID) error
	DeleteUserMemories(ctx context.Context, user User, memoryIDs []MemoryID) (*BatchDeleteResult, error)
	DeleteAllUserMemories(ctx context.Context, user User) error
	CheckUserMemoryEnabled(ctx context.Context, userID int64) (bool, error)
	VoteOnUserMemory(ctx context.Context, user User, fact string, vote *Vote) error
	CountUserMemories(ctx context.Context, user User, query UserMemoryQuery) (int, error)
	ListBillingEntityMemories(ctx context.Context, filter BillingEntityMemoryFilter, pageRequest MemoryPageRequest) (*MemoryPage, error)
	DeleteBillingEntityMemories(ctx context.Context, filter BillingEntityMemoryFilter, pageRequest MemoryPageRequest) (*BillingEntityDeleteResult, error)
}

type memoryService struct {
	store                 MemoryStore
	featureFlagClient     featureflags.Client
	secretScanner         SecretScanner
	obsv                  observability.Exporters
	enablementChecker     MemoryEnablementChecker
	billingEntityResolver BillingEntityResolver
}

// NewMemoryService creates a new instance of MemoryService.
func NewMemoryService(
	store MemoryStore,
	featureFlagClient featureflags.Client,
	secretScanner SecretScanner,
	obsv observability.Exporters,
	enablementChecker MemoryEnablementChecker,
	billingEntityResolver BillingEntityResolver,
) MemoryService {
	return &memoryService{
		store:                 store,
		featureFlagClient:     featureFlagClient,
		secretScanner:         secretScanner,
		obsv:                  obsv,
		enablementChecker:     enablementChecker,
		billingEntityResolver: billingEntityResolver,
	}
}

// CreateMemory saves a new memory to the repository.
// The repository parameter should be pre-fetched by the caller to avoid
// authorization issues with different token types.
func (s *memoryService) CreateMemory(ctx context.Context, memory *Memory, repository *Repository) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.CreateMemory")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", memory.Source.User.ID),
		kvp.String("agent", memory.Source.Agent),
	)
	start := time.Now()
	operation := "create_memory"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, map[string]string{"operation": operation}), time.Since(start))
		span.End()
	}()

	logger, err := s.validateRepositoryAccess(ctx, logger, operation, memory.Source.User, repository)
	if err != nil {
		return err
	}

	// Resolve billing entity and stamp it on the memory at creation time.
	err = s.resolveBillingEntityForCreate(ctx, memory, int64(memory.Source.User.ID))
	if err != nil {
		return err
	}

	err = s.scanRepositoryMemoryForSecrets(ctx, logger, operation, memory.Source.User, repository, memory)
	if err != nil {
		return err
	}

	// Record memory content size for capacity planning
	contentSize := len(memory.Subject) + len(memory.Fact) + len(memory.Reason)
	for _, citation := range memory.Citations {
		contentSize += len(citation)
	}
	s.obsv.Distribution(ctx, metricMemoryContentSize, MetricTags(ctx, map[string]string{"agent": memory.Source.Agent}), float64(contentSize))

	s.obsv.Increment(ctx, "memory_service.create_memory.count", MetricTags(ctx, map[string]string{"agent": memory.Source.Agent}))
	memory.Scope = MemoryScopeRepository
	err = s.store.SaveForRepository(ctx, repository.ID, memory)
	if err != nil {
		logger.WithError(err).Error("failed to save memory to store")
		return err
	}
	s.recordVotesPerMemory(ctx, memory)
	logger.WithFields(kvp.String("memory_id", memory.ID.String())).Info("memory created successfully")
	return nil
}

// GetMemories retrieves all memories for a given repository.
// The repository parameter should be pre-fetched by the caller to avoid
// authorization issues with different token types.
func (s *memoryService) GetMemories(ctx context.Context, user User, repository *Repository) ([]*Memory, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.GetMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
	)
	start := time.Now()
	operation := "get_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, map[string]string{"operation": operation}), time.Since(start))
		span.End()
	}()

	logger, err := s.validateRepositoryAccess(ctx, logger, operation, user, repository)
	if err != nil {
		return nil, err
	}

	memories, err := s.store.FindByRepository(ctx, repository.ID)
	if err != nil {
		logger.WithError(err).Error("failed to fetch memories from store")
		s.recordServiceError(ctx, operation, "store_fetch_failed")
		return nil, err
	}

	rawCount := len(memories)
	if s.isVotingEnabledForUserOrRepo(ctx, int64(user.ID), int64(repository.ID)) {
		memories = SortByScore(memories, time.Now().UTC())
	}

	err = s.recordMemoryFetchMetrics(ctx, logger, operation, rawCount, len(memories))
	if err != nil {
		return nil, err
	}
	return memories, nil
}

// GetRecentMemories retrieves the most recent N memories for a given repository.
// The repository parameter should be pre-fetched by the caller to avoid
// authorization issues with different token types.
func (s *memoryService) GetRecentMemories(ctx context.Context, user User, repository *Repository, limit uint) ([]*Memory, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.GetRecentMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
		kvp.Uint("limit", limit),
	)
	start := time.Now()
	operation := "get_recent_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, map[string]string{"operation": operation}), time.Since(start))
		span.End()
	}()

	logger, err := s.validateRepositoryAccess(ctx, logger, operation, user, repository)
	if err != nil {
		return nil, err
	}

	memories, err := s.store.FindRecentByRepository(ctx, repository.ID, limit)
	if err != nil {
		logger.WithError(err).Error("failed to get recent memories")
		s.recordServiceError(ctx, operation, "store_fetch_failed")
		return nil, goerrors.Errorf("failed to get recent memories: %w", err)
	}

	err = s.recordMemoryFetchMetrics(ctx, logger, operation, len(memories), len(memories))
	if err != nil {
		return nil, err
	}
	return memories, nil
}

// GetTopMemories retrieves the top N memories by score for a given repository.
// It fetches all memories, scores and ranks them, then returns the top `limit`.
// The repository parameter should be pre-fetched by the caller to avoid
// authorization issues with different token types.
func (s *memoryService) GetTopMemories(ctx context.Context, user User, repository *Repository, limit uint) ([]*Memory, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.GetTopMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
		kvp.Uint("limit", limit),
	)
	start := time.Now()
	operation := "get_top_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, map[string]string{"operation": operation}), time.Since(start))
		span.End()
	}()

	logger, err := s.validateRepositoryAccess(ctx, logger, operation, user, repository)
	if err != nil {
		return nil, err
	}

	memories, err := s.store.FindByRepository(ctx, repository.ID)
	if err != nil {
		logger.WithError(err).Error("failed to fetch memories from store")
		s.recordServiceError(ctx, operation, "store_fetch_failed")
		return nil, goerrors.Errorf("failed to get top memories: %w", err)
	}

	rawCount := len(memories)
	memories = SortByScore(memories, time.Now().UTC())

	if uint(len(memories)) > limit {
		memories = memories[:limit]
	}

	err = s.recordMemoryFetchMetrics(ctx, logger, operation, rawCount, len(memories))
	if err != nil {
		return nil, err
	}
	return memories, nil
}

// DeleteMemory deletes a specific memory by ID.
// The repository parameter should be pre-fetched by the caller to avoid
// authorization issues with different token types.
func (s *memoryService) DeleteMemory(ctx context.Context, user User, repository *Repository, memoryID MemoryID) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.DeleteMemory")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
		kvp.String("memory_id", memoryID.String()),
	)
	start := time.Now()
	operation := "delete_memory"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, map[string]string{"operation": operation}), time.Since(start))
		span.End()
	}()

	logger, err := s.validateRepositoryAccess(ctx, logger, operation, user, repository)
	if err != nil {
		return err
	}

	s.obsv.Increment(ctx, "memory_service.delete_memory.count", MetricTags(ctx, nil))
	err = s.store.DeleteForRepository(ctx, repository.ID, memoryID)
	if err != nil {
		logger.WithError(err).Error("failed to delete memory")
		return err
	}
	logger.Info("memory deleted successfully")
	return nil
}

// DeleteMemories deletes a batch of memories by their IDs.
// The repository parameter should be pre-fetched by the caller to avoid
// authorization issues with different token types.
func (s *memoryService) DeleteMemories(ctx context.Context, user User, repository *Repository, memoryIDs []MemoryID) (*BatchDeleteResult, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.DeleteMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
		kvp.Int("memory_ids_count", len(memoryIDs)),
	)
	start := time.Now()
	operation := "delete_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, map[string]string{"operation": operation}), time.Since(start))
		span.End()
	}()

	logger, err := s.validateRepositoryAccess(ctx, logger, operation, user, repository)
	if err != nil {
		return nil, err
	}

	s.obsv.Increment(ctx, "memory_service.delete_memories.count", MetricTags(ctx, nil))
	result, err := s.store.DeleteBatchForRepository(ctx, repository.ID, memoryIDs)
	if err != nil {
		logger.WithError(err).Error("failed to delete memories")
		s.recordServiceError(ctx, operation, "delete_batch_failed")
		return result, goerrors.Errorf("failed to delete memories: %w", err)
	}

	logger.Info("memories deleted successfully")
	return result, nil
}

// DeleteAllMemories deletes all memories for a repository.
// The repository parameter should be pre-fetched by the caller to avoid
// authorization issues with different token types.
func (s *memoryService) DeleteAllMemories(ctx context.Context, user User, repository *Repository) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.DeleteAllMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
	)
	start := time.Now()
	operation := "delete_all_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, map[string]string{"operation": operation}), time.Since(start))
		span.End()
	}()

	logger, err := s.validateRepositoryAccess(ctx, logger, operation, user, repository)
	if err != nil {
		return err
	}

	s.obsv.Increment(ctx, "memory_service.delete_all_memories.requests", MetricTags(ctx, nil))
	err = s.store.DeleteAllForRepository(ctx, repository.ID)
	if err != nil {
		logger.WithError(err).Error("failed to delete all memories")
		s.recordServiceError(ctx, operation, "delete_all_failed")
		return goerrors.Errorf("failed to delete all memories: %w", err)
	}

	logger.Info("all memories deleted")
	return nil
}

// CheckMemoryEnabled checks if the memory feature is enabled for the given user ID and repository.
func (s *memoryService) CheckMemoryEnabled(ctx context.Context, userID int64, repository *Repository) (bool, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.CheckMemoryEnabled")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Int64("user_id", userID),
		kvp.Int64("repo_id", repository.GetRepositoryID()),
		kvp.Int64("owner_id", repository.GetOwnerID()),
	)
	start := time.Now()
	operation := "check_memory_enabled"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, map[string]string{"operation": operation}), time.Since(start))
		span.End()
	}()

	// If we cannot perform enablement check, we consider the feature disabled (safer default)
	if s.enablementChecker == nil {
		logger.Info("enablement checker not configured, defaulting to disabled")
		return false, nil
	}

	enabled, err := s.enablementChecker.IsMemoryEnabled(ctx, userID)
	if err != nil {
		logger.WithError(err).Warn("failed to check memory enablement")
		s.recordServiceError(ctx, operation, "enablement_check_failed")
		return false, goerrors.Errorf("failed to check memory enablement: %w", err)
	}

	// Invariant: the predicate used by the probe (CheckMemoryEnabled) and the
	// gate (validateRepositoryAccess) must be
	// identical. Otherwise the UI/agent prompt that calls this probe to decide
	// whether to surface memory features can disagree with the backend
	// enforcement that runs on every read/write/vote, leading to confusing
	// "memory works for some operations but not others" behaviour.
	if !s.repositoryMemoryFlagsAllow(ctx, userID, repository) {
		logger.Info("memory feature flag disabled")
		return false, nil
	}
	if s.repositoryMemoryDisallowed(ctx, userID, repository) {
		logger.Info("memory repository disallowed")
		return false, nil
	}

	logger.WithFields(kvp.Bool("enabled", enabled)).Info("memory enablement checked")
	return enabled, nil
}

// VoteOnMemory reads a memory by its fact text, adds a vote, and persists the result.
func (s *memoryService) VoteOnMemory(ctx context.Context, user User, repository *Repository, fact string, vote *Vote) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.VoteOnMemory")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
	)
	start := time.Now()
	operation := "vote_memory"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, map[string]string{"operation": operation}), time.Since(start))
		span.End()
	}()

	logger, err := s.validateRepositoryAccess(ctx, logger, operation, user, repository)
	if err != nil {
		return err
	}

	if !s.isVotingEnabledForUserOrRepo(ctx, int64(user.ID), int64(repository.ID)) {
		logger.Info("memory voting feature not enabled")
		s.recordServiceError(ctx, operation, "voting_not_enabled")
		return ErrFeatureNotEnabled
	}

	storeOps := voteStoreOps{
		findByFact: func(ctx context.Context, fact string) ([]*Memory, error) {
			return s.store.FindByFactForRepository(ctx, repository.ID, fact)
		},
		saveBatch: func(ctx context.Context, memories []*Memory) error {
			return s.store.SaveBatchForRepository(ctx, repository.ID, memories)
		},
		expectedScope: MemoryScopeRepository,
		lookupMetric:  "memory_service.fact_lookup",
		successMetric: "memory_service.vote_memory.count",
		retryMetric:   "memory_service.vote_memory.concurrency_retry",
	}

	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentMemoryAsyncVoting, int64(user.ID), int64(repository.ID)) {
		bgCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), asyncVoteTimeout)
		s.obsv.Increment(ctx, metricVoteAsyncLaunched, MetricTags(ctx, stats.Tags{"scope": "repository"}))
		go func() {
			defer cancel()
			defer func() {
				if r := recover(); r != nil {
					logger.WithFields(kvp.Any("panic", r)).Error("panic in async vote goroutine")
					s.obsv.Increment(bgCtx, metricVoteAsyncError, MetricTags(bgCtx, stats.Tags{"scope": "repository", "reason": "panic"}))
				}
			}()

			scanCandidate := &Memory{
				Fact:   fact,
				Reason: vote.Source.Reason,
			}
			err := s.scanRepositoryMemoryForSecrets(bgCtx, logger, operation, user, repository, scanCandidate)
			if err != nil {
				logger.WithError(err).Warn("async vote blocked by secret scanning")
				s.obsv.Increment(bgCtx, metricVoteAsyncError, MetricTags(bgCtx, stats.Tags{"scope": "repository", "reason": "secret_scan"}))
				return
			}

			err = s.executeVote(bgCtx, logger, operation, fact, vote, storeOps)
			if err != nil {
				logger.WithError(err).Warn("async vote execution failed")
				s.obsv.Increment(bgCtx, metricVoteAsyncError, MetricTags(bgCtx, stats.Tags{"scope": "repository", "reason": "execute_vote"}))
			}
		}()
		return nil
	}

	// Synchronous path.
	scanCandidate := &Memory{
		Fact:   fact,
		Reason: vote.Source.Reason,
	}
	err = s.scanRepositoryMemoryForSecrets(ctx, logger, operation, user, repository, scanCandidate)
	if err != nil {
		return err
	}

	return s.executeVote(ctx, logger, operation, fact, vote, storeOps)
}

// CountMemories returns the total number of memories stored for a given repository.
func (s *memoryService) CountMemories(ctx context.Context, user User, repository *Repository) (int, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.CountMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
	)
	start := time.Now()
	operation := "count_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	logger, err := s.validateRepositoryAccess(ctx, logger, operation, user, repository)
	if err != nil {
		return 0, err
	}

	count, err := s.store.CountByRepository(ctx, repository.ID)
	if err != nil {
		logger.WithError(err).Warn("failed to count memories for repository")
		s.recordServiceError(ctx, operation, "count_failed")
		return 0, err
	}

	s.obsv.Distribution(ctx, metricTotalMemoriesPerRepository, MetricTags(ctx, nil), float64(count))

	return count, nil
}

// CountUserMemories returns the total number of memories stored for a user.
// When query.BillingFilter is set, only memories matching that billing entity are counted.
func (s *memoryService) CountUserMemories(ctx context.Context, user User, query UserMemoryQuery) (int, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.CountUserMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
	)
	start := time.Now()
	operation := "count_user_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	err := s.validateUserAccess(ctx, logger, operation, user)
	if err != nil {
		return 0, err
	}

	count, err := s.store.CountByUser(ctx, user.ID, query.BillingFilter)
	if err != nil {
		logger.WithError(err).Warn("failed to count memories for user")
		s.recordServiceError(ctx, operation, "count_failed")
		return 0, err
	}

	s.obsv.Distribution(ctx, metricTotalMemoriesPerUser, MetricTags(ctx, nil), float64(count))

	return count, nil
}

// CreateUserMemory saves a new memory scoped to a user.
func (s *memoryService) CreateUserMemory(ctx context.Context, memory *Memory, user User) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.CreateUserMemory")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
		kvp.String("agent", memory.Source.Agent),
	)
	start := time.Now()
	operation := "create_user_memory"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	err := s.validateUserAccess(ctx, logger, operation, user)
	if err != nil {
		return err
	}

	// Resolve billing entity and stamp it on the memory at creation time.
	err = s.resolveBillingEntityForCreate(ctx, memory, int64(user.ID))
	if err != nil {
		return err
	}

	err = s.scanUserMemoryForSecrets(ctx, logger, operation, user, memory.Source.NWO, memory)
	if err != nil {
		return err
	}

	contentSize := len(memory.Subject) + len(memory.Fact) + len(memory.Reason)
	for _, citation := range memory.Citations {
		contentSize += len(citation)
	}
	s.obsv.Distribution(ctx, metricMemoryContentSize, MetricTags(ctx, stats.Tags{"agent": memory.Source.Agent}), float64(contentSize))

	s.obsv.Increment(ctx, "memory_service.create_user_memory.count", MetricTags(ctx, stats.Tags{"agent": memory.Source.Agent}))
	memory.Scope = MemoryScopeUser
	err = s.store.SaveForUser(ctx, user.ID, memory)
	if err != nil {
		logger.WithError(err).Error("failed to save user memory to store")
		return err
	}
	logger.WithFields(kvp.String("memory_id", memory.ID.String())).Info("user memory created successfully")
	return nil
}

// GetUserMemories retrieves all memories for a given user.
func (s *memoryService) GetUserMemories(ctx context.Context, user User, query UserMemoryQuery) ([]*Memory, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.GetUserMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
	)
	start := time.Now()
	operation := "get_user_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	err := s.validateUserAccess(ctx, logger, operation, user)
	if err != nil {
		return nil, err
	}

	memories, err := s.store.FindByUser(ctx, user.ID, query.BillingFilter)
	if err != nil {
		logger.WithError(err).Error("failed to fetch user memories from store")
		s.recordServiceError(ctx, operation, "store_fetch_failed")
		return nil, goerrors.Errorf("failed to fetch user memories: %w", err)
	}

	rawCount := len(memories)
	if s.isVotingEnabledForUser(ctx, int64(user.ID)) {
		memories = SortByScore(memories, time.Now().UTC())
	}

	err = s.recordUserMemoryFetchMetrics(ctx, logger, operation, rawCount, len(memories))
	if err != nil {
		return nil, err
	}
	return memories, nil
}

// GetRecentUserMemories retrieves the most recent N memories for a given user.
// When query.BillingFilter is set, results are filtered by billing entity at the DB level.
func (s *memoryService) GetRecentUserMemories(ctx context.Context, user User, limit uint, query UserMemoryQuery) ([]*Memory, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.GetRecentUserMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
		kvp.Uint("limit", limit),
	)
	start := time.Now()
	operation := "get_recent_user_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	err := s.validateUserAccess(ctx, logger, operation, user)
	if err != nil {
		return nil, err
	}

	memories, err := s.store.FindRecentByUser(ctx, user.ID, limit, query.BillingFilter)
	if err != nil {
		logger.WithError(err).Error("failed to get recent user memories")
		s.recordServiceError(ctx, operation, "store_fetch_failed")
		return nil, goerrors.Errorf("failed to get recent user memories: %w", err)
	}

	err = s.recordUserMemoryFetchMetrics(ctx, logger, operation, len(memories), len(memories))
	if err != nil {
		return nil, err
	}

	s.backfillUserMemoryBillingEntities(ctx, logger, user.ID, memories)

	return memories, nil
}

// GetTopUserMemories retrieves the top N user memories by score.
// It fetches all memories, scores and ranks them, then returns the top `limit`.
// When query.BillingFilter is set, results are filtered by billing entity at the DB level.
func (s *memoryService) GetTopUserMemories(ctx context.Context, user User, limit uint, query UserMemoryQuery) ([]*Memory, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.GetTopUserMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
		kvp.Uint("limit", limit),
	)
	start := time.Now()
	operation := "get_top_user_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	err := s.validateUserAccess(ctx, logger, operation, user)
	if err != nil {
		return nil, err
	}

	memories, err := s.store.FindByUser(ctx, user.ID, query.BillingFilter)
	if err != nil {
		logger.WithError(err).Error("failed to fetch user memories from store")
		s.recordServiceError(ctx, operation, "store_fetch_failed")
		return nil, goerrors.Errorf("failed to get top user memories: %w", err)
	}

	rawCount := len(memories)
	memories = SortByScore(memories, time.Now().UTC())

	if uint(len(memories)) > limit {
		memories = memories[:limit]
	}

	err = s.recordUserMemoryFetchMetrics(ctx, logger, operation, rawCount, len(memories))
	if err != nil {
		return nil, err
	}

	s.backfillUserMemoryBillingEntities(ctx, logger, user.ID, memories)

	return memories, nil
}

// ListBillingEntityMemories retrieves one billing-scoped page of user-scoped memories.
func (s *memoryService) ListBillingEntityMemories(ctx context.Context, filter BillingEntityMemoryFilter, pageRequest MemoryPageRequest) (*MemoryPage, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.ListBillingEntityMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("billing_org_id", filter.OrganizationID),
		kvp.Uint64("billing_enterprise_id", filter.EnterpriseID),
		kvp.Uint64("user_id", filter.UserID),
		kvp.Uint("limit", pageRequest.Limit),
	)
	start := time.Now()
	operation := "list_billing_entity_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	if filter.IsZero() {
		logger.Warn("billing entity memory billing filter is empty")
		s.recordServiceError(ctx, operation, "invalid_billing_filter")
		return nil, ErrInvalidBillingFilter
	}
	if filter.UserID == 0 {
		logger.Warn("billing entity memory user filter is empty")
		s.recordServiceError(ctx, operation, "invalid_user_filter")
		return nil, ErrInvalidUserFilter
	}
	if pageRequest.SnapshotTime.IsZero() {
		logger.Warn("billing entity memory snapshot time is empty")
		s.recordServiceError(ctx, operation, "invalid_snapshot_time")
		return nil, ErrInvalidSnapshotTime
	}

	page, err := s.store.ListBillingEntityMemories(ctx, filter, pageRequest)
	if err != nil {
		logger.WithError(err).Error("failed to fetch billing entity memories from store")
		s.recordServiceError(ctx, operation, "store_fetch_failed")
		return nil, goerrors.Errorf("failed to fetch billing entity memories: %w", err)
	}

	memoriesCount := 0
	if page != nil {
		memoriesCount = len(page.Memories)
	}
	logger.WithFields(kvp.Int("memories_count", memoriesCount)).Info("billing entity memories fetched")
	return page, nil
}

// DeleteBillingEntityMemories deletes one billing-scoped page of user-scoped memories.
func (s *memoryService) DeleteBillingEntityMemories(ctx context.Context, filter BillingEntityMemoryFilter, pageRequest MemoryPageRequest) (*BillingEntityDeleteResult, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.DeleteBillingEntityMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("billing_org_id", filter.OrganizationID),
		kvp.Uint64("billing_enterprise_id", filter.EnterpriseID),
		kvp.Uint64("user_id", filter.UserID),
		kvp.Uint("limit", pageRequest.Limit),
	)
	start := time.Now()
	operation := "delete_billing_entity_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	if filter.IsZero() {
		logger.Warn("billing entity memory billing filter is empty")
		s.recordServiceError(ctx, operation, "invalid_billing_filter")
		return nil, ErrInvalidBillingFilter
	}
	if filter.UserID == 0 {
		logger.Warn("billing entity memory user filter is empty")
		s.recordServiceError(ctx, operation, "invalid_user_filter")
		return nil, ErrInvalidUserFilter
	}
	if pageRequest.SnapshotTime.IsZero() {
		logger.Warn("billing entity memory snapshot time is empty")
		s.recordServiceError(ctx, operation, "invalid_snapshot_time")
		return nil, ErrInvalidSnapshotTime
	}

	result, err := s.store.DeleteBillingEntityMemories(ctx, filter, pageRequest)
	if err != nil {
		logger.WithError(err).Error("failed to delete billing entity memories from store")
		s.recordServiceError(ctx, operation, "store_delete_failed")
		return nil, goerrors.Errorf("failed to delete billing entity memories: %w", err)
	}

	if result == nil {
		result = &BillingEntityDeleteResult{}
	}
	logger.WithFields(kvp.Uint("deleted_count", result.DeletedCount)).Info("billing entity memories deleted")
	return result, nil
}

// DeleteUserMemory deletes a specific user-scoped memory by ID.
func (s *memoryService) DeleteUserMemory(ctx context.Context, user User, memoryID MemoryID) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.DeleteUserMemory")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
		kvp.String("memory_id", memoryID.String()),
	)
	start := time.Now()
	operation := "delete_user_memory"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	err := s.validateUserAccess(ctx, logger, operation, user)
	if err != nil {
		return err
	}

	s.obsv.Increment(ctx, "memory_service.delete_user_memory.count", MetricTags(ctx, nil))
	err = s.store.DeleteForUser(ctx, user.ID, memoryID)
	if err != nil {
		logger.WithError(err).Error("failed to delete user memory")
		return err
	}
	logger.Info("user memory deleted successfully")
	return nil
}

// DeleteUserMemories deletes a batch of user-scoped memories by their IDs.
func (s *memoryService) DeleteUserMemories(ctx context.Context, user User, memoryIDs []MemoryID) (*BatchDeleteResult, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.DeleteUserMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
		kvp.Int("memory_ids_count", len(memoryIDs)),
	)
	start := time.Now()
	operation := "delete_user_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	err := s.validateUserAccess(ctx, logger, operation, user)
	if err != nil {
		return nil, err
	}

	s.obsv.Increment(ctx, "memory_service.delete_user_memories.count", MetricTags(ctx, nil))
	result, err := s.store.DeleteBatchForUser(ctx, user.ID, memoryIDs)
	if err != nil {
		logger.WithError(err).Error("failed to delete user memories")
		s.recordServiceError(ctx, operation, "delete_batch_failed")
		return result, goerrors.Errorf("failed to delete user memories: %w", err)
	}
	logger.Info("user memories deleted successfully")
	return result, nil
}

// DeleteAllUserMemories deletes all memories for a user.
func (s *memoryService) DeleteAllUserMemories(ctx context.Context, user User) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.DeleteAllUserMemories")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
	)
	start := time.Now()
	operation := "delete_all_user_memories"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	err := s.validateUserAccess(ctx, logger, operation, user)
	if err != nil {
		return err
	}

	s.obsv.Increment(ctx, "memory_service.delete_all_user_memories.requests", MetricTags(ctx, nil))
	err = s.store.DeleteAllForUser(ctx, user.ID)
	if err != nil {
		logger.WithError(err).Error("failed to delete all user memories")
		s.recordServiceError(ctx, operation, "delete_all_failed")
		return goerrors.Errorf("failed to delete all user memories: %w", err)
	}

	logger.Info("all user memories deleted")
	return nil
}

// CheckUserMemoryEnabled checks if user-scoped memory is enabled for the given user ID.
func (s *memoryService) CheckUserMemoryEnabled(ctx context.Context, userID int64) (bool, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.CheckUserMemoryEnabled")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Int64("user_id", userID),
	)
	start := time.Now()
	operation := "check_user_memory_enabled"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, stats.Tags{"operation": operation}), time.Since(start))
		span.End()
	}()

	if s.enablementChecker == nil {
		logger.Warn("enablement checker not configured, defaulting to disabled")
		return false, nil
	}

	enabled, err := s.enablementChecker.IsMemoryEnabled(ctx, userID)
	if err != nil {
		logger.WithError(err).Warn("failed to check memory enablement")
		s.recordServiceError(ctx, operation, "enablement_check_failed")
		return false, goerrors.Errorf("failed to check memory enablement: %w", err)
	}

	err = s.checkUserMemoryFeatureFlags(ctx, logger, operation, userID)
	if err != nil {
		logger.WithError(err).Warn("user memory feature flag check failed")
		return false, nil
	}

	logger.WithFields(kvp.Bool("enabled", enabled)).Info("user memory enablement checked")
	return enabled, nil
}

// VoteOnUserMemory reads a user-scoped memory by its fact text, adds a vote, and persists the result.
func (s *memoryService) VoteOnUserMemory(ctx context.Context, user User, fact string, vote *Vote) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.VoteOnUserMemory")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Uint64("user_id", user.ID),
	)
	start := time.Now()
	operation := "vote_user_memory"
	defer func() {
		s.obsv.DistributionMs(ctx, metricServiceOperationDuration, MetricTags(ctx, map[string]string{"operation": operation}), time.Since(start))
		span.End()
	}()

	err := s.validateUserAccess(ctx, logger, operation, user)
	if err != nil {
		return err
	}

	if !s.isVotingEnabledForUser(ctx, int64(user.ID)) {
		logger.Info("memory voting feature not enabled for user")
		s.recordServiceError(ctx, operation, "voting_not_enabled")
		return ErrFeatureNotEnabled
	}

	storeOps := voteStoreOps{
		findByFact: func(ctx context.Context, fact string) ([]*Memory, error) {
			return s.store.FindByFactForUser(ctx, user.ID, fact)
		},
		saveBatch: func(ctx context.Context, memories []*Memory) error {
			return s.store.SaveBatchForUser(ctx, user.ID, memories)
		},
		expectedScope: MemoryScopeUser,
		lookupMetric:  "memory_service.user_fact_lookup",
		successMetric: "memory_service.vote_user_memory.count",
		retryMetric:   "memory_service.vote_user_memory.concurrency_retry",
	}

	if s.featureFlagClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentMemoryAsyncVoting, int64(user.ID)) {
		bgCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), asyncVoteTimeout)
		s.obsv.Increment(ctx, metricVoteAsyncLaunched, MetricTags(ctx, stats.Tags{"scope": "user"}))
		go func() {
			defer cancel()
			defer func() {
				if r := recover(); r != nil {
					logger.WithFields(kvp.Any("panic", r)).Error("panic in async user vote goroutine")
					s.obsv.Increment(bgCtx, metricVoteAsyncError, MetricTags(bgCtx, stats.Tags{"scope": "user", "reason": "panic"}))
				}
			}()

			scanCandidate := &Memory{
				Fact:   fact,
				Reason: vote.Source.Reason,
			}
			err := s.scanUserMemoryForSecrets(bgCtx, logger, operation, user, vote.Source.RepoNWO, scanCandidate)
			if err != nil {
				logger.WithError(err).Warn("async user vote blocked by secret scanning")
				s.obsv.Increment(bgCtx, metricVoteAsyncError, MetricTags(bgCtx, stats.Tags{"scope": "user", "reason": "secret_scan"}))
				return
			}

			err = s.executeVote(bgCtx, logger, operation, fact, vote, storeOps)
			if err != nil {
				logger.WithError(err).Warn("async user vote execution failed")
				s.obsv.Increment(bgCtx, metricVoteAsyncError, MetricTags(bgCtx, stats.Tags{"scope": "user", "reason": "execute_vote"}))
			}
		}()
		return nil
	}

	// Synchronous path.
	scanCandidate := &Memory{
		Fact:   fact,
		Reason: vote.Source.Reason,
	}
	err = s.scanUserMemoryForSecrets(ctx, logger, operation, user, vote.Source.RepoNWO, scanCandidate)
	if err != nil {
		return err
	}

	return s.executeVote(ctx, logger, operation, fact, vote, storeOps)
}

// voteStoreOps holds the scope-specific store operations and metric names
// used by executeVote to abstract over repository vs user scoped voting.
type voteStoreOps struct {
	findByFact    func(ctx context.Context, fact string) ([]*Memory, error)
	saveBatch     func(ctx context.Context, memories []*Memory) error
	expectedScope MemoryScope
	lookupMetric  string
	successMetric string
	retryMetric   string
}

// executeVote validates the vote, then performs a read-modify-write loop with
// optimistic concurrency retry. The caller is responsible for access validation
// and feature flag checks before calling this method.
//
// Invariant: every memory returned by findByFact must carry either the scope
// expected by ops.expectedScope or no scope at all (for legacy/in-memory test
// stores). A concrete mismatch indicates a store-layer bug or scope confusion
// that would let a user vote mutate a repository memory (or vice versa). The
// mismatch is treated as ErrMemoryNotFound to avoid leaking the wrong-scope row.
func (s *memoryService) executeVote(ctx context.Context, logger log.Logger, operation, fact string, vote *Vote, ops voteStoreOps) error {
	if vote == nil {
		logger.Warn("nil vote provided")
		s.recordServiceError(ctx, operation, "nil_vote")
		return goerrors.New("memory vote cannot be nil")
	}
	if !vote.Direction.IsValid() {
		logger.Warn("invalid vote direction")
		s.recordServiceError(ctx, operation, "invalid_vote_direction")
		return ErrInvalidVoteDirection
	}

	const maxRetries = 3
	for attempt := range maxRetries {
		memories, err := ops.findByFact(ctx, fact)
		if err != nil {
			logger.WithError(err).Warn("failed to find memories for voting")
			return err
		}
		if len(memories) == 0 {
			logger.Info("memories not found by fact")
			s.obsv.Increment(ctx, ops.lookupMetric, MetricTags(ctx, map[string]string{"result": "not_found"}))
			return ErrMemoryFactNotFound
		}
		for _, memory := range memories {
			if memory == nil {
				logger.Error("nil memory returned by findByFact")
				s.recordServiceError(ctx, operation, "nil_memory")
				return ErrMemoryNotFound
			}
			if ops.expectedScope != "" && memory.Scope != "" && memory.Scope != ops.expectedScope {
				logger.WithFields(
					kvp.String("expected_scope", string(ops.expectedScope)),
					kvp.String("actual_scope", string(memory.Scope)),
				).Error("scope mismatch on memory returned by findByFact")
				s.recordServiceError(ctx, operation, "scope_mismatch")
				return ErrMemoryNotFound
			}
		}
		s.obsv.Increment(ctx, ops.lookupMetric, MetricTags(ctx, map[string]string{"result": "found"}))

		// Upvote: apply to the highest-scored memory using the same ranking
		// the user sees in GetTopMemories (decayed score, tiebroken by
		// CreatedAt). When there are duplicate facts this avoids voting on
		// the most-recently-updated memory, which is not necessarily the one
		// shown to the user.
		// Downvote: apply to all memories with matching fact, least-recently-updated first.
		targets := memories[:1]
		if vote.Direction == DownVote {
			targets = memories
		} else if len(memories) > 1 {
			ranked := SortByScore(append([]*Memory(nil), memories...), nowFunc())
			if len(ranked) == 0 {
				// All duplicates have a negative decayed score, so there is
				// no valid memory to upvote.
				logger.Info("no positively-scored memory to upvote")
				s.obsv.Increment(ctx, ops.lookupMetric, MetricTags(ctx, map[string]string{"result": "all_negative"}))
				return ErrMemoryFactNotFound
			}
			targets = ranked[:1]
		}

		// Apply votes in reverse order (oldest first) so that each memory
		// receives a strictly increasing timestamp. This preserves the relative
		// update order.
		baseTime := nowFunc()
		for i := len(targets) - 1; i >= 0; i-- {
			v := *vote
			v.Timestamp = baseTime.Add(time.Duration(len(targets)-1-i) * time.Nanosecond)
			err := targets[i].AddVote(v)
			if err != nil {
				return err
			}
		}

		err = ops.saveBatch(ctx, targets)
		if err != nil {
			if errors.Is(err, ErrConcurrencyConflict) {
				if attempt < maxRetries-1 {
					logger.WithFields(kvp.Int("attempt", attempt+1)).Warn("concurrency conflict, retrying vote")
					s.obsv.Increment(ctx, ops.retryMetric, MetricTags(ctx, nil))
				}
				continue
			}
			logger.WithError(err).Error("failed to save memories after voting")
			return err
		}

		for _, memory := range targets {
			s.recordVotesPerMemory(ctx, memory)
		}
		s.obsv.Increment(ctx, ops.successMetric, MetricTags(ctx, map[string]string{"direction": vote.Direction.String()}))
		logger.Info("vote added successfully")
		return nil
	}
	logger.Error("exhausted retries for voting due to concurrency conflicts")
	s.recordServiceError(ctx, operation, "concurrency_conflict_exhausted")
	return ErrConcurrencyConflict
}

// scanRepositoryMemoryForSecrets checks repository-scoped memory content for secrets
// when scanning is enabled for the user or repository.
func (s *memoryService) scanRepositoryMemoryForSecrets(
	ctx context.Context,
	logger log.Logger,
	operation string,
	user User,
	repository *Repository,
	memory *Memory,
) error {
	if !s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureSecretScanning, int64(user.ID), int64(repository.ID)) {
		return nil
	}

	return s.scanForSecrets(ctx, logger, operation, repository.NWO, memory)
}

// scanUserMemoryForSecrets checks user-scoped memory content for secrets when
// scanning is enabled for the user. Repo context is optional.
func (s *memoryService) scanUserMemoryForSecrets(
	ctx context.Context,
	logger log.Logger,
	operation string,
	user User,
	repoNWO RepoNWO,
	memory *Memory,
) error {
	if !s.featureFlagClient.IsEnabledForUser(ctx, featureSecretScanning, int64(user.ID)) {
		return nil
	}

	return s.scanForSecrets(ctx, logger, operation, repoNWO, memory)
}

// scanForSecrets performs secret scanning on the given memory payload.
func (s *memoryService) scanForSecrets(
	ctx context.Context,
	logger log.Logger,
	operation string,
	repoNWO RepoNWO,
	memory *Memory,
) error {
	s.obsv.Increment(ctx, metricSecretScanningInvocations, MetricTags(ctx, nil))
	scanStart := time.Now()
	secrets, err := s.secretScanner.Scan(ctx, repoNWO, memory)
	s.obsv.DistributionMs(ctx, metricSecretScanningDuration, MetricTags(ctx, nil), time.Since(scanStart))
	if err != nil {
		logger.WithError(err).Warn("secret scanning failed")
		s.obsv.Increment(ctx, metricSecretScanningFailures, MetricTags(ctx, nil))
		s.recordServiceError(ctx, operation, "secret_scanning_failed")
		return goerrors.Errorf("failed to scan memory for secrets: %w", err)
	}
	if len(secrets) > 0 {
		logger.WithFields(kvp.Int("secrets_found", len(secrets))).Warn("memory contains secrets")
		s.obsv.Increment(ctx, metricSecretScanningBlocked, MetricTags(ctx, nil))
		s.recordServiceError(ctx, operation, "secrets_detected")
		return ErrMemoryContainsSecrets
	}

	return nil
}

// validateRepositoryAccess performs the shared validation checks for all memory
// operations: nil repository guard, memory enablement, feature flags, and
// disallowed repository check. It returns the logger enriched with repo_nwo.
func (s *memoryService) validateRepositoryAccess(
	ctx context.Context,
	logger log.Logger,
	operation string,
	user User,
	repository *Repository,
) (log.Logger, error) {
	if repository == nil {
		logger.Error("repository not found - this indicates a programming error")
		s.recordServiceError(ctx, operation, "repository_not_found")
		return logger, ErrRepositoryNotFound
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repository.NWO.String()))

	err := s.checkMemoryEnabledWithTelemetry(ctx, int64(user.ID))
	if err != nil {
		logger.Info("memory feature not enabled for user")
		s.recordServiceError(ctx, operation, "feature_not_enabled")
		return logger, ErrFeatureNotEnabled
	}

	// Invariant: probe (CheckMemoryEnabled) and gate (this call site) share
	// repositoryMemoryFlagsAllow so the public "is memory enabled?" answer
	// agrees with per-operation enforcement.
	if !s.repositoryMemoryFlagsAllow(ctx, int64(user.ID), repository) {
		logger.Info("memory feature flag disabled")
		s.recordServiceError(ctx, operation, "feature_flag_disabled")
		return logger, ErrFeatureNotEnabled
	}

	if s.repositoryMemoryDisallowed(ctx, int64(user.ID), repository) {
		logger.Info("repository is disallowed")
		s.recordServiceError(ctx, operation, "repository_disallowed")
		return logger, ErrFeatureNotEnabled
	}

	return logger, nil
}

// recordMemoryFetchMetrics records telemetry for repo-scoped memory retrieval operations
// and returns ErrNoMemoriesNotFound if the raw count is zero.
func (s *memoryService) recordMemoryFetchMetrics(
	ctx context.Context,
	logger log.Logger,
	operation string,
	rawCount int,
	filteredCount int,
) error {
	return s.recordFetchMetrics(ctx, logger, operation, rawCount, filteredCount, metricMemoriesPerRepository, metricMemoriesPerRepositoryFiltered)
}

// recordUserMemoryFetchMetrics records telemetry for user-scoped memory retrieval operations
// and returns ErrNoMemoriesNotFound if the raw count is zero.
func (s *memoryService) recordUserMemoryFetchMetrics(
	ctx context.Context,
	logger log.Logger,
	operation string,
	rawCount int,
	filteredCount int,
) error {
	return s.recordFetchMetrics(ctx, logger, operation, rawCount, filteredCount, metricMemoriesPerUser, metricMemoriesPerUserFiltered)
}

// recordFetchMetrics is the shared implementation for recording memory fetch telemetry.
func (s *memoryService) recordFetchMetrics(
	ctx context.Context,
	logger log.Logger,
	operation string,
	rawCount int,
	filteredCount int,
	rawMetric string,
	filteredMetric string,
) error {
	s.obsv.Distribution(ctx, rawMetric, MetricTags(ctx, nil), float64(rawCount))
	if rawCount == 0 {
		logger.Info("no memories found")
		return ErrNoMemoriesNotFound
	}
	s.obsv.Distribution(ctx, filteredMetric, MetricTags(ctx, nil), float64(filteredCount))
	if filteredCount == 0 {
		logger.WithFields(
			kvp.Int("raw_memories_count", rawCount),
		).Info("all memories filtered out by scoring")
		return nil
	}
	logger.WithFields(
		kvp.Int("raw_memories_count", rawCount),
		kvp.Int("memories_count", filteredCount),
	).Info(operation + " completed successfully")
	return nil
}

func (s *memoryService) recordVotesPerMemory(ctx context.Context, memory *Memory) {
	s.obsv.Distribution(ctx, metricVotesPerMemory, MetricTags(ctx, nil), float64(len(memory.Votes)))
}

// checkMemoryEnabledWithTelemetry wraps checkMemoryEnabled with duration tracking.
func (s *memoryService) checkMemoryEnabledWithTelemetry(ctx context.Context, userID int64) error {
	start := time.Now()
	err := s.checkMemoryEnabled(ctx, userID)
	s.obsv.DistributionMs(ctx, metricEnablementCheckDuration, MetricTags(ctx, nil), time.Since(start))
	return err
}

// repositoryMemoryFlagsAllow encapsulates the repository-scoped memory
// feature-flag predicate. It is the single source of truth shared by both the
// probe (CheckMemoryEnabled) and the gate (validateRepositoryAccess), so the
// public "is memory enabled?" answer is guaranteed to agree with the
// per-operation enforcement. The disable flag takes precedence over the
// enable flag, and all three actor levels (user, repo, owner) are consulted.
func (s *memoryService) repositoryMemoryFlagsAllow(ctx context.Context, userID int64, repository *Repository) bool {
	actors := &repositoryWithActor{
		Repository: repository,
		actorID:    userID,
	}
	featureEnabled := s.featureFlagClient.IsEnabledForUserOrRepoOrOwner(ctx, featureMemoryEnabled, actors)
	featureDisabled := s.featureFlagClient.IsEnabledForUserOrRepoOrOwner(ctx, FeatureMemoryDisabled, actors)
	return featureEnabled && !featureDisabled
}

func (s *memoryService) repositoryMemoryDisallowed(ctx context.Context, userID int64, repository *Repository) bool {
	return s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, userID, repository.GetRepositoryID())
}

// validateUserAccess performs the shared validation checks for all user-scoped
// memory operations: memory enablement and feature flags.
func (s *memoryService) validateUserAccess(
	ctx context.Context,
	logger log.Logger,
	operation string,
	user User,
) error {
	err := s.checkMemoryEnabledWithTelemetry(ctx, int64(user.ID))
	if err != nil {
		logger.Info("memory feature not enabled for user")
		s.recordServiceError(ctx, operation, "feature_not_enabled")
		return ErrFeatureNotEnabled
	}

	return s.checkUserMemoryFeatureFlags(ctx, logger, operation, int64(user.ID))
}

// checkUserMemoryFeatureFlags validates that user-scoped memory feature flags allow the operation.
// Returns nil if the operation is allowed, ErrFeatureNotEnabled otherwise.
func (s *memoryService) checkUserMemoryFeatureFlags(ctx context.Context, logger log.Logger, operation string, userID int64) error {
	featureEnabled := s.featureFlagClient.IsEnabledForUser(ctx, featureMemoryEnabled, userID)
	featureDisabled := s.featureFlagClient.IsEnabledForUser(ctx, FeatureMemoryDisabled, userID)
	resolvedFlag, err := UserScopedMemoryFlag(ctx, userID)
	if err != nil {
		logger.WithError(err).Warn("failed to resolve user plan for flag routing",
			kvp.Int64("user_id", userID),
		)
	}
	userScopedEnabled := s.featureFlagClient.IsEnabledForUser(ctx, resolvedFlag, userID)
	if !featureEnabled || featureDisabled || !userScopedEnabled {
		logger.Info("user-scoped memory disabled",
			kvp.Int64("user_id", userID),
			kvp.Bool("feature_enabled", featureEnabled),
			kvp.Bool("feature_disabled", featureDisabled),
			kvp.Bool("user_scoped_enabled", userScopedEnabled),
			kvp.String("user_scoped_flag", resolvedFlag),
		)
		s.recordServiceError(ctx, operation, "feature_flag_disabled")
		return ErrFeatureNotEnabled
	}

	// Some integrations (e.g. CCR) require an additional per-client feature flag
	// beyond the general FeatureUserScopedMemory flag.
	if additionalFlag := UserScopedMemoryFlagFromContext(ctx); additionalFlag != "" {
		if !s.featureFlagClient.IsEnabledForUser(ctx, additionalFlag, userID) {
			logger.Info("user-scoped memory disabled by integration-specific flag",
				kvp.String("additional_flag", additionalFlag),
			)
			s.recordServiceError(ctx, operation, "integration_feature_flag_disabled")
			return ErrFeatureNotEnabled
		}
	}

	return nil
}

// recordServiceError records a service-level error metric with integration ID
// from context (filtered through the known-integration allow-list).
func (s *memoryService) recordServiceError(ctx context.Context, operation, errorType string) {
	s.obsv.Increment(ctx, metricServiceErrorCount, MetricTags(ctx, map[string]string{
		"operation":  operation,
		"error_type": errorType,
	}))
}

// Errors for memory service operations.
var (
	// ErrNoMemoriesNotFound indicates that no memories were found for the given repository.
	ErrNoMemoriesNotFound               = errors.New("no memories found for the given repository")
	ErrRepositoryNotFound               = errors.New("repository not found")
	ErrRepositoryAccessDenied           = errors.New("access to repository denied")
	ErrRepositoryOAuthAccessRestriction = errors.New("access to repository denied due to OAuth App access restrictions")
	ErrFeatureNotEnabled                = errors.New("memories are not enabled for this actor")
	ErrMemoryContainsSecrets            = errors.New("memory contains secrets, cannot be saved")
	ErrSecretScanningRepositoryNotFound = errors.New("repository not found by secret scanning service")
	ErrSecretScanningServiceUnavailable = errors.New("secret scanning service unavailable")
)

var (
	// FeatureMemoryBackfillUserMemoryBillingEntity gates the lazy backfill of billing entity
	// on user memories read from the store. When enabled, memories with (0,0) billing IDs
	// are stamped with the user's current billing entity on read if the user's billing
	// entity is non-zero.
	FeatureMemoryBackfillUserMemoryBillingEntity = "copilot_feature_agentic_memory_backfill_user_memory_billing_entity"
	// FeatureMemoryBillingEnforcedRetrieval gates billing-entity filtering on user memory
	// retrieval for prompt injection. When enabled, only memories matching the user's
	// resolved billing entity are included in the prompt. When disabled, user memories
	// are fetched without billing filtering (pre-billing behavior).
	FeatureMemoryBillingEnforcedRetrieval = "copilot_feature_agentic_memory_billing_enforced_retrieval"
	// FeatureMemoryDisabled is a cross-product flag that disables memory for specific users/repos/orgs.
	// It's exported so the handler can check it early to avoid expensive GitHub API calls.
	FeatureMemoryDisabled  = "copilot-feature-agentic-memory-disabled"
	featureDisallowedRepos = "copilot_swe_agent_disallow"
	featureMemoryEnabled   = "copilot-feature-agentic-memory"
	// FeatureMemoryWithBillingEntity gates billing entity resolution and stamping on memories.
	// When enabled, memory creation resolves and stamps the billing entity, and rejects
	// users with unresolved billing entities (multi-SKU without a default selection).
	FeatureMemoryWithBillingEntity = "copilot_feature_agentic_memory_with_billing_entity"
	featureSecretScanning          = "copilot_swe_agent_memory_secret_scanning" //nolint:gosec // false positive
	// FeatureUserScopedMemory gates user-scoped memory operations.
	// Exported so the handler can check it for prompt guidance.
	FeatureUserScopedMemory = "copilot_feature_agentic_memory_user_scoped"
	// FeatureUserScopedMemoryCCR gates user-scoped memory for Copilot Code Reviews clients.
	// CCR requires both FeatureUserScopedMemory and this flag to be enabled.
	FeatureUserScopedMemoryCCR = "copilot_swe_agent_memory_user_scoped_ccr"
	// FeatureUserScopedMemoryCFI gates user-scoped memory for CfI Pro/Pro+ users.
	// CfI users are routed to this flag; all other users use FeatureUserScopedMemory.
	FeatureUserScopedMemoryCFI = "copilot_feature_agentic_memory_user_scoped_cfi"
)

// isVotingEnabledForUserOrRepo resolves the per-client memory voting feature
// flag from the context and checks it against both user and repo actors.
func (s *memoryService) isVotingEnabledForUserOrRepo(ctx context.Context, userID, repoID int64) bool {
	flag := featureflags.MemoryVotingFlagFromContext(ctx)
	if flag == "" {
		return false
	}
	return s.featureFlagClient.IsEnabledForUserOrRepo(ctx, flag, userID, repoID)
}

// isVotingEnabledForUser resolves the per-client memory voting feature flag
// from the context and checks it against the user actor.
func (s *memoryService) isVotingEnabledForUser(ctx context.Context, userID int64) bool {
	flag := featureflags.MemoryVotingFlagFromContext(ctx)
	if flag == "" {
		return false
	}
	return s.featureFlagClient.IsEnabledForUser(ctx, flag, userID)
}

// resolveBillingEntityForCreate resolves the billing entity and stamps it on the memory.
// Returns a sentinel error if resolution fails or the billing entity is unresolved.
// Skips resolution when the feature flag is disabled or the resolver is nil.
func (s *memoryService) resolveBillingEntityForCreate(ctx context.Context, memory *Memory, userID int64) error {
	if s.billingEntityResolver == nil {
		return nil
	}
	if s.featureFlagClient == nil || !s.featureFlagClient.IsEnabledForUser(ctx, FeatureMemoryWithBillingEntity, userID) {
		return nil
	}

	billingEntity, err := s.billingEntityResolver.ResolveBillingEntity(ctx, userID)
	if err != nil {
		return goerrors.Errorf("%w: %v", ErrBillingEntityResolutionFailed, err)
	}
	if billingEntity.IsUnresolved() {
		return ErrBillingEntityUnresolved
	}
	memory.BillingOrganizationID = billingEntity.OrganizationID
	memory.BillingEnterpriseID = billingEntity.EnterpriseID
	return nil
}

// backfillUserMemoryBillingEntities lazily stamps billing entity on legacy user memories
// that have (0,0) billing IDs. This is best-effort: failures are logged but do not
// affect the response. Only fires when the backfill FF is enabled and the user's
// current billing entity resolves to a non-zero value.
// Given that only Hubbers will have user memories without billing entities, this backfill
// should only apply to a very small subset of users.
func (s *memoryService) backfillUserMemoryBillingEntities(ctx context.Context, logger log.Logger, userID uint64, memories []*Memory) {
	if s.billingEntityResolver == nil {
		return
	}
	if s.featureFlagClient == nil || !s.featureFlagClient.IsEnabledForUser(ctx, FeatureMemoryBackfillUserMemoryBillingEntity, int64(userID)) {
		return
	}

	// Identify memories needing backfill.
	var needsBackfill []*Memory
	for _, m := range memories {
		if m.BillingOrganizationID == 0 && m.BillingEnterpriseID == 0 {
			needsBackfill = append(needsBackfill, m)
		}
	}
	if len(needsBackfill) == 0 {
		return
	}

	// Resolve the user's current billing entity.
	billingEntity, err := s.billingEntityResolver.ResolveBillingEntity(ctx, int64(userID))
	if err != nil {
		logger.WithError(err).Warn("billing backfill: failed to resolve billing entity")
		return
	}
	if billingEntity.IsUnresolved() || billingEntity.IsZero() {
		// CfI user or unresolved — nothing to backfill.
		return
	}

	// Stamp and persist each memory. Best-effort per memory.
	for _, m := range needsBackfill {
		m.BillingOrganizationID = billingEntity.OrganizationID
		m.BillingEnterpriseID = billingEntity.EnterpriseID
		err = s.store.SaveForUser(ctx, userID, m)
		if err != nil {
			// Revert in-memory mutation on failure so the response reflects actual state.
			m.BillingOrganizationID = 0
			m.BillingEnterpriseID = 0
			if errors.Is(err, ErrConcurrencyConflict) {
				logger.WithFields(kvp.String("memory_id", m.ID.String())).
					Info("billing backfill: skipped due to concurrency conflict")
			} else {
				logger.WithError(err).WithFields(kvp.String("memory_id", m.ID.String())).
					Warn("billing backfill: failed to persist")
			}
			continue
		}
	}
}
