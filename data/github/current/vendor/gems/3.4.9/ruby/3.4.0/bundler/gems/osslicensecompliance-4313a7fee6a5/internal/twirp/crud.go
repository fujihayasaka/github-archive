package twirp

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const maxRemediationGuidanceLength = 2048

// CreateOrganizationPolicy creates a new organization policy.
func (s *Server) CreateOrganizationPolicy(ctx context.Context, req *proto.CreateOrganizationPolicyRequest) (*proto.CreateOrganizationPolicyResponse, error) {
	if len(req.CustomRemediationGuidance) > maxRemediationGuidanceLength {
		return nil, twirp.InvalidArgumentError("custom_remediation_guidance", fmt.Sprintf("length must be less than %d characters", maxRemediationGuidanceLength))
	}
	policyModel := PolicyModelMapper{}.FromProto(req.Licenses, req.Packages)
	orgPolicy, err := s.app.Subsystems.Storage.CreateOrganizationPolicy(ctx, req.OrganizationId, policyModel, req.CustomRemediationGuidance)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	resPackages, err := PolicyModelMapper{}.PackagesToProto(orgPolicy.Policy.Packages)
	if err != nil {
		return nil, twirp.InternalErrorWith(fmt.Errorf("error mapping response: %w", err))
	}
	return &proto.CreateOrganizationPolicyResponse{
		Policy: &proto.OrganizationPolicy{
			Licenses:                  req.Licenses,
			Packages:                  resPackages,
			OrganizationId:            orgPolicy.OrganizationID,
			CreatedAt:                 timestamppb.New(orgPolicy.CreatedAt),
			CustomRemediationGuidance: orgPolicy.CustomRemediationGuidance,
		},
	}, nil
}

// GetOrganizationPolicy gets an OrganizationPolicy by id
func (s *Server) GetOrganizationPolicy(ctx context.Context, req *proto.GetOrganizationPolicyRequest) (*proto.GetOrganizationPolicyResponse, error) {
	orgPolicy, err := s.app.Subsystems.Storage.GetOrganizationPolicyByOrgID(ctx, req.OrganizationId)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			return nil, twirp.NotFoundError("policy not found")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	protoLicenses := PolicyModelMapper{}.LicenseListToProto(orgPolicy.Policy.PolicyLicenses)
	protoPackages, err := PolicyModelMapper{}.PackagesToProto(orgPolicy.Policy.Packages)
	if err != nil {
		return nil, twirp.InternalErrorWith(fmt.Errorf("error mapping response: %w", err))
	}
	return &proto.GetOrganizationPolicyResponse{
		Policy: &proto.OrganizationPolicy{
			Licenses:       protoLicenses,
			Packages:       protoPackages,
			OrganizationId: orgPolicy.OrganizationID,
			CreatedAt:      timestamppb.New(orgPolicy.CreatedAt),
		},
	}, nil
}

// CreateEnterprisePolicy creates a new enterprise policy.
func (s *Server) CreateEnterprisePolicy(ctx context.Context, req *proto.CreateEnterprisePolicyRequest) (*proto.CreateEnterprisePolicyResponse, error) {
	if len(req.CustomRemediationGuidance) > maxRemediationGuidanceLength {
		return nil, twirp.InvalidArgumentError("custom_remediation_guidance", fmt.Sprintf("length must be less than %d characters", maxRemediationGuidanceLength))
	}
	policyModel := PolicyModelMapper{}.FromProto(req.Licenses, req.Packages)
	enterprisePolicy, err := s.app.Subsystems.Storage.CreateEnterprisePolicy(ctx, req.EnterpriseId, policyModel, req.CustomRemediationGuidance)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	resPackages, err := PolicyModelMapper{}.PackagesToProto(enterprisePolicy.Policy.Packages)
	if err != nil {
		return nil, twirp.InternalErrorWith(fmt.Errorf("error mapping response: %w", err))
	}
	return &proto.CreateEnterprisePolicyResponse{
		Policy: &proto.EnterprisePolicy{
			Licenses:                  req.Licenses,
			Packages:                  resPackages,
			EnterpriseId:              enterprisePolicy.EnterpriseID,
			CreatedAt:                 timestamppb.New(enterprisePolicy.CreatedAt),
			CustomRemediationGuidance: enterprisePolicy.CustomRemediationGuidance,
		},
	}, nil
}

