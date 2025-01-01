package storage

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/github/osslicensecompliance/internal/models"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
)

// CreateRepositoryPolicy inserts a RepositoryPolicy into blob storage.
func (s *Storage) CreateRepositoryPolicy(ctx context.Context, repositoryID, orgID uint64, policy *models.RepositoryRefinement) (*models.RepositoryPolicy, error) {
	policyBytes, err := json.Marshal(policy)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal policy: %w", err)
	}
	hash := sha256.New()
	_, err = hash.Write(policyBytes)
	if err != nil {
		return nil, fmt.Errorf("failed to hash policy: %w", err)
	}

	repoPolicy := &models.RepositoryPolicy{
		CreatedAt:      time.Now().UTC(),
		Hash:           hash.Sum(nil),
		OrganizationID: orgID,
		RepositoryID:   repositoryID,
		Policy:         policy,
	}

	repoPolicyBytes, err := json.Marshal(repoPolicy)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal policy: %w", err)
	}

	err = s.writeAllWithMetrics(ctx, s.repoBucket, "CreateRepositoryPolicy", strconv.FormatUint(repositoryID, 10), repoPolicyBytes, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to blob write repo policy: %w", err)
	}

	return repoPolicy, nil
}

// GetRepositoryPolicyByRepoID returns a single RepositoryPolicy.
func (s *Storage) GetRepositoryPolicyByRepoID(ctx context.Context, id uint64) (*models.RepositoryPolicy, error) {
	policyBytes, err := s.readAllWithMetrics(ctx, s.repoBucket, "GetRepositoryPolicyByRepoID", strconv.FormatUint(id, 10))
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return nil, fmt.Errorf("blob not found for repo id: %d: %w, %w", id, ErrNotFound, err)
		}
		return nil, fmt.Errorf("failed to blob read repo policy id: %d error: %w", id, err)
	}

	policy := &models.RepositoryPolicy{}

	if err := json.Unmarshal(policyBytes, &policy); err != nil {
		return nil, err
	}

	return policy, nil
}
