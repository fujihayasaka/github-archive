package twirp

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"slices"

	"github.com/github/go-spdx/v2/spdxexp"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/policy"
	"github.com/github/osslicensecompliance/internal/remediation"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/twirp/twcerr"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/twitchtv/twirp"
)

const maxRemediationGuidanceLength = 2048

func createDistributionPoliciesFromRequest(reqLicenses *proto.PolicyLicenses, reqPackages []*proto.PackagePolicy) []*proto.DistributionPolicy {
	distributionPolicies := make(map[string]*proto.DistributionPolicy)

	if reqLicenses != nil {
		// Add the licenses to the distribution policies
		for _, licenseEntry := range reqLicenses.Allowed {
			// Normalize the SPDX ID to canonical case
			licenseEntry.SpdxId = evaluator.NormalizeSpdxID(licenseEntry.SpdxId)

			if len(licenseEntry.Contexts) == 0 { //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
				licenseEntry.Contexts = []string{"distributed"} //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
			}
			dpNames := slices.Clone(licenseEntry.Contexts) //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
			licenseEntry.Contexts = nil                    //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
			for _, dpName := range dpNames {
				dp, exists := distributionPolicies[dpName]
				if !exists {
					dp = &proto.DistributionPolicy{
						Name:     dpName,
						Licenses: &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{}},
						Packages: []*proto.PackagePolicy{},
					}
					distributionPolicies[dpName] = dp
				}
				dp.Licenses.Allowed = append(dp.Licenses.Allowed, licenseEntry)
			}
		}
	}

	// Add the packages to the distribution policies
	for _, pkgPolicy := range reqPackages {
		if len(pkgPolicy.Contexts) == 0 { //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
			pkgPolicy.Contexts = []string{"distributed"} //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
		}
		dpNames := slices.Clone(pkgPolicy.Contexts) //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
		pkgPolicy.Contexts = nil                    //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
		for _, dpName := range dpNames {
			dp, exists := distributionPolicies[dpName]
			if !exists {
				dp = &proto.DistributionPolicy{
					Name:     dpName,
					Licenses: &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{}},
					Packages: []*proto.PackagePolicy{},
				}
				distributionPolicies[dpName] = dp
			}
			dp.Packages = append(dp.Packages, pkgPolicy)
		}
	}
	// Convert map to slice
	return slices.Collect(maps.Values(distributionPolicies))
}

// CreateOrganizationPolicy creates a new organization policy.
//
// Deprecated: Policies are created automatically by adding licenses or packages.
// There will be a new version of this later when we support multiple distribution policies.
func (s *Server) CreateOrganizationPolicy(ctx context.Context, req *proto.CreateOrganizationPolicyRequest) (*proto.CreateOrganizationPolicyResponse, error) {
	if len(req.CustomRemediationGuidance) > maxRemediationGuidanceLength {
		return nil, twirp.InvalidArgumentError("custom_remediation_guidance", fmt.Sprintf("length must be less than %d characters", maxRemediationGuidanceLength))
	}

	if req.OrganizationId == 0 {
		return nil, twirp.RequiredArgumentError("organization_id")
	}

	orgPolicy := &proto.OrganizationPolicy{
		OrganizationId:            req.OrganizationId,
		CustomRemediationGuidance: req.CustomRemediationGuidance,
		DistributionPolicies:      createDistributionPoliciesFromRequest(req.Licenses, req.Packages),
	}
	orgPolicy, err := s.app.Subsystems.Storage.CreateOrganizationPolicy(ctx, orgPolicy)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.CreateOrganizationPolicyResponse{
		Policy: orgPolicy,
	}, nil
}

// GetOrganizationPolicy gets an OrganizationPolicy by id.
func (s *Server) GetOrganizationPolicy(ctx context.Context, req *proto.GetOrganizationPolicyRequest) (*proto.GetOrganizationPolicyResponse, error) {
	orgPolicy, err := s.app.Subsystems.Storage.GetOrganizationPolicyByOrgID(ctx, req.OrganizationId)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			return nil, twirp.NotFoundError("policy not found")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.GetOrganizationPolicyResponse{
		Policy: orgPolicy,
	}, nil
}

// CreateEnterprisePolicy creates a new enterprise policy.
//
// Deprecated: Policies are created automatically by adding licenses or packages.
// There will be a new version of this later when we support multiple distribution policies.
func (s *Server) CreateEnterprisePolicy(ctx context.Context, req *proto.CreateEnterprisePolicyRequest) (*proto.CreateEnterprisePolicyResponse, error) {
	if len(req.CustomRemediationGuidance) > maxRemediationGuidanceLength {
		return nil, twirp.InvalidArgumentError("custom_remediation_guidance", fmt.Sprintf("length must be less than %d characters", maxRemediationGuidanceLength))
	}

	if req.EnterpriseId == 0 {
		return nil, twirp.RequiredArgumentError("enterprise_id")
	}

	enterprisePolicy := &proto.EnterprisePolicy{
		EnterpriseId:              req.EnterpriseId,
		CustomRemediationGuidance: req.CustomRemediationGuidance,
		DistributionPolicies:      createDistributionPoliciesFromRequest(req.Licenses, req.Packages),
	}
	enterprisePolicy, err := s.app.Subsystems.Storage.CreateEnterprisePolicy(ctx, enterprisePolicy)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	singlePolicyBackwardsCompatibility(enterprisePolicy)

	return &proto.CreateEnterprisePolicyResponse{
		Policy: enterprisePolicy,
	}, nil
}

