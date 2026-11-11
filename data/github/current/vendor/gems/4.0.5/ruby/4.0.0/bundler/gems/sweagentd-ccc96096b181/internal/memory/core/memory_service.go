package core

import (
	"context"
	"errors"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

// Telemetry metric names for memory service operations.
const (
	metricServiceOperationDuration = "memory_service.operation_duration"
	metricServiceErrorCount        = "memory_service.error_count"
	metricSecretScanningDuration   = "memory_service.secret_scanning_duration"
	metricSecretScanningBlocked    = "memory_service.secret_scanning_blocked"
	metricEnablementCheckDuration  = "memory_service.enablement_check_duration"
	metricMemoryContentSize        = "memory_service.memory_content_size"
	metricMemoriesPerRepository    = "memory_service.memories_per_repository"
)

// MemoryService defines the interface for memory management operations.
type MemoryService interface {
	CreateMemory(ctx context.Context, memory *Memory, repository *Repository) error
	GetMemories(ctx context.Context, user User, repository *Repository) ([]*Memory, error)
	GetRecentMemories(ctx context.Context, user User, repository *Repository, limit uint) ([]*Memory, error)
	DeleteMemory(ctx context.Context, user User, repository *Repository, memoryID MemoryID) error
	DeleteAllMemories(ctx context.Context, user User, repository *Repository) error
	CheckMemoryEnabled(ctx context.Context, userID int64) (bool, error)
}

type memoryService struct {
	repo              MemoryRepository
	featureFlagClient featureflags.Client
	secretScanner     SecretScanner
	obsv              observability.Exporters
	enablementChecker MemoryEnablementChecker
}

// NewMemoryService creates a new instance of MemoryService.
func NewMemoryService(
	repo MemoryRepository,
	featureFlagClient featureflags.Client,
	secretScanner SecretScanner,
	obsv observability.Exporters,
	enablementChecker MemoryEnablementChecker,
) MemoryService {
	return &memoryService{
		repo:              repo,
		featureFlagClient: featureFlagClient,
		secretScanner:     secretScanner,
		obsv:              obsv,
		enablementChecker: enablementChecker,
	}
}

// CreateMemory saves a new memory to the repository.
// The repository parameter should be pre-fetched by the caller to avoid
// authorization issues with different token types.
func (s *memoryService) CreateMemory(ctx context.Context, memory *Memory, repository *Repository) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.CreateMemory")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("repo_nwo", memory.Source.NWO.String()),
		kvp.Uint64("user_id", memory.Source.User.ID),
		kvp.String("agent", memory.Source.Agent),
	)
	start := time.Now()
	operation := "create_memory"
	defer func() {
		s.obsv.Statter.DistributionMs(metricServiceOperationDuration, map[string]string{"operation": operation}, time.Since(start))
		span.End()
	}()

	// Defensive check: repository should always be pre-fetched by the handler.
	// If this is nil, it indicates a programming error in the caller.
	if repository == nil {
		logger.Error("repository not found - this indicates a programming error")
		s.recordServiceError(operation, "repository_not_found")
		return ErrRepositoryNotFound
	}

	// Default to "memory disabled" if check fails or user hasn't enabled the feature.
	err := s.checkMemoryEnabledWithTelemetry(ctx, int64(memory.Source.User.ID))
	if err != nil {
		logger.Info("memory feature not enabled for user")
		s.recordServiceError(operation, "feature_not_enabled")
		return ErrFeatureNotEnabled
	}

	featureEnabled := s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryEnabled, int64(memory.Source.User.ID), int64(repository.ID))
	if !featureEnabled {
		logger.Info("memory feature flag disabled")
		s.recordServiceError(operation, "feature_flag_disabled")
		return ErrFeatureNotEnabled
	}

	// Check if the repository is disallowed
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, int64(memory.Source.User.ID), int64(repository.ID)) {
		logger.Info("repository is disallowed")
		s.recordServiceError(operation, "repository_disallowed")
		return ErrFeatureNotEnabled
	}

	// Check if the memory contains secrets
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureSecretScanning, int64(memory.Source.User.ID), int64(repository.ID)) {
		scanStart := time.Now()
		secrets, err := s.secretScanner.Scan(ctx, repository.NWO, *memory)
		s.obsv.Statter.DistributionMs(metricSecretScanningDuration, map[string]string{}, time.Since(scanStart))
		if err != nil {
			logger.WithError(err).Warn("secret scanning failed")
			s.recordServiceError(operation, "secret_scanning_failed")
			return goerrors.Errorf("failed to scan memory for secrets: %w", err)
		}
		if len(secrets) > 0 {
			logger.WithFields(kvp.Int("secrets_found", len(secrets))).Warn("memory contains secrets")
			s.obsv.Statter.Increment(metricSecretScanningBlocked, map[string]string{})
			s.recordServiceError(operation, "secrets_detected")
			return ErrMemoryContainsSecrets
		}
	}

	// Record memory content size for capacity planning
	contentSize := len(memory.Subject) + len(memory.Fact) + len(memory.Reason)
	for _, citation := range memory.Citations {
		contentSize += len(citation)
	}
	s.obsv.Statter.Distribution(metricMemoryContentSize, map[string]string{"agent": memory.Source.Agent}, float64(contentSize))

	s.obsv.Statter.Increment("memory_service.create_memory.count", map[string]string{"agent": memory.Source.Agent})
	err = s.repo.Save(ctx, repository.ID, memory)
	if err != nil {
		logger.WithError(err).Error("failed to save memory to repository")
		return err
	}
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
		s.obsv.Statter.DistributionMs(metricServiceOperationDuration, map[string]string{"operation": operation}, time.Since(start))
		span.End()
	}()

	// Defensive check: repository should always be pre-fetched by the handler.
	// If this is nil, it indicates a programming error in the caller.
	if repository == nil {
		logger.Error("repository not found - this indicates a programming error")
		s.recordServiceError(operation, "repository_not_found")
		return nil, ErrRepositoryNotFound
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repository.NWO.String()))

	err := s.checkMemoryEnabledWithTelemetry(ctx, int64(user.ID))
	if err != nil {
		logger.Info("memory feature not enabled for user")
		s.recordServiceError(operation, "feature_not_enabled")
		return nil, ErrFeatureNotEnabled
	}

	featureEnabled := s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryEnabled, int64(user.ID), int64(repository.ID))
	if !featureEnabled {
		logger.Info("memory feature flag disabled")
		s.recordServiceError(operation, "feature_flag_disabled")
		return nil, ErrFeatureNotEnabled
	}

	// Check if the repository is disallowed
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, int64(user.ID), int64(repository.ID)) {
		logger.Info("repository is disallowed")
		s.recordServiceError(operation, "repository_disallowed")
		return nil, ErrFeatureNotEnabled
	}

	memories, err := s.repo.FindByRepository(ctx, repository.ID)
	if err != nil {
		logger.WithError(err).Error("failed to fetch memories from repository")
		s.recordServiceError(operation, "repository_fetch_failed")
		return nil, err
	}
	// Record memories per repository for saturation monitoring (only on success)
	s.obsv.Statter.Distribution(metricMemoriesPerRepository, map[string]string{}, float64(len(memories)))
	if len(memories) == 0 {
		logger.Info("no memories found")
		return nil, ErrNoMemoriesNotFound
	}
	logger.WithFields(kvp.Int("memories_count", len(memories))).Info("memories retrieved successfully")
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
		s.obsv.Statter.DistributionMs(metricServiceOperationDuration, map[string]string{"operation": operation}, time.Since(start))
		span.End()
	}()

	// Defensive check: repository should always be pre-fetched by the handler.
	// If this is nil, it indicates a programming error in the caller.
	if repository == nil {
		logger.Error("repository not found - this indicates a programming error")
		s.recordServiceError(operation, "repository_not_found")
		return nil, ErrRepositoryNotFound
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repository.NWO.String()))

	err := s.checkMemoryEnabledWithTelemetry(ctx, int64(user.ID))
	if err != nil {
		logger.Info("memory feature not enabled for user")
		s.recordServiceError(operation, "feature_not_enabled")
		return nil, ErrFeatureNotEnabled
	}

	featureEnabled := s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryEnabled, int64(user.ID), int64(repository.ID))
	if !featureEnabled {
		logger.Info("memory feature flag disabled")
		s.recordServiceError(operation, "feature_flag_disabled")
		return nil, ErrFeatureNotEnabled
	}

	// Check if the repository is disallowed
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, int64(user.ID), int64(repository.ID)) {
		logger.Info("repository is disallowed")
		s.recordServiceError(operation, "repository_disallowed")
		return nil, ErrFeatureNotEnabled
	}

	memories, err := s.repo.FindRecentByRepository(ctx, repository.ID, limit)
	if err != nil {
		logger.WithError(err).Error("failed to get recent memories")
		s.recordServiceError(operation, "repository_fetch_failed")
		return nil, goerrors.Errorf("failed to get recent memories: %w", err)
	}
	// Record memories count for recent memories (only on success)
	s.obsv.Statter.Distribution(metricMemoriesPerRepository, map[string]string{}, float64(len(memories)))
	if len(memories) == 0 {
		logger.Info("no memories found")
		return nil, ErrNoMemoriesNotFound
	}
	logger.WithFields(kvp.Int("memories_count", len(memories))).Info("recent memories retrieved successfully")
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
		s.obsv.Statter.DistributionMs(metricServiceOperationDuration, map[string]string{"operation": operation}, time.Since(start))
		span.End()
	}()

	// Defensive check: repository should always be pre-fetched by the handler.
	// If this is nil, it indicates a programming error in the caller.
	if repository == nil {
		logger.Error("repository not found - this indicates a programming error")
		s.recordServiceError(operation, "repository_not_found")
		return ErrRepositoryNotFound
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repository.NWO.String()))

	// First, check if the user has memory enabled
	err := s.checkMemoryEnabledWithTelemetry(ctx, int64(user.ID))
	if err != nil {
		logger.Info("memory feature not enabled for user")
		s.recordServiceError(operation, "feature_not_enabled")
		return ErrFeatureNotEnabled
	}

	// Then check feature flag enablement
	featureEnabled := s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryEnabled, int64(user.ID), int64(repository.ID))
	if !featureEnabled {
		logger.Info("memory feature flag disabled")
		s.recordServiceError(operation, "feature_flag_disabled")
		return ErrFeatureNotEnabled
	}

	// Check if the repository is disallowed
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, int64(user.ID), int64(repository.ID)) {
		logger.Info("repository is disallowed")
		s.recordServiceError(operation, "repository_disallowed")
		return ErrFeatureNotEnabled
	}

	s.obsv.Statter.Increment("memory_service.delete_memory.count", map[string]string{})
	err = s.repo.Delete(ctx, repository.ID, memoryID)
	if err != nil {
		logger.WithError(err).Error("failed to delete memory")
		return err
	}
	logger.Info("memory deleted successfully")
	return nil
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
		s.obsv.Statter.DistributionMs(metricServiceOperationDuration, map[string]string{"operation": operation}, time.Since(start))
		span.End()
	}()

	// Defensive check: repository should always be pre-fetched by the handler.
	// If this is nil, it indicates a programming error in the caller.
	if repository == nil {
		logger.Error("repository not found - this indicates a programming error")
		s.recordServiceError(operation, "repository_not_found")
		return ErrRepositoryNotFound
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repository.NWO.String()))

	err := s.checkMemoryEnabledWithTelemetry(ctx, int64(user.ID))
	if err != nil {
		logger.Info("memory feature not enabled for user")
		s.recordServiceError(operation, "feature_not_enabled")
		return ErrFeatureNotEnabled
	}

	featureEnabled := s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryEnabled, int64(user.ID), int64(repository.ID))
	if !featureEnabled {
		logger.Info("memory feature flag disabled")
		s.recordServiceError(operation, "feature_flag_disabled")
		return ErrFeatureNotEnabled
	}

	// Check if the repository is disallowed
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, int64(user.ID), int64(repository.ID)) {
		logger.Info("repository is disallowed")
		s.recordServiceError(operation, "repository_disallowed")
		return ErrFeatureNotEnabled
	}

	// Get all memories for the repository
	memories, err := s.repo.FindByRepository(ctx, repository.ID)
	if err != nil {
		logger.WithError(err).Error("failed to get memories for deletion")
		s.recordServiceError(operation, "fetch_memories_failed")
		return goerrors.Errorf("failed to get memories for deletion: %w", err)
	}

	// Delete each memory individually
	deletedCount := 0
	for _, memory := range memories {
		err := s.repo.Delete(ctx, repository.ID, memory.ID)
		if err != nil {
			// Log the error but continue deleting other memories
			logger.WithError(err).WithFields(kvp.String("memory_id", memory.ID.String())).Warn("failed to delete individual memory")
			s.obsv.Statter.Increment("memory_service.delete_all_memories.error", map[string]string{"memory_id": memory.ID.String()})
			// You might want to return the error here depending on your requirements
			// For now, we'll continue and try to delete the rest
		} else {
			deletedCount++
		}
	}

	s.obsv.Statter.Distribution("memory_service.delete_all_memories.count", map[string]string{}, float64(deletedCount))
	logger.WithFields(kvp.Int("deleted_count", deletedCount), kvp.Int("total_count", len(memories))).Info("all memories deleted")
	return nil
}

