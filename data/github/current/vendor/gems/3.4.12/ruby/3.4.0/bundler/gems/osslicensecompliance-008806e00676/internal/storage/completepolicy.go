package storage

import (
	"context"
	"errors"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"golang.org/x/sync/errgroup"
)

// GetCompletePolicy returns the complete policy for a given enterprise, organization, and repository.
func (s *Storage) GetCompletePolicy(ctx context.Context, enterpriseID, organizationID, repositoryID uint64) (*models.CompletePolicy, error) {
	g, ctx := errgroup.WithContext(ctx)

	var enterprisePolicy *proto.EnterprisePolicy
	var organizationPolicy *proto.OrganizationPolicy
	var repositoryPolicy *proto.RepositoryPolicy

	if enterpriseID != 0 {
		g.Go(func() error {
			retrieved, err := s.GetEnterprisePolicyByEnterpriseID(ctx, enterpriseID)
			if err != nil && !errors.Is(err, ErrNotFound) {
				return err
			}
			enterprisePolicy = retrieved
			return nil
		})
	}

	g.Go(func() error {
		retrieved, err := s.GetOrganizationPolicyByOrgID(ctx, organizationID)
		if err != nil && !errors.Is(err, ErrNotFound) {
			return err
		}
		organizationPolicy = retrieved
		return nil
	})

	g.Go(func() error {
		retrieved, err := s.GetRepositoryPolicyByRepoID(ctx, repositoryID)
		if err != nil && !errors.Is(err, ErrNotFound) {
			return err
		}
		repositoryPolicy = retrieved
		return nil
	})

	if err := g.Wait(); err != nil {
		return nil, err
	}

	if enterprisePolicy == nil && organizationPolicy == nil && repositoryPolicy == nil {
		return nil, ErrNotFound
	}

	completePolicy := models.NewCompletePolicy(enterprisePolicy, organizationPolicy, repositoryPolicy)
	return completePolicy, nil
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
