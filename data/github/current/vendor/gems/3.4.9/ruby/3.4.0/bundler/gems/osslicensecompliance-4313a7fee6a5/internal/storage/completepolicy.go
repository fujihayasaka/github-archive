package storage

import (
	"context"
	"errors"

	"github.com/github/osslicensecompliance/internal/models"
	"golang.org/x/sync/errgroup"
)

// GetCompletePolicy returns the complete policy for a given enterprise, organization, and repository.
func (s *Storage) GetCompletePolicy(ctx context.Context, enterpriseID, organizationID, repositoryID uint64) (*models.CompletePolicy, error) {
	completePolicy := &models.CompletePolicy{}
	g, ctx := errgroup.WithContext(ctx)

	if enterpriseID != 0 {
		g.Go(func() error {
			enterprisePolicy, err := s.GetEnterprisePolicyByEnterpriseID(ctx, enterpriseID)
			if err != nil && !errors.Is(err, ErrNotFound) {
				return err
			}
			completePolicy.EnterprisePolicy = enterprisePolicy
			return nil
		})
	}

	g.Go(func() error {
		organizationPolicy, err := s.GetOrganizationPolicyByOrgID(ctx, organizationID)
		if err != nil && !errors.Is(err, ErrNotFound) {
			return err
		}
		completePolicy.OrganizationPolicy = organizationPolicy
		return nil
	})

	g.Go(func() error {
		repositoryPolicy, err := s.GetRepositoryPolicyByRepoID(ctx, repositoryID)
		if err != nil && !errors.Is(err, ErrNotFound) {
			return err
		}
		completePolicy.RepositoryPolicy = repositoryPolicy
		return nil
	})

	if err := g.Wait(); err != nil {
		return nil, err
	}

	if completePolicy.EnterprisePolicy == nil && completePolicy.OrganizationPolicy == nil && completePolicy.RepositoryPolicy == nil {
		return nil, ErrNotFound
	}

	return completePolicy, nil
}