// CheckMemoryEnabled checks if the memory feature is enabled for the given user ID.
func (s *memoryService) CheckMemoryEnabled(ctx context.Context, userID int64) (bool, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.CheckMemoryEnabled")
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Int64("user_id", userID),
	)
	start := time.Now()
	operation := "check_memory_enabled"
	defer func() {
		s.obsv.Statter.DistributionMs(metricServiceOperationDuration, map[string]string{"operation": operation}, time.Since(start))
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
		s.recordServiceError(operation, "enablement_check_failed")
		return false, goerrors.Errorf("failed to check memory enablement: %w", err)
	}

	logger.WithFields(kvp.Bool("enabled", enabled)).Info("memory enablement checked")
	return enabled, nil
}

// checkMemoryEnabledWithTelemetry wraps checkMemoryEnabled with duration tracking.
func (s *memoryService) checkMemoryEnabledWithTelemetry(ctx context.Context, userID int64) error {
	start := time.Now()
	err := s.checkMemoryEnabled(ctx, userID)
	s.obsv.Statter.DistributionMs(metricEnablementCheckDuration, map[string]string{}, time.Since(start))
	return err
}

// recordServiceError records a service-level error metric.
func (s *memoryService) recordServiceError(operation, errorType string) {
	s.obsv.Statter.Increment(metricServiceErrorCount, map[string]string{
		"operation":  operation,
		"error_type": errorType,
	})
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
)

var (
	featureMemoryEnabled   = "copilot-feature-agentic-memory"
	featureSecretScanning  = "copilot_swe_agent_memory_secret_scanning" //nolint:gosec // false positive
	featureDisallowedRepos = "copilot_swe_agent_disallow"
)
