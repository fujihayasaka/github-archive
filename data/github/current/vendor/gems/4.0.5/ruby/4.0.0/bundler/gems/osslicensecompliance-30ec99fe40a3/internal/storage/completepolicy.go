package storage

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"golang.org/x/sync/errgroup"
	proto2 "google.golang.org/protobuf/proto"
)

// GetCompletePolicy returns the complete policy for a given enterprise, organization, and repository.
func (s *Storage) GetCompletePolicy(ctx context.Context, enterpriseID, organizationID, repositoryID uint64) (*models.CompletePolicy, error) {
	policy, _, err := s.GetCompletePolicyWithVersion(ctx, enterpriseID, organizationID, repositoryID)
	return policy, err
}

// GetCompletePolicyWithVersion returns the complete policy along with version information (Last-Modified timestamps).
// The version can be used for optimistic locking to detect policy changes during PR check execution.
func (s *Storage) GetCompletePolicyWithVersion(ctx context.Context, enterpriseID, organizationID, repositoryID uint64) (*models.CompletePolicy, *PolicyVersion, error) {
	g, ctx := errgroup.WithContext(ctx)

	var enterprisePolicy *proto.EnterprisePolicy
	var organizationPolicy *proto.OrganizationPolicy
	var repositoryPolicy *proto.RepositoryPolicy
	var version PolicyVersion

	if enterpriseID != 0 {
		g.Go(func() error {
			retrieved, timestamp, err := s.getEnterprisePolicyWithTimestamp(ctx, enterpriseID)
			if err != nil && !errors.Is(err, ErrNotFound) {
				return err
			}
			enterprisePolicy = retrieved
			version.EnterpriseLastModified = timestamp
			return nil
		})
	}

	g.Go(func() error {
		retrieved, timestamp, err := s.getOrganizationPolicyWithTimestamp(ctx, organizationID)
		if err != nil && !errors.Is(err, ErrNotFound) {
			return err
		}
		organizationPolicy = retrieved
		version.OrgLastModified = timestamp
		return nil
	})

	g.Go(func() error {
		retrieved, timestamp, err := s.getRepositoryPolicyWithTimestamp(ctx, repositoryID)
		if err != nil && !errors.Is(err, ErrNotFound) {
			return err
		}
		repositoryPolicy = retrieved
		version.RepoLastModified = timestamp
		return nil
	})

	if err := g.Wait(); err != nil {
		return nil, nil, err
	}

	if enterprisePolicy == nil && organizationPolicy == nil && repositoryPolicy == nil {
		return nil, nil, ErrNotFound
	}

	completePolicy := models.NewCompletePolicy(enterprisePolicy, organizationPolicy, repositoryPolicy)
	return completePolicy, &version, nil
}

// GetCompletePolicyFromPolicy returns a new CompletePolicy based on an existing one,
// but with parts of it replaced if the IDs have changed. Importantly, this only
// fetches policies for IDs that are different from those in the existing policy.
func (s *Storage) GetCompletePolicyFromPolicy(ctx context.Context, policy *models.CompletePolicy, enterpriseID, organizationID, repositoryID uint64) (*models.CompletePolicy, error) {
	g, ctx := errgroup.WithContext(ctx)

	var enterprisePolicy *proto.EnterprisePolicy
	var organizationPolicy *proto.OrganizationPolicy
	var repositoryPolicy *proto.RepositoryPolicy

	currentEnterpriseID := policy.GetEnterpriseID()
	currentOrganizationID := policy.GetOrganizationID()
	currentRepositoryID := policy.GetRepositoryID()

	if enterpriseID != 0 {
		if currentEnterpriseID != enterpriseID {
			g.Go(func() error {
				retrieved, err := s.GetEnterprisePolicyByEnterpriseID(ctx, enterpriseID)
				if err != nil && !errors.Is(err, ErrNotFound) {
					return err
				}
				if retrieved == nil {
					// No policy exists, so we use an empty policy to signal that the policy should be cleared.
					enterprisePolicy = nil
				} else {
					enterprisePolicy = retrieved
				}
				return nil
			})
		} else {
			enterprisePolicy = policy.EnterprisePolicy.Data
		}
	} else {
		enterprisePolicy = nil
	}

	if organizationID != 0 {
		if currentOrganizationID != organizationID {
			g.Go(func() error {
				retrieved, err := s.GetOrganizationPolicyByOrgID(ctx, organizationID)
				if err != nil && !errors.Is(err, ErrNotFound) {
					return err
				}
				if retrieved == nil {
					organizationPolicy = nil
				} else {
					organizationPolicy = retrieved
				}
				return nil
			})
		} else {
			organizationPolicy = policy.OrganizationPolicy.Data
		}
	} else {
		organizationPolicy = nil
	}

	if repositoryID != 0 {
		if currentRepositoryID != repositoryID {
			g.Go(func() error {
				retrieved, err := s.GetRepositoryPolicyByRepoID(ctx, repositoryID)
				if err != nil && !errors.Is(err, ErrNotFound) {
					return err
				}
				if retrieved == nil {
					repositoryPolicy = nil
				} else {
					repositoryPolicy = retrieved
				}
				return nil
			})
		} else {
			repositoryPolicy = policy.RepositoryPolicy.Data
		}
	} else {
		repositoryPolicy = nil
	}

	if err := g.Wait(); err != nil {
		return nil, err
	}

	completePolicy := policy.PolicyFromExistingPolicy(enterprisePolicy, organizationPolicy, repositoryPolicy)
	return completePolicy, nil
}

