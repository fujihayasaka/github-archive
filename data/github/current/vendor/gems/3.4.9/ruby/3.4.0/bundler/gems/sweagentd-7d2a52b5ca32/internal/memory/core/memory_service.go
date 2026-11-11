package core

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
)

type MemoryService interface {
	CreateMemory(ctx context.Context, memory *Memory) error
	GetMemories(ctx context.Context, user User, repoNWO RepoNWO) ([]*Memory, error)
	GetRecentMemories(ctx context.Context, user User, repoNWO RepoNWO, limit uint) ([]*Memory, error)
	DeleteMemory(ctx context.Context, user User, repoNWO RepoNWO, memoryID MemoryID) error
	DeleteAllMemories(ctx context.Context, user User, repoNWO RepoNWO) error
}

type memoryService struct {
	repo              MemoryRepository
	repositoryStore   RepositoryStore
	featureFlagClient featureflags.Client
	secretScanner     SecretScanner
	obsv              observability.Exporters
}

// NewMemoryService creates a new instance of MemoryService.
func NewMemoryService(repo MemoryRepository, repositoryStore RepositoryStore, featureFlagClient featureflags.Client, secretScanner SecretScanner, obsv observability.Exporters) MemoryService {
	return &memoryService{
		repo:              repo,
		repositoryStore:   repositoryStore,
		featureFlagClient: featureFlagClient,
		secretScanner:     secretScanner,
		obsv:              obsv,
	}
}

// CreateMemory saves a new memory to the repository.
func (s *memoryService) CreateMemory(ctx context.Context, memory *Memory) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.CreateMemory")
	defer span.End()
	repository, err := s.repositoryStore.FindByNWO(ctx, memory.Source.NWO)
	if err != nil {
		return fmt.Errorf("failed to find repository %s: %w", memory.Source.NWO, err)
	}

	if !s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryStorage, int64(memory.Source.User.ID), int64(repository.ID)) {
		return ErrFeatureNotEnabled
	}

	// Check if the repository is disallowed
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, int64(memory.Source.User.ID), int64(repository.ID)) {
		return ErrFeatureNotEnabled
	}

	if repository == nil {
		return ErrRepositoryNotFound
	}
	// If the repository is public, we have not enabled the feature
	if !repository.Private {
		return ErrFeatureNotEnabled
	}
	// Check if the memory contains secrets
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureSecretScanning, int64(memory.Source.User.ID), int64(repository.ID)) {
		secrets, err := s.secretScanner.Scan(ctx, repository.NWO, *memory)
		if err != nil {
			return fmt.Errorf("failed to scan memory for secrets: %w", err)
		}
		if len(secrets) > 0 {
			return ErrMemoryContainsSecrets
		}
	}

	s.obsv.Statter.Increment("memory_service.create_memory.count", map[string]string{"agent": memory.Source.Agent})
	return s.repo.Save(ctx, repository.ID, memory)
}

// GetMemories retrieves all memories for a given repository NWO.
func (s *memoryService) GetMemories(ctx context.Context, user User, repoNWO RepoNWO) ([]*Memory, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.GetMemories")
	defer span.End()
	repository, err := s.repositoryStore.FindByNWO(ctx, repoNWO)
	if err != nil {
		return nil, fmt.Errorf("failed to find repository %s: %w", repoNWO, err)
	}

	if !s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryStorage, int64(user.ID), int64(repository.ID)) {
		return nil, ErrFeatureNotEnabled
	}

	// Check if the repository is disallowed
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, int64(user.ID), int64(repository.ID)) {
		return nil, ErrFeatureNotEnabled
	}

	if repository == nil {
		return nil, ErrRepositoryNotFound
	}

	// If the repository is public, we have not enabled the feature
	if !repository.Private {
		return nil, ErrFeatureNotEnabled
	}
	memories, err := s.repo.FindByRepository(ctx, repository.ID)
	s.obsv.Statter.Distribution("memory_service.get_memories.count", map[string]string{}, float64(len(memories)))
	if err != nil {
		return nil, err
	}
	if len(memories) == 0 {
		return nil, ErrNoMemoriesNotFound
	}
	return memories, nil
}

