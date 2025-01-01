package twirp_test

import (
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/twirp"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var allDistributionContexts = []string{"distributed", "network", "internal"}

func TestPolicyModelMapper_BuildFromProtos(t *testing.T) {
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{
		{SpdxId: "MIT", Contexts: allDistributionContexts},
		{SpdxId: "BSD-3-Clause", Contexts: allDistributionContexts},
	}}

	packages := []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "lodash-reason",
			MatchLicenses:  []string{"MIT"},
			Contexts:       allDistributionContexts,
		},
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "react",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "react-reason",
			MatchLicenses:  []string{"MIT"},
			Contexts:       allDistributionContexts,
		},
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
			Name:           "rubocop",
			Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
			Reason:         "rubocop-reason",
			MatchLicenses:  []string{"BSD-3-Clause"},
			Contexts:       allDistributionContexts,
		},
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUST,
			Name:           "tokio",
			Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
			Reason:         "tokio-reason",
			MatchLicenses:  []string{"LPL-1.0"},
			Contexts:       allDistributionContexts,
		},
	}

	mapper := twirp.PolicyModelMapper{}

	gotModelPolicy := mapper.FromProto(licenses, packages)
	assert.Equal(
		t,
		&models.Policy{
			PolicyLicenses: models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}, {SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts}}},
			Packages: []models.PackagePolicy{
				{PackageManager: models.PMnpm, PackageName: "lodash", Action: models.PackageActionAllow, Reason: "lodash-reason", MatchLicenses: []string{"MIT"}, Contexts: allDistributionContexts},
				{PackageManager: models.PMnpm, PackageName: "react", Action: models.PackageActionAllow, Reason: "react-reason", MatchLicenses: []string{"MIT"}, Contexts: allDistributionContexts},
				{PackageManager: models.PMrubygems, PackageName: "rubocop", Action: models.PackageActionPrivate, Reason: "rubocop-reason", MatchLicenses: []string{"BSD-3-Clause"}, Contexts: allDistributionContexts},
				{PackageManager: models.PMrust, PackageName: "tokio", Action: models.PackageActionBlock, Reason: "tokio-reason", MatchLicenses: []string{"LPL-1.0"}, Contexts: allDistributionContexts},
			},
		},
		gotModelPolicy,
	)
}

func TestPolicyModelMapper_BuildFromProtos_DefaultToBlockedWhenUnspecified(t *testing.T) {
	packages := []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_UNKNOWN,
			Reason:         "lodash-reason",
			Contexts:       allDistributionContexts,
		},
	}
	mapper := twirp.PolicyModelMapper{}

	gotModelPolicy := mapper.FromProto(
		&proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: allDistributionContexts}, {SpdxId: "BSD-3-Clause", Contexts: allDistributionContexts}}},
		packages,
	)
	assert.Equal(
		t,
		&models.Policy{
			PolicyLicenses: models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}, {SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts}}},
			Packages: []models.PackagePolicy{
				{PackageManager: models.PMnpm, PackageName: "lodash", Action: models.PackageActionBlock, Reason: "lodash-reason", Contexts: allDistributionContexts},
			},
		},
		gotModelPolicy,
	)
}

func TestPolicyModelMapper_LicenseListToProto(t *testing.T) {
	licenses := models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}, {SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts}}}
	mapper := twirp.PolicyModelMapper{}
	gotProtoLicenseList := mapper.LicenseListToProto(licenses)
	assert.ElementsMatch(
		t,
		[]*proto.LicenseEntry{{SpdxId: "MIT", Contexts: allDistributionContexts}, {SpdxId: "BSD-3-Clause", Contexts: allDistributionContexts}},
		gotProtoLicenseList.Allowed,
	)
}

func TestPolicyModelMapper_PackagesToProto(t *testing.T) {
	packages := []models.PackagePolicy{
		{PackageManager: models.PMnpm, PackageName: "lodash", Action: models.PackageActionAllow, Reason: "lodash-reason", MatchLicenses: []string{"MIT"}},
		{PackageManager: models.PMrubygems, PackageName: "rubocop", Action: models.PackageActionPrivate, Reason: "rubocop-reason", MatchLicenses: []string{"BSD-3-Clause"}},
		{PackageManager: models.PMrust, PackageName: "tokio", Action: models.PackageActionBlock, Reason: "tokio-reason", MatchLicenses: []string{"LPL-1.0"}},
	}
	mapper := twirp.PolicyModelMapper{}
	gotProtoPackages, err := mapper.PackagesToProto(packages)
	require.NoError(t, err)

	assert.ElementsMatch(
		t,
		[]*proto.PackagePolicy{
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "lodash",
				Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
				Reason:         "lodash-reason",
				MatchLicenses:  []string{"MIT"},
			},
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
				Name:           "rubocop",
				Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
				Reason:         "rubocop-reason",
				MatchLicenses:  []string{"BSD-3-Clause"},
			},
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUST,
				Name:           "tokio",
				Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
				Reason:         "tokio-reason",
				MatchLicenses:  []string{"LPL-1.0"},
			},
		},
		gotProtoPackages,
	)
}