// GetPolicyVersion returns the version information (Last-Modified timestamps) for the policies
// without fetching the actual policy data. This is a lightweight operation using HEAD requests.
// Missing policies (not found errors) are treated as nil timestamps and not considered errors.
func (s *Storage) GetPolicyVersion(ctx context.Context, enterpriseID, organizationID, repositoryID uint64) (*PolicyVersion, error) {
	g, ctx := errgroup.WithContext(ctx)
	var version PolicyVersion

	if enterpriseID != 0 {
		g.Go(func() error {
			timestamp, err := s.enterpriseBucket.GetLastModified(ctx, strconv.FormatUint(enterpriseID, 10))
			if err != nil {
				// BlobNotFound is expected when no policy exists - treat as nil timestamp
				if bloberror.HasCode(err, bloberror.BlobNotFound) {
					version.EnterpriseLastModified = nil
					return nil
				}
				return err
			}
			version.EnterpriseLastModified = timestamp
			return nil
		})
	}

	g.Go(func() error {
		timestamp, err := s.orgBucket.GetLastModified(ctx, strconv.FormatUint(organizationID, 10))
		if err != nil {
			if bloberror.HasCode(err, bloberror.BlobNotFound) {
				version.OrgLastModified = nil
				return nil
			}
			return err
		}
		version.OrgLastModified = timestamp
		return nil
	})

	g.Go(func() error {
		timestamp, err := s.repoBucket.GetLastModified(ctx, strconv.FormatUint(repositoryID, 10))
		if err != nil {
			if bloberror.HasCode(err, bloberror.BlobNotFound) {
				version.RepoLastModified = nil
				return nil
			}
			return err
		}
		version.RepoLastModified = timestamp
		return nil
	})

	if err := g.Wait(); err != nil {
		return nil, err
	}

	return &version, nil
}

// getEnterprisePolicyWithTimestamp retrieves an enterprise policy along with its Last-Modified timestamp.
func (s *Storage) getEnterprisePolicyWithTimestamp(ctx context.Context, enterpriseID uint64) (*proto.EnterprisePolicy, *time.Time, error) {
	policyBytes, timestamp, err := s.readAllWithTimestamp(ctx, s.enterpriseBucket, "GetEnterprisePolicyByEnterpriseID", strconv.FormatUint(enterpriseID, 10))
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return nil, nil, fmt.Errorf("blob not found for enterprise id: %d: %w, %w", enterpriseID, ErrNotFound, err)
		}
		return nil, nil, fmt.Errorf("failed to blob read enterprise policy id: %d error: %w", enterpriseID, err)
	}

	var policy proto.EnterprisePolicy
	if err := proto2.Unmarshal(policyBytes, &policy); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal enterprise policy: %w", err)
	}

	return &policy, timestamp, nil
}

// getOrganizationPolicyWithTimestamp retrieves an organization policy along with its Last-Modified timestamp.
func (s *Storage) getOrganizationPolicyWithTimestamp(ctx context.Context, organizationID uint64) (*proto.OrganizationPolicy, *time.Time, error) {
	policyBytes, timestamp, err := s.readAllWithTimestamp(ctx, s.orgBucket, "GetOrganizationPolicyByOrgID", strconv.FormatUint(organizationID, 10))
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return nil, nil, fmt.Errorf("blob not found for org id: %d: %w, %w", organizationID, ErrNotFound, err)
		}
		return nil, nil, fmt.Errorf("failed to blob read org policy id: %d error: %w", organizationID, err)
	}

	var policy proto.OrganizationPolicy
	if err := proto2.Unmarshal(policyBytes, &policy); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal org policy: %w", err)
	}

	return &policy, timestamp, nil
}

// getRepositoryPolicyWithTimestamp retrieves a repository policy along with its Last-Modified timestamp.
func (s *Storage) getRepositoryPolicyWithTimestamp(ctx context.Context, repositoryID uint64) (*proto.RepositoryPolicy, *time.Time, error) {
	policyBytes, timestamp, err := s.readAllWithTimestamp(ctx, s.repoBucket, "GetRepositoryPolicyByRepoID", strconv.FormatUint(repositoryID, 10))
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return nil, nil, fmt.Errorf("blob not found for repo id: %d: %w, %w", repositoryID, ErrNotFound, err)
		}
		return nil, nil, fmt.Errorf("failed to blob read repo policy id: %d error: %w", repositoryID, err)
	}

	var policy proto.RepositoryPolicy
	if err := proto2.Unmarshal(policyBytes, &policy); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal repo policy: %w", err)
	}

	return &policy, timestamp, nil
}