// GetRecentMemories retrieves the most recent N memories for a given repository NWO.
func (s *memoryService) GetRecentMemories(ctx context.Context, user User, repoNWO RepoNWO, limit uint) ([]*Memory, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.GetRecentMemories")
	defer span.End()
	repository, err := s.repositoryStore.FindByNWO(ctx, repoNWO)
	if err != nil {
		return nil, fmt.Errorf("failed to find repository %s: %w", repoNWO, err)
	}

	if !s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryStorage, int64(user.ID), int64(repository.ID)) {
		return nil, ErrFeatureNotEnabled
	}

	// Check if the repository is disallowed
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, int64(user.ID), int64(repository.ID)) {
		return nil, ErrFeatureNotEnabled
	}

	if repository == nil {
		return nil, ErrRepositoryNotFound
	}

	// If the repository is public, we have not enabled the feature
	if !repository.Private {
		return nil, ErrFeatureNotEnabled
	}

	memories, err := s.repo.FindRecentByRepository(ctx, repository.ID, limit)
	s.obsv.Statter.Distribution("memory_service.get_recent_memories.count", map[string]string{}, float64(len(memories)))
	if err != nil {
		return nil, fmt.Errorf("failed to get recent memories: %w", err)
	}
	if len(memories) == 0 {
		return nil, ErrNoMemoriesNotFound
	}
	return memories, nil
}

// DeleteMemory deletes a specific memory by ID.
func (s *memoryService) DeleteMemory(ctx context.Context, user User, repoNWO RepoNWO, memoryID MemoryID) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.DeleteMemory")
	defer span.End()

	repository, err := s.repositoryStore.FindByNWO(ctx, repoNWO)
	if err != nil {
		return fmt.Errorf("failed to find repository %s: %w", repoNWO, err)
	}

	if !s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryStorage, int64(user.ID), int64(repository.ID)) {
		return ErrFeatureNotEnabled
	}

	if !s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryDeletion, int64(user.ID), int64(repository.ID)) {
		return ErrFeatureNotEnabled
	}

	// Check if the repository is disallowed
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, int64(user.ID), int64(repository.ID)) {
		return ErrFeatureNotEnabled
	}

	if repository == nil {
		return ErrRepositoryNotFound
	}

	// If the repository is public, we have not enabled the feature
	if !repository.Private {
		return ErrFeatureNotEnabled
	}

	s.obsv.Statter.Increment("memory_service.delete_memory.count", map[string]string{})
	return s.repo.Delete(ctx, repository.ID, memoryID)
}

// DeleteAllMemories deletes all memories for a repository.
func (s *memoryService) DeleteAllMemories(ctx context.Context, user User, repoNWO RepoNWO) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "memoryService.DeleteAllMemories")
	defer span.End()

	repository, err := s.repositoryStore.FindByNWO(ctx, repoNWO)
	if err != nil {
		return fmt.Errorf("failed to find repository %s: %w", repoNWO, err)
	}

	if !s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryStorage, int64(user.ID), int64(repository.ID)) {
		return ErrFeatureNotEnabled
	}

	if !s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureMemoryDeletion, int64(user.ID), int64(repository.ID)) {
		return ErrFeatureNotEnabled
	}

	// Check if the repository is disallowed
	if s.featureFlagClient.IsEnabledForUserOrRepo(ctx, featureDisallowedRepos, int64(user.ID), int64(repository.ID)) {
		return ErrFeatureNotEnabled
	}

	if repository == nil {
		return ErrRepositoryNotFound
	}

	// If the repository is public, we have not enabled the feature
	if !repository.Private {
		return ErrFeatureNotEnabled
	}

	// Get all memories for the repository
	memories, err := s.repo.FindByRepository(ctx, repository.ID)
	if err != nil {
		return fmt.Errorf("failed to get memories for deletion: %w", err)
	}

	// Delete each memory individually
	deletedCount := 0
	for _, memory := range memories {
		if err := s.repo.Delete(ctx, repository.ID, memory.ID); err != nil {
			// Log the error but continue deleting other memories
			s.obsv.Statter.Increment("memory_service.delete_all_memories.error", map[string]string{"memory_id": memory.ID.String()})
			// You might want to return the error here depending on your requirements
			// For now, we'll continue and try to delete the rest
		} else {
			deletedCount++
		}
	}

	s.obsv.Statter.Distribution("memory_service.delete_all_memories.count", map[string]string{}, float64(deletedCount))
	return nil
}

var (
	ErrNoMemoriesNotFound    = errors.New("no memories found for the given repository")
	ErrRepositoryNotFound    = errors.New("repository not found")
	ErrFeatureNotEnabled     = errors.New("memories are not enabled for this actor")
	ErrMemoryContainsSecrets = errors.New("memory contains secrets, cannot be saved")
)

var (
	featureMemoryStorage   = "copilot_swe_agent_memory_service"
	featureSecretScanning  = "copilot_swe_agent_memory_secret_scanning"
	featureMemoryDeletion  = "copilot_swe_agent_memory_deletion"
	featureDisallowedRepos = "copilot_swe_agent_disallow"
)
