package storage

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	olcproto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
)

// CreateRepositoryPolicy inserts a RepositoryPolicy into blob storage.
func (s *Storage) CreateRepositoryPolicy(ctx context.Context, policy *olcproto.RepositoryPolicy) (*olcproto.RepositoryPolicy, error) {
	if policy == nil {
		return nil, errors.New("repository policy is nil")
	}
	if policy.RepositoryId == 0 {
		return nil, errors.New("repository ID is required")
	}

	policy.CreatedAt = timestamppb.Now()

	repoPolicyBytes, err := proto.Marshal(policy)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal repo policy: %w", err)
	}

	err = s.writeAllWithMetrics(ctx, s.repoBucket, "CreateRepositoryPolicy", strconv.FormatUint(policy.RepositoryId, 10), repoPolicyBytes, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to blob write repo policy: %w", err)
	}

	return policy, nil
}

// GetRepositoryPolicyByRepoID returns a single RepositoryPolicy.
func (s *Storage) GetRepositoryPolicyByRepoID(ctx context.Context, id uint64) (*olcproto.RepositoryPolicy, error) {
	policyBytes, err := s.readAllWithMetrics(ctx, s.repoBucket, "GetRepositoryPolicyByRepoID", strconv.FormatUint(id, 10))
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return nil, fmt.Errorf("blob not found for repo id: %d: %w, %w", id, ErrNotFound, err)
		}
		return nil, fmt.Errorf("failed to blob read repo policy id: %d error: %w", id, err)
	}

	var policy olcproto.RepositoryPolicy
	if err := proto.Unmarshal(policyBytes, &policy); err != nil {
		return nil, fmt.Errorf("failed to unmarshal repo policy: %w", err)
	}

	return &policy, nil
}

// UpdateRepositoryPolicy updates an existing RepositoryPolicy using the provided update function.
// The update function may be called multiple times, so it must be safe to retry.
func (s *Storage) UpdateRepositoryPolicy(ctx context.Context, repositoryID uint64, updateFn func(policy *olcproto.RepositoryPolicy) (*olcproto.RepositoryPolicy, error)) (*olcproto.RepositoryPolicy, error) {
	var updatedPolicy *olcproto.RepositoryPolicy
	err := s.swapWithMetrics(ctx, s.repoBucket, "UpdateRepositoryPolicy", strconv.FormatUint(repositoryID, 10), func(oldBytes []byte) ([]byte, error) {
		if oldBytes == nil {
			return nil, ErrNotFound
		}
		currentPolicy := &olcproto.RepositoryPolicy{}
		err := proto.Unmarshal(oldBytes, currentPolicy)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal existing repo policy: %w", err)
		}
		updatedPolicy, err = updateFn(currentPolicy)
		if err != nil {
			return nil, fmt.Errorf("update function failed: %w", err)
		}
		updatedPolicy.CreatedAt = timestamppb.Now()

		updated, err := proto.Marshal(updatedPolicy)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal updated repo policy: %w", err)
		}

		return updated, nil
	}, nil)

	if err != nil {
		if errors.Is(err, ErrNotFound) {
			return nil, fmt.Errorf("repository policy not found for repo id: %d: %w", repositoryID, err)
		}
		return nil, fmt.Errorf("failed to update repository policy for repo id: %d: %w", repositoryID, err)
	}

	return updatedPolicy, nil
}