// GetEnterprisePolicy gets an EnterprisePolicy by id.
func (s *Server) GetEnterprisePolicy(ctx context.Context, req *proto.GetEnterprisePolicyRequest) (*proto.GetEnterprisePolicyResponse, error) {
	enterprisePolicy, err := s.app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, req.EnterpriseId)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			return nil, twirp.NotFoundError("policy not found")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	singlePolicyBackwardsCompatibility(enterprisePolicy)

	return &proto.GetEnterprisePolicyResponse{
		Policy: enterprisePolicy,
	}, nil
}

// CreateRepositoryPolicy creates a new repository policy.
func (s *Server) CreateRepositoryPolicy(ctx context.Context, req *proto.CreateRepositoryPolicyRequest) (*proto.CreateRepositoryPolicyResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}

	repoPolicy := &proto.RepositoryPolicy{
		RepositoryId: req.RepositoryId,
		Licenses:     req.Licenses,
		Packages:     req.Packages,
	}
	repoPolicy, err := s.app.Subsystems.Storage.CreateRepositoryPolicy(ctx, repoPolicy)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.CreateRepositoryPolicyResponse{
		Policy: repoPolicy,
	}, nil
}

// GetRepositoryPolicy gets a RepositoryPolicy by id.
func (s *Server) GetRepositoryPolicy(ctx context.Context, req *proto.GetRepositoryPolicyRequest) (*proto.GetRepositoryPolicyResponse, error) {
	repoPolicy, err := s.app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, req.RepositoryId)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			return nil, twirp.NotFoundError("policy not found")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.GetRepositoryPolicyResponse{
		Policy: repoPolicy,
	}, nil
}

// GetCombinedRepositoryPolicy returns the full policy for a repository, combining the repository,
// organization, and enterprise policies as applicable.
func (s *Server) GetCombinedRepositoryPolicy(ctx context.Context, req *proto.GetCombinedRepositoryPolicyRequest) (*proto.GetCombinedRepositoryPolicyResponse, error) {
	completePolicy, err := s.app.Subsystems.Storage.GetCompletePolicy(ctx, req.EnterpriseId, req.OrganizationId, req.RepositoryId)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			return nil, twirp.NotFoundError("policy not found")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	combinedPolicy := completePolicy.GetCombinedRepositoryPolicy(req.DistributionPolicyName)

	return &proto.GetCombinedRepositoryPolicyResponse{
		Policy: combinedPolicy,
	}, nil
}

