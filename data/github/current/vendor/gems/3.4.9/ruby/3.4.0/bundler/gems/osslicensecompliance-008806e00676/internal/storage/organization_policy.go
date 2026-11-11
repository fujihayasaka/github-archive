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

// CreateOrganizationPolicy inserts an OrganizationPolicy row.
func (s *Storage) CreateOrganizationPolicy(ctx context.Context, orgPolicy *olcproto.OrganizationPolicy) (*olcproto.OrganizationPolicy, error) {
	if orgPolicy == nil {
		return nil, errors.New("organization policy is nil")
	}
	if orgPolicy.OrganizationId == 0 {
		return nil, errors.New("organization ID is required")
	}

	orgPolicy.CreatedAt = timestamppb.Now()

	orgPolicyBytes, err := proto.Marshal(orgPolicy)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal org policy: %w", err)
	}

	err = s.writeAllWithMetrics(ctx, s.orgBucket, "CreateOrganizationPolicy", strconv.FormatUint(orgPolicy.OrganizationId, 10), orgPolicyBytes, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to blob write org policy org id: %d error: %w", orgPolicy.OrganizationId, err)
	}
	return orgPolicy, nil
}

// GetOrganizationPolicyByOrgID returns a single OrganizationPolicy.
func (s *Storage) GetOrganizationPolicyByOrgID(ctx context.Context, id uint64) (*olcproto.OrganizationPolicy, error) {
	policyBytes, err := s.readAllWithMetrics(ctx, s.orgBucket, "GetOrganizationPolicyByOrgID", strconv.FormatUint(id, 10))
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return nil, fmt.Errorf("blob not found for repo id: %d: %w, %w", id, ErrNotFound, err)
		}
		return nil, fmt.Errorf("failed to blob read repo policy id: %d error: %w", id, err)
	}

	var policy olcproto.OrganizationPolicy

	if err := proto.Unmarshal(policyBytes, &policy); err != nil {
		return nil, err
	}

	return &policy, nil
}

// UpdateOrganizationPolicy updates an existing OrganizationPolicy using the provided update function.
func (s *Storage) UpdateOrganizationPolicy(ctx context.Context, organizationID uint64, updateFn func(policy *olcproto.OrganizationPolicy) (*olcproto.OrganizationPolicy, error)) (*olcproto.OrganizationPolicy, error) {
	var updatedPolicy *olcproto.OrganizationPolicy
	err := s.swapWithMetrics(ctx, s.orgBucket, "UpdateOrganizationPolicy", strconv.FormatUint(organizationID, 10), func(oldBytes []byte) ([]byte, error) {
		if oldBytes == nil {
			return nil, ErrNotFound
		}
		currentPolicy := &olcproto.OrganizationPolicy{}
		err := proto.Unmarshal(oldBytes, currentPolicy)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal existing org policy: %w", err)
		}
		updatedPolicy, err = updateFn(currentPolicy)
		if err != nil {
			return nil, fmt.Errorf("update function failed: %w", err)
		}
		updatedPolicy.CreatedAt = timestamppb.Now()

		updated, err := proto.Marshal(updatedPolicy)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal updated org policy: %w", err)
		}

		return updated, nil
	}, nil)

	if err != nil {
		if errors.Is(err, ErrNotFound) {
			return nil, fmt.Errorf("organization policy not found for org id: %d: %w", organizationID, err)
		}
		return nil, fmt.Errorf("failed to update organization policy for org id: %d: %w", organizationID, err)
	}

	return updatedPolicy, nil
}
