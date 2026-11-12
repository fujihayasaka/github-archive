package twirp

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"
	"time"

	"github.com/github/go-server/runtime/telemetry/reporter"
	"github.com/github/go-spdx/v2/spdxexp"
	"github.com/github/osslicensecompliance/internal/models"
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
			// TODO: Normalizing one at a time is not super efficient and loses the dedup benefit of ValidateAndNormalizeLicensesWithOptions.
			validLicenses, invalidLicenses := spdxexp.ValidateAndNormalizeLicensesWithOptions([]string{licenseEntry.SpdxId}, spdxexp.ValidateLicensesOptions{})
			if len(invalidLicenses) > 0 || len(validLicenses) == 0 {
				// Skip invalid and empty set of licenses
				continue
			}
			licenseEntry.SpdxId = validLicenses[0]

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

	return &proto.GetEnterprisePolicyResponse{
		Policy: enterprisePolicy,
	}, nil
}

// removeAddedSpdxIDs makes the add/remove operation more coherent by removing
// any SPDX IDs from the delete list that are also in the add list
func removeAddedSpdxIDs(addSpdxIDs, deleteSpdxIDs []string) []string {
	return slices.DeleteFunc(deleteSpdxIDs, func(elem string) bool {
		return slices.Contains(addSpdxIDs, elem)
	})
}

// removeAddedPackages makes the add/remove operation more coherent by removing
// any packages from the delete list that are also in the add list
func removeAddedPackages(addPackages, deletePackages []*proto.PackagePolicy) []*proto.PackagePolicy {
	return slices.DeleteFunc(deletePackages, func(elem *proto.PackagePolicy) bool {
		return slices.ContainsFunc(addPackages, func(addElem *proto.PackagePolicy) bool {
			return addElem.PackageManager == elem.PackageManager && addElem.Name == elem.Name
		})
	})
}

