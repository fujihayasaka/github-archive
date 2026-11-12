package twirp

import (
	"fmt"

	"github.com/github/osslicensecompliance/internal/models"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

// PolicyModelMapper maps between the proto and model representations of a policy.
type PolicyModelMapper struct{}

// FromProto converts a policy lists and packages from proto to model.
func (m PolicyModelMapper) FromProto(licenses *proto.PolicyLicenses, packages []*proto.PackagePolicy) *models.Policy {
	policy := &models.Policy{
		PolicyLicenses: m.licenses(licenses),
		Packages:       m.packages(packages),
	}

	return policy
}

func (m PolicyModelMapper) licenses(protoLicenseList *proto.PolicyLicenses) models.LicenseList {
	var allowed []models.LicenseEntry
	for _, entry := range protoLicenseList.Allowed {
		allowed = append(allowed, models.LicenseEntry{
			SpdxID:   entry.SpdxId,
			Contexts: withDefaultContexts(entry.Contexts),
		})
	}
	return models.LicenseList{
		Allowed: allowed,
	}
}

func (m PolicyModelMapper) packages(protoPackages []*proto.PackagePolicy) []models.PackagePolicy {
	packages := make([]models.PackagePolicy, 0, len(protoPackages))
	for _, protoPackage := range protoPackages {
		newEntry := models.PackagePolicy{
			PackageManager: models.PackageManager(protoPackage.PackageManager),
			PackageName:    protoPackage.Name,
			Action:         protoToModelAction(protoPackage.Action),
			Reason:         protoPackage.Reason,
			MatchLicenses:  protoPackage.MatchLicenses,
			Contexts:       withDefaultContexts(protoPackage.Contexts),
		}
		packages = append(packages, newEntry)
	}
	return packages
}

// LicenseListToProto coverts model license list to proto
func (m PolicyModelMapper) LicenseListToProto(policyLicenseList models.LicenseList) *proto.PolicyLicenses {
	var allowed []*proto.LicenseEntry
	for _, entry := range policyLicenseList.Allowed {
		allowed = append(allowed, &proto.LicenseEntry{
			SpdxId:   entry.SpdxID,
			Contexts: entry.Contexts,
		})
	}
	return &proto.PolicyLicenses{
		Allowed: allowed,
	}
}

// LicenseEntriesFromProto converts a slice of proto LicenseEntry to model LicenseEntry.
func (m PolicyModelMapper) LicenseEntriesFromProto(licenses *proto.PolicyLicenses) []models.LicenseEntry {
	licenseEntries := make([]models.LicenseEntry, 0, len(licenses.Allowed))
	for _, license := range licenses.Allowed {
		licenseEntries = append(licenseEntries, models.LicenseEntry{
			SpdxID:   license.SpdxId,
			Contexts: withDefaultContexts(license.Contexts),
		})
	}
	return licenseEntries
}

// PackagesToProto converts model package policy to proto
func (m PolicyModelMapper) PackagesToProto(packages []models.PackagePolicy) ([]*proto.PackagePolicy, error) {
	packagePolicyProto := make([]*proto.PackagePolicy, 0, len(packages))
	for _, packagePolicy := range packages {
		action, err := modelToProtoAction(packagePolicy.Action)
		if err != nil {
			return nil, err
		}

		packagePolicyProto = append(packagePolicyProto, &proto.PackagePolicy{
			PackageManager: proto.PackageManager(packagePolicy.PackageManager),
			Name:           packagePolicy.PackageName,
			Action:         action,
			Reason:         packagePolicy.Reason,
			MatchLicenses:  packagePolicy.MatchLicenses,
			Contexts:       packagePolicy.Contexts,
		})
	}

	return packagePolicyProto, nil
}

func protoToModelAction(action proto.PackageAction) models.PackageAction {
	switch action {
	case proto.PackageAction_PACKAGE_ACTION_ALLOWED:
		return models.PackageActionAllow
	case proto.PackageAction_PACKAGE_ACTION_BLOCKED:
		return models.PackageActionBlock
	case proto.PackageAction_PACKAGE_ACTION_PRIVATE:
		return models.PackageActionPrivate
	default:
		return models.PackageActionBlock
	}
}

func modelToProtoAction(action models.PackageAction) (proto.PackageAction, error) {
	switch action {
	case models.PackageActionAllow:
		return proto.PackageAction_PACKAGE_ACTION_ALLOWED, nil
	case models.PackageActionBlock:
		return proto.PackageAction_PACKAGE_ACTION_BLOCKED, nil
	case models.PackageActionPrivate:
		return proto.PackageAction_PACKAGE_ACTION_PRIVATE, nil
	default:
		return proto.PackageAction_PACKAGE_ACTION_BLOCKED, fmt.Errorf("unknown package action: %v", action.String())
	}
}

// withDefaultContexts is TEMPORARY. If no contexts are provided, default to a set of common contexts.
// This is a stop-gap until the UI actually allows you to select contexts.
// Ultimately, we should only include contexts that are explicitly set in the policy.
// Remove during https://github.com/github/dependency-graph/issues/7604
func withDefaultContexts(contexts []string) []string {
	if len(contexts) > 0 {
		return contexts
	}
	// Default contexts if none are provided
	return []string{"distributed", "network", "internal"}
}