// DeleteLicensesFromRepositoryPolicy removes licenses from a RepositoryPolicy.
func (s *Server) DeleteLicensesFromRepositoryPolicy(ctx context.Context, req *proto.DeleteLicensesFromRepositoryPolicyRequest) (*proto.DeleteLicensesFromRepositoryPolicyResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if len(req.SpdxIds) == 0 {
		return nil, twirp.RequiredArgumentError("spdx_ids")
	}

	existingPolicy, err := s.app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, req.RepositoryId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if existingPolicy == nil {
		return nil, errors.New("no existing policy to update")
	}

	policyWriter, err := policy.NewWriter(s.app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, req.RepositoryId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	err = policyWriter.RemoveLicenses(ctx, req.SpdxIds, "")
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.DeleteLicensesFromRepositoryPolicyResponse{
		Success: true,
	}, nil
}

// DeletePackageExceptionsFromRepositoryPolicy deletes package exceptions from policy.
func (s *Server) DeletePackageExceptionsFromRepositoryPolicy(ctx context.Context, req *proto.DeletePackageExceptionsFromRepositoryPolicyRequest) (*proto.DeletePackageExceptionsFromRepositoryPolicyResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if len(req.Packages) == 0 {
		return nil, twirp.RequiredArgumentError("packages")
	}

	existingPolicy, err := s.app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, req.RepositoryId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if existingPolicy == nil {
		return nil, errors.New("no existing policy to update")
	}

	policyWriter, err := policy.NewWriter(s.app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, req.RepositoryId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	err = policyWriter.RemovePackages(ctx, req.Packages, "")
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.DeletePackageExceptionsFromRepositoryPolicyResponse{
		Success: true,
	}, nil
}

// AddLicensesToOrganizationPolicy adds licenses to an OrganizationPolicy, creating the policy if it doesn't exist.
func (s *Server) AddLicensesToOrganizationPolicy(ctx context.Context, req *proto.AddLicensesToOrganizationPolicyRequest) (*proto.AddLicensesToOrganizationPolicyResponse, error) {
	if len(req.SpdxIds) == 0 {
		return nil, twirp.RequiredArgumentError("spdx_ids")
	}
	if req.Context == "" {
		return nil, twirp.RequiredArgumentError("context")
	}
	if req.OrganizationId == 0 {
		return nil, twirp.RequiredArgumentError("organization_id")
	}
	if valid, invalidLicenses := spdxexp.ValidateLicenses(req.SpdxIds); !valid {
		return nil, twcerr.NewInvalidSPDXIdentifiersError(twirp.InvalidArgumentError("req.SpdxIds", "has invalid SPDX license identifiers"), invalidLicenses)
	}

	updatedPolicy, err := remediation.AddLicensesToOrganizationPolicy(
		ctx,
		s.app,
		req.SpdxIds,
		req.Context,
		req.OrganizationId,
	)

	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.AddLicensesToOrganizationPolicyResponse{
		Policy: updatedPolicy,
	}, nil
}

// AddLicensesToEnterprisePolicy adds licenses to an EnterprisePolicy, creating the policy if it doesn't exist.
func (s *Server) AddLicensesToEnterprisePolicy(ctx context.Context, req *proto.AddLicensesToEnterprisePolicyRequest) (*proto.AddLicensesToEnterprisePolicyResponse, error) {
	if len(req.SpdxIds) == 0 {
		return nil, twirp.RequiredArgumentError("spdx_ids")
	}
	if req.Context == "" {
		return nil, twirp.RequiredArgumentError("context")
	}
	if req.EnterpriseId == 0 {
		return nil, twirp.RequiredArgumentError("enterprise_id")
	}
	if valid, invalidLicenses := spdxexp.ValidateLicenses(req.SpdxIds); !valid {
		return nil, twcerr.NewInvalidSPDXIdentifiersError(twirp.InvalidArgumentError("req.SpdxIds", "has invalid SPDX license identifiers"), invalidLicenses)
	}

	updatedPolicy, err := remediation.AddLicensesToEnterprisePolicy(
		ctx,
		s.app,
		req.SpdxIds,
		req.Context,
		req.EnterpriseId,
	)

	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.AddLicensesToEnterprisePolicyResponse{
		Policy: updatedPolicy,
	}, nil
}

// DeleteLicensesFromEnterprisePolicy removes licenses from an EnterprisePolicy.
func (s *Server) DeleteLicensesFromEnterprisePolicy(ctx context.Context, req *proto.DeleteLicensesFromEnterprisePolicyRequest) (*proto.DeleteLicensesFromEnterprisePolicyResponse, error) {
	if len(req.SpdxIds) == 0 {
		return nil, twirp.RequiredArgumentError("spdx_ids")
	}
	if req.EnterpriseId == 0 {
		return nil, twirp.RequiredArgumentError("enterprise_id")
	}
	if req.Context == "" {
		return nil, twirp.RequiredArgumentError("context")
	}

	existingPolicy, err := s.app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, req.EnterpriseId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if existingPolicy == nil {
		return nil, errors.New("no existing policy to update")
	}

	policyWriter, err := policy.NewWriter(s.app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, req.EnterpriseId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	err = policyWriter.RemoveLicenses(ctx, req.SpdxIds, req.Context)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	// Fetch the updated policy to return
	updatedPolicy, err := s.app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, req.EnterpriseId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	singlePolicyBackwardsCompatibility(updatedPolicy)

	return &proto.DeleteLicensesFromEnterprisePolicyResponse{
		Policy: updatedPolicy,
	}, nil
}

// DeletePackageExceptionsFromEnterprisePolicy deletes package exceptions from policy.
// TODO: this needs to support deleting by context when we fully implement multiple policies.
func (s *Server) DeletePackageExceptionsFromEnterprisePolicy(ctx context.Context, req *proto.DeletePackageExceptionsFromEnterprisePolicyRequest) (*proto.DeletePackageExceptionsFromEnterprisePolicyResponse, error) {
	if req.EnterpriseId == 0 {
		return nil, twirp.RequiredArgumentError("enterprise_id")
	}
	if len(req.Packages) == 0 {
		return nil, twirp.RequiredArgumentError("packages")
	}

	existingPolicy, err := s.app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, req.EnterpriseId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if existingPolicy == nil {
		return nil, errors.New("no existing policy to update")
	}

	policyWriter, err := policy.NewWriter(s.app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, req.EnterpriseId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	err = policyWriter.RemovePackages(ctx, req.Packages, "distributed")
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	// Fetch the updated policy to return
	updatedPolicy, err := s.app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, req.EnterpriseId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	singlePolicyBackwardsCompatibility(updatedPolicy)

	return &proto.DeletePackageExceptionsFromEnterprisePolicyResponse{
		Policy: updatedPolicy,
	}, nil
}