// SaveEnterprisePolicy supports adding/deleting licenses and package exceptions in a single request.
func (s *Server) SaveEnterprisePolicy(ctx context.Context, req *proto.SaveEnterprisePolicyRequest) (*proto.SaveEnterprisePolicyResponse, error) {
	missingRequiredArgs := []string{}
	addIfMissing := func(cond bool, name string) {
		if cond {
			missingRequiredArgs = append(missingRequiredArgs, name)
		}
	}

	addIfMissing(req.EnterpriseId == 0, "enterprise_id")
	addIfMissing(req.Context == "", "context")
	addIfMissing(req.UserId == 0, "user_id")

	if len(missingRequiredArgs) > 0 {
		return nil, twirp.RequiredArgumentError(strings.Join(missingRequiredArgs, ", "))
	}

	deletePackages := req.DeletePackages
	if len(req.AddPackages) > 0 {
		err := s.validatePackagePolicies(req.AddPackages)
		if err != nil {
			return nil, twirp.InvalidArgumentError("add_packages", err.Error())
		}
		deletePackages = removeAddedPackages(req.AddPackages, deletePackages)
	}

	var validAddSpdxIDs []string
	var invalidAddSpdxIDs []string
	deleteSpdxIDs := req.DeleteSpdxIds
	if len(req.AddSpdxIds) > 0 {
		validAddSpdxIDs, invalidAddSpdxIDs = s.validateAndNormalizeLicenses(req.AddSpdxIds)
		deleteSpdxIDs = removeAddedSpdxIDs(validAddSpdxIDs, deleteSpdxIDs)
	}

	if len(validAddSpdxIDs) == 0 && len(deleteSpdxIDs) == 0 && len(deletePackages) == 0 && len(req.AddPackages) == 0 {
		if len(invalidAddSpdxIDs) > 0 {
			return &proto.SaveEnterprisePolicyResponse{
				Policy:        nil,
				FailedSpdxIds: invalidAddSpdxIDs,
			}, twirp.InvalidArgumentError("add_spdx_ids", "no valid SPDX IDs to add")
		}
		return nil, twirp.InvalidArgumentError("request", "must specify at least one update")
	}

	// Policy must exist to be updated for delete operations without add operations
	if (deleteSpdxIDs != nil || deletePackages != nil) && len(req.AddSpdxIds) == 0 && len(req.AddPackages) == 0 {
		_, err := s.app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, req.EnterpriseId)
		if err != nil {
			if errors.Is(err, storage.ErrNotFound) {
				return nil, twirp.NotFoundError("policy not found")
			}
			return nil, twirp.InternalErrorWith(err)
		}
	}

	policyWriter, err := policy.NewWriter(s.app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, req.EnterpriseId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	err = policyWriter.UpdateMultiple(ctx, &policy.MultipleUpdates{
		AddSpdxIDs:          validAddSpdxIDs,
		DeleteSpdxIDs:       deleteSpdxIDs,
		AddPackages:         req.AddPackages,
		DeletePackages:      deletePackages,
		DistributionContext: req.Context,
	})

	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if len(validAddSpdxIDs) > 0 {
		// Since we have successfully added licenses, we need a background routine to
		// update any affected alerts
		// Spawn async goroutine to close affected alerts
		// WithoutCancel detaches from request cancellation while preserving context tags
		asyncCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 1*time.Minute)
		go func() {
			defer cancel()

			eventBodyPayload := models.LicensesAddedEventBody{
				Licenses: validAddSpdxIDs,
				Level:    models.PolicyLevelToString(proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE),
			}
			err := remediation.CheckAndCloseAffectedAlertsForLicenses(
				asyncCtx,
				s.app,
				eventBodyPayload,
				proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
				req.EnterpriseId,
				0,
				0,
				&req.UserId,
				nil, // No original alert for direct policy updates
			)
			if err != nil {
				s.app.Logger.Named("policy-update").WithError(err).Error("failed to close affected alerts asynchronously")
				err = reporter.ReportWithValues(asyncCtx, err, map[string]string{
					"service":   "twirp",
					"component": "SaveEnterprisePolicy",
				})
				if err != nil {
					s.app.Logger.Named("policy-update").WithError(err).Error("failed to report error to Sentry")
				}
			}
		}()
	}

	if len(req.AddPackages) > 0 {
		// Since we have successfully added package exceptions, we need a background routine to
		// update any affected alerts

		// Spawn async goroutine to close affected alerts
		// WithoutCancel detaches from request cancellation while preserving context tags
		asyncCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 1*time.Minute)
		go func() {
			defer cancel()

			for _, packagePolicy := range req.AddPackages {
				// Record an alert event for the exception addition
				eventBodyPayload := models.ExceptionAddedEventBody{
					PackageManager: models.PackageManagerToString(packagePolicy.PackageManager),
					PackageName:    packagePolicy.Name,
					Level:          models.PolicyLevelToString(proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE),
				}

				err := remediation.CheckAndCloseAffectedAlertsForPackages(
					asyncCtx,
					s.app,
					eventBodyPayload,
					proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
					packagePolicy,
					req.EnterpriseId,
					0,
					0,
					&req.UserId,
					nil, // No original alert for direct policy updates
				)
				if err != nil {
					s.app.Logger.Named("policy-update").WithError(err).Error("failed to close affected alerts asynchronously")
					err = reporter.ReportWithValues(asyncCtx, err, map[string]string{
						"service":   "twirp",
						"component": "SaveEnterprisePolicy",
					})
					if err != nil {
						s.app.Logger.Named("policy-update").WithError(err).Error("failed to report error to Sentry")
					}
				}
			}
		}()
	}

	updatedPolicy, err := s.app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, req.EnterpriseId)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			return &proto.SaveEnterprisePolicyResponse{
				Policy:        nil,
				FailedSpdxIds: invalidAddSpdxIDs,
			}, nil
		}
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.SaveEnterprisePolicyResponse{
		Policy:        updatedPolicy,
		FailedSpdxIds: invalidAddSpdxIDs,
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

// SaveRepositoryPolicy supports deleting licenses and package exceptions in a single request.
func (s *Server) SaveRepositoryPolicy(ctx context.Context, req *proto.SaveRepositoryPolicyRequest) (*proto.SaveRepositoryPolicyResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}

	if len(req.DeleteSpdxIds) == 0 && len(req.DeletePackages) == 0 {
		return nil, twirp.InvalidArgumentError("request", "must specify at least one update")
	}

	// Policy must exist to be updated for delete operations without add operations
	_, err := s.app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, req.RepositoryId)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			return nil, twirp.NotFoundError("policy not found")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	policyWriter, err := policy.NewWriter(s.app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, req.RepositoryId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	err = policyWriter.UpdateMultiple(ctx, &policy.MultipleUpdates{
		DeleteSpdxIDs:  req.DeleteSpdxIds,
		DeletePackages: req.DeletePackages,
	})

	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.SaveRepositoryPolicyResponse{
		Success: true,
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
	if req.UserId == 0 {
		return nil, twirp.RequiredArgumentError("user_id")
	}
	var validLicenses []string
	var invalidLicenses []string
	if validLicenses, invalidLicenses = spdxexp.ValidateAndNormalizeLicensesWithOptions(req.SpdxIds, s.spdxLicenseValidationOptions()); len(invalidLicenses) > 0 {
		return nil, twcerr.NewInvalidSPDXIdentifiersError(twirp.InvalidArgumentError("req.SpdxIds", "has invalid SPDX license identifiers"), invalidLicenses)
	}

	updatedPolicy, err := remediation.AddLicensesToOrganizationPolicy(
		ctx,
		s.app,
		validLicenses,
		req.Context,
		req.OrganizationId,
		req.UserId,
	)

	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.AddLicensesToOrganizationPolicyResponse{
		Policy: updatedPolicy,
	}, nil
}

// AddLicensesToEnterprisePolicy adds licenses to an EnterprisePolicy, creating the policy if it doesn't exist.
// Valid SPDX IDs are added to the policy; invalid ones are returned in the failed_spdx_ids response field.
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
	if req.UserId == 0 {
		return nil, twirp.RequiredArgumentError("user_id")
	}

	updatedPolicy, invalidSpdxIDs, err := s.validateAndAddLicensesToEnterprisePolicy(ctx, req.SpdxIds, req.Context, req.EnterpriseId, req.UserId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.AddLicensesToEnterprisePolicyResponse{
		Policy:        updatedPolicy,
		FailedSpdxIds: invalidSpdxIDs,
	}, nil
}

func (s *Server) validateAndAddLicensesToEnterprisePolicy(ctx context.Context, spdxIDs []string, distContext string, enterpriseID, userID uint64) (*proto.EnterprisePolicy, []string, error) {
	validSpdxIDs, invalidSpdxIDs := s.validateAndNormalizeLicenses(spdxIDs)

	var updatedPolicy *proto.EnterprisePolicy
	if len(validSpdxIDs) > 0 {
		var err error
		updatedPolicy, err = remediation.AddLicensesToEnterprisePolicy(
			ctx,
			s.app,
			validSpdxIDs,
			distContext,
			enterpriseID,
			userID,
		)
		if err != nil {
			return nil, nil, twirp.InternalErrorWith(err)
		}
	}

	return updatedPolicy, invalidSpdxIDs, nil
}

func (s *Server) validatePackagePolicies(packagePolicies []*proto.PackagePolicy) error {
	for _, packagePolicy := range packagePolicies {
		// Name of a private package is expected to always be a wildcard
		if err := validateWildcardPattern(packagePolicy.Name); err != nil {
			return err
		}
	}
	return nil
}

// ValidateLicenses validates, normalizes, and dedups a list of licenses. The valid licenses are returned in canonical form.
// Invalid licenses are returned as well so the caller can decide how to handle them.
func (s *Server) ValidateLicenses(ctx context.Context, req *proto.ValidateLicensesRequest) (*proto.ValidateLicensesResponse, error) {
	validSpdxIDs, invalidSpdxIDs := s.validateAndNormalizeLicenses(req.SpdxIds)

	return &proto.ValidateLicensesResponse{
		ValidSpdxIds:   validSpdxIDs,
		InvalidSpdxIds: invalidSpdxIDs,
	}, nil
}

func (s *Server) validateAndNormalizeLicenses(spdxIDs []string) (validSpdxIDs, invalidSpdxIDs []string) {
	validSpdxIDs, invalidSpdxIDs = spdxexp.ValidateAndNormalizeLicensesWithOptions(spdxIDs, s.spdxLicenseValidationOptions())
	return validSpdxIDs, invalidSpdxIDs
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

	return &proto.DeletePackageExceptionsFromEnterprisePolicyResponse{
		Policy: updatedPolicy,
	}, nil
}