// GetEnterprisePolicy gets an EnterprisePolicy by id
func (s *Server) GetEnterprisePolicy(ctx context.Context, req *proto.GetEnterprisePolicyRequest) (*proto.GetEnterprisePolicyResponse, error) {
	enterprisePolicy, err := s.app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, req.EnterpriseId)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			return nil, twirp.NotFoundError("policy not found")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	protoLicenses := PolicyModelMapper{}.LicenseListToProto(enterprisePolicy.Policy.PolicyLicenses)
	protoPackages, err := PolicyModelMapper{}.PackagesToProto(enterprisePolicy.Policy.Packages)
	if err != nil {
		return nil, twirp.InternalErrorWith(fmt.Errorf("error mapping response: %w", err))
	}
	return &proto.GetEnterprisePolicyResponse{
		Policy: &proto.EnterprisePolicy{
			Licenses:     protoLicenses,
			Packages:     protoPackages,
			EnterpriseId: enterprisePolicy.EnterpriseID,
			CreatedAt:    timestamppb.New(enterprisePolicy.CreatedAt),
		},
	}, nil
}

// CreateRepositoryPolicy creates a new repository policy.
func (s *Server) CreateRepositoryPolicy(ctx context.Context, req *proto.CreateRepositoryPolicyRequest) (*proto.CreateRepositoryPolicyResponse, error) {
	packages := PolicyModelMapper{}.packages(req.Packages)
	licenseEntries := PolicyModelMapper{}.LicenseEntriesFromProto(req.Licenses)
	repoRefinement := &models.RepositoryRefinement{
		Packages: packages,
		Licenses: models.LicenseList{
			Allowed: licenseEntries,
		},
	}
	repoPolicy, err := s.app.Subsystems.Storage.CreateRepositoryPolicy(ctx, req.RepositoryId, req.OrganizationId, repoRefinement)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	resPackages, err := PolicyModelMapper{}.PackagesToProto(repoPolicy.Policy.Packages)
	if err != nil {
		return nil, twirp.InternalErrorWith(fmt.Errorf("error mapping response: %w", err))
	}
	allowedLicenses := make([]*proto.LicenseEntry, 0, len(repoPolicy.Policy.Licenses.Allowed))
	for _, license := range repoPolicy.Policy.Licenses.Allowed {
		allowedLicenses = append(allowedLicenses, &proto.LicenseEntry{
			SpdxId:   license.SpdxID,
			Contexts: license.Contexts,
		})
	}
	return &proto.CreateRepositoryPolicyResponse{
		Policy: &proto.RepositoryPolicy{
			Licenses:       &proto.PolicyLicenses{Allowed: allowedLicenses},
			Packages:       resPackages,
			RepositoryId:   repoPolicy.RepositoryID,
			OrganizationId: repoPolicy.OrganizationID,
			CreatedAt:      timestamppb.New(repoPolicy.CreatedAt),
		},
	}, nil
}

// GetRepositoryPolicy gets a RepositoryPolicy by id
func (s *Server) GetRepositoryPolicy(ctx context.Context, req *proto.GetRepositoryPolicyRequest) (*proto.GetRepositoryPolicyResponse, error) {
	repoPolicy, err := s.app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, req.RepositoryId)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			return nil, twirp.NotFoundError("policy not found")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	protoPackages, err := PolicyModelMapper{}.PackagesToProto(repoPolicy.Policy.Packages)
	if err != nil {
		return nil, twirp.InternalErrorWith(fmt.Errorf("error mapping response: %w", err))
	}
	allowedLicenses := make([]*proto.LicenseEntry, 0, len(repoPolicy.Policy.Licenses.Allowed))
	for _, license := range repoPolicy.Policy.Licenses.Allowed {
		allowedLicenses = append(allowedLicenses, &proto.LicenseEntry{
			SpdxId:   license.SpdxID,
			Contexts: license.Contexts,
		})
	}
	return &proto.GetRepositoryPolicyResponse{
		Policy: &proto.RepositoryPolicy{
			Licenses:       &proto.PolicyLicenses{Allowed: allowedLicenses},
			Packages:       protoPackages,
			RepositoryId:   repoPolicy.RepositoryID,
			OrganizationId: repoPolicy.OrganizationID,
			CreatedAt:      timestamppb.New(repoPolicy.CreatedAt),
		},
	}, nil
}
