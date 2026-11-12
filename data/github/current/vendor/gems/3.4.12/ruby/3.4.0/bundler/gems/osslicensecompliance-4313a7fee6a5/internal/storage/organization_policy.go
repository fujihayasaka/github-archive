package storage

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/github/osslicensecompliance/internal/models"
)

// CreateOrganizationPolicy inserts an OrganizationPolicy row.
func (s *Storage) CreateOrganizationPolicy(ctx context.Context, organizationID uint64, policy *models.Policy, customRemediationGuidance string) (*models.OrganizationPolicy, error) {
	policyBytes, err := json.Marshal(policy)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal policy: %w", err)
	}
	hash := sha256.New()
	_, err = hash.Write(policyBytes)
	if err != nil {
		return nil, fmt.Errorf("failed to hash policy: %w", err)
	}

	orgPolicy := &models.OrganizationPolicy{
		CreatedAt:                 time.Now().UTC(),
		OrganizationID:            organizationID,
		Policy:                    policy,
		Hash:                      hash.Sum(nil),
		CustomRemediationGuidance: customRemediationGuidance,
	}

	orgPolicybytes, err := json.Marshal(orgPolicy)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal policy: %w", err)
	}

	err = s.writeAllWithMetrics(ctx, s.orgBucket, "CreateOrganizationPolicy", strconv.FormatUint(organizationID, 10), orgPolicybytes, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to blob write org policy org id: %d error: %w", organizationID, err)
	}
	return orgPolicy, nil
}

// GetOrganizationPolicyByOrgID returns a single OrganizationPolicy.
func (s *Storage) GetOrganizationPolicyByOrgID(ctx context.Context, id uint64) (*models.OrganizationPolicy, error) {
	policyBytes, err := s.readAllWithMetrics(ctx, s.orgBucket, "GetOrganizationPolicyByOrgID", strconv.FormatUint(id, 10))
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return nil, fmt.Errorf("blob not found for repo id: %d: %w, %w", id, ErrNotFound, err)
		}
		return nil, fmt.Errorf("failed to blob read repo policy id: %d error: %w", id, err)
	}

	policy := &models.OrganizationPolicy{}

	if err := json.Unmarshal(policyBytes, &policy); err != nil {
		return nil, err
	}

	return policy, nil
}
