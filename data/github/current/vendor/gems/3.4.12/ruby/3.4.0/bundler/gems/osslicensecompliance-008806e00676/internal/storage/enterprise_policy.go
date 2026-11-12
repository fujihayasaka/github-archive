package storage

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	olcproto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// CreateEnterprisePolicy stores an enterprise policy in blob storage.
func (s *Storage) CreateEnterprisePolicy(ctx context.Context, entPolicy *olcproto.EnterprisePolicy) (*olcproto.EnterprisePolicy, error) {
	if entPolicy == nil {
		return nil, errors.New("enterprise policy is nil")
	}
	if entPolicy.EnterpriseId == 0 {
		return nil, errors.New("enterprise ID is required")
	}

	upgradeEnterprisePolicy(entPolicy)

	// Store the current time in entPolicy as the CreatedAt time
	entPolicy.CreatedAt = timestamppb.Now()

	data, err := proto.Marshal(entPolicy)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal enterprise policy proto: %w", err)
	}

	err = s.writeAllWithMetrics(ctx, s.enterpriseBucket, "CreateEnterprisePolicy", strconv.FormatUint(entPolicy.EnterpriseId, 10), data, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to blob write repo policy: %w", err)
	}
	return entPolicy, nil
}

// GetEnterprisePolicyByEnterpriseID returns a single EnterprisePolicy by enterprise ID.
func (s *Storage) GetEnterprisePolicyByEnterpriseID(ctx context.Context, id uint64) (*olcproto.EnterprisePolicy, error) {
	policyBytes, err := s.readAllWithMetrics(ctx, s.enterpriseBucket, "GetEnterprisePolicyByEnterpriseID", strconv.FormatUint(id, 10))
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return nil, fmt.Errorf("blob not found for enterpriseID: %d: %w, %w", id, ErrNotFound, err)
		}
		return nil, fmt.Errorf("failed to blob read enterprise policy id: %d error: %w", id, err)
	}

	var policy olcproto.EnterprisePolicy
	err = proto.Unmarshal(policyBytes, &policy)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal enterprise policy proto for enterpriseID %d: %w", id, err)
	}

	upgradeEnterprisePolicy(&policy)

	return &policy, nil
}

//nolint:staticcheck // SA1019: this function specifically handles deprecated fields during upgrade
func upgradeEnterprisePolicy(policy *olcproto.EnterprisePolicy) {
	// Temporary upgrade logic to be removed after our policies have been upgraded.
	if len(policy.DistributionPolicies) == 0 {
		policy.DistributionPolicies = []*olcproto.DistributionPolicy{
			{
				Name: "distributed",
				//nolint:staticcheck // SA1019: accessing deprecated field during upgrade
				Licenses: policy.Licenses,
				//nolint:staticcheck // SA1019: accessing deprecated field during upgrade
				Packages: policy.Packages,
			},
		}
	}
}

// UpdateEnterprisePolicy updates an existing EnterprisePolicy using the provided update function.
func (s *Storage) UpdateEnterprisePolicy(ctx context.Context, enterpriseID uint64, updateFunc func(*olcproto.EnterprisePolicy) (*olcproto.EnterprisePolicy, error)) (*olcproto.EnterprisePolicy, error) {
	var updatedPolicy *olcproto.EnterprisePolicy
	err := s.swapWithMetrics(ctx, s.enterpriseBucket, "UpdateEnterprisePolicy", strconv.FormatUint(enterpriseID, 10), func(oldBytes []byte) ([]byte, error) {
		if oldBytes == nil {
			return nil, ErrNotFound
		}
		currentPolicy := &olcproto.EnterprisePolicy{}
		err := proto.Unmarshal(oldBytes, currentPolicy)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal existing enterprise policy: %w", err)
		}

		upgradeEnterprisePolicy(currentPolicy)

		updatedPolicy, err = updateFunc(currentPolicy)
		if err != nil {
			return nil, fmt.Errorf("update function failed: %w", err)
		}
		updatedPolicy.CreatedAt = timestamppb.Now()

		updatedBytes, err := proto.Marshal(updatedPolicy)
		if err != nil {
			return nil, fmt.Errorf("marshal updated policy: %w", err)
		}
		return updatedBytes, nil
	}, nil)

	if err != nil {
		if errors.Is(err, ErrNotFound) {
			return nil, fmt.Errorf("enterprise policy not found for enterprise id %d: %w", enterpriseID, err)
		}
		return nil, fmt.Errorf("failed to update enterprise policy for enterprise id: %d: %w", enterpriseID, err)
	}

	return updatedPolicy, nil
}
