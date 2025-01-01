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

// CreateEnterprisePolicy inserts an EnterprisePolicy row
func (s *Storage) CreateEnterprisePolicy(ctx context.Context, enterpriseID uint64, policy *models.Policy, customRemediationGuidance string) (*models.EnterprisePolicy, error) {
	policyBytes, err := json.Marshal(policy)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal policy: %w", err)
	}
	hash := sha256.New()
	_, err = hash.Write(policyBytes)
	if err != nil {
		return nil, fmt.Errorf("failed to hash policy: %w", err)
	}

	entPolicy := &models.EnterprisePolicy{
		CreatedAt:                 time.Now().UTC(),
		EnterpriseID:              enterpriseID,
		Policy:                    policy,
		Hash:                      hash.Sum(nil),
		CustomRemediationGuidance: customRemediationGuidance,
	}

	entPolicyBytes, err := json.Marshal(entPolicy)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal policy: %w", err)
	}

	err = s.writeAllWithMetrics(ctx, s.enterpriseBucket, "CreateEnterprisePolicy", strconv.FormatUint(enterpriseID, 10), entPolicyBytes, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to blob write repo policy: %w", err)
	}
	return entPolicy, nil
}

// GetEnterprisePolicyByEnterpriseID returns a single EnterprisePolicy
func (s *Storage) GetEnterprisePolicyByEnterpriseID(ctx context.Context, id uint64) (*models.EnterprisePolicy, error) {
	policyBytes, err := s.readAllWithMetrics(ctx, s.enterpriseBucket, "GetEnterprisePolicyByEnterpriseID", strconv.FormatUint(id, 10))
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return nil, fmt.Errorf("blob not found for enterpriseID: %d: %w, %w", id, ErrNotFound, err)
		}
		return nil, fmt.Errorf("failed to blob read enterprise policy id: %d error: %w", id, err)
	}

	policy := &models.EnterprisePolicy{}

	if err := json.Unmarshal(policyBytes, &policy); err != nil {
		return nil, err
	}

	return policy, nil
}
