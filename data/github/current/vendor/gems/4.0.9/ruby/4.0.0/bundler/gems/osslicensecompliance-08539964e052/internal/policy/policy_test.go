package policy_test

import (
	"testing"
	"testing/synctest"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/eventpublisher"
	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/policy"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	gproto "google.golang.org/protobuf/proto"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
)

func newTestApp(t *testing.T) *application.Application {
	t.Helper()
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	t.Cleanup(func() {
		err = app.Close()
		if err != nil {
			t.Errorf("failed to close app: %v", err)
		}
	})
	return app
}

func TestLicenseUpdater_AddLicenses_OrganizationLevel(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	orgID := uint64(42)

	_, err := app.Subsystems.Storage.CreateOrganizationPolicy(ctx, &proto.OrganizationPolicy{
		OrganizationId: orgID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
			{
				Name: "internal",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
			{
				Name: "network",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
		},
	})
	require.NoError(t, err)

	updater, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, orgID)
	require.NoError(t, err)

	err = updater.AddLicenses(ctx, []string{"GPL-3.0"}, testhelpers.AllDistributionContexts)
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetOrganizationPolicyByOrgID(ctx, orgID)
	require.NoError(t, err)
	require.Len(t, resultPolicy.DistributionPolicies, 3)
	licenses := resultPolicy.DistributionPolicies[0].Licenses
	require.Len(t, licenses.Allowed, 2)

	licenseIDs := []string{}
	for _, license := range licenses.Allowed {
		licenseIDs = append(licenseIDs, license.SpdxId)
	}
	assert.ElementsMatch(t, []string{"MIT", "GPL-3.0"}, licenseIDs)
}

func TestLicenseUpdater_AddLicenses_EnterpriseLevel(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	entID := uint64(7)

	_, err := app.Subsystems.Storage.CreateEnterprisePolicy(ctx, &proto.EnterprisePolicy{
		EnterpriseId: entID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
			{
				Name: "internal",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
			{
				Name: "network",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
		},
	})
	require.NoError(t, err)

	updater, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, entID)
	require.NoError(t, err)

	err = updater.AddLicenses(ctx, []string{"GPL-3.0"}, testhelpers.AllDistributionContexts)
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, entID)
	require.NoError(t, err)
	require.Len(t, resultPolicy.DistributionPolicies, 3)
	licenses := resultPolicy.DistributionPolicies[0].Licenses
	require.Len(t, licenses.Allowed, 2)

	licenseIDs := []string{}
	for _, license := range licenses.Allowed {
		licenseIDs = append(licenseIDs, license.SpdxId)
	}
	assert.ElementsMatch(t, []string{"MIT", "GPL-3.0"}, licenseIDs)
}

func TestLicenseUpdater_AddLicenses_NoDuplicates(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)

	_, err := app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts},
				{SpdxId: "GPL-3.0", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	updater, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repositoryID)
	require.NoError(t, err)

	err = updater.AddLicenses(ctx, []string{"GPL-3.0"}, testhelpers.AllDistributionContexts)
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, repositoryID)
	require.NoError(t, err)

	licenses := resultPolicy.GetLicenses()
	require.Len(t, licenses.Allowed, 2)

	licenseIDs := []string{}
	for _, license := range licenses.Allowed {
		licenseIDs = append(licenseIDs, license.SpdxId)
	}
	assert.ElementsMatch(t, []string{"MIT", "GPL-3.0"}, licenseIDs)
}

func TestLicenseUpdater_AddLicenses_CreatesRepositoryPolicy(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)

	updater, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repositoryID)
	require.NoError(t, err)

	err = updater.AddLicenses(ctx, []string{"GPL-3.0"}, testhelpers.AllDistributionContexts)
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, repositoryID)
	require.NoError(t, err)
	licenses := resultPolicy.Licenses
	require.Len(t, licenses.Allowed, 1)
	assert.Equal(t, "GPL-3.0", licenses.Allowed[0].SpdxId)
}

func TestLicenseUpdater_AddLicenses_CreatesOrganizationPolicy(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	orgID := uint64(42)

	updater, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, orgID)
	require.NoError(t, err)

	err = updater.AddLicenses(ctx, []string{"GPL-3.0"}, testhelpers.AllDistributionContexts)
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetOrganizationPolicyByOrgID(ctx, orgID)
	require.NoError(t, err)
	require.Len(t, resultPolicy.DistributionPolicies, 3)
	licenses := resultPolicy.DistributionPolicies[0].Licenses
	require.Len(t, licenses.Allowed, 1)
	assert.Equal(t, "GPL-3.0", licenses.Allowed[0].SpdxId)
}

func TestLicenseUpdater_AddLicenses_CreatesEnterprisePolicy(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	entID := uint64(7)

	updater, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, entID)
	require.NoError(t, err)

	err = updater.AddLicenses(ctx, []string{"GPL-3.0"}, testhelpers.AllDistributionContexts)
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, entID)
	require.NoError(t, err)
	require.Len(t, resultPolicy.DistributionPolicies, 3)
	licenses := resultPolicy.DistributionPolicies[0].Licenses
	require.Len(t, licenses.Allowed, 1)
	assert.Equal(t, "GPL-3.0", licenses.Allowed[0].SpdxId)
}

func TestPackageUpdater_AddPackage_CreatesPolicy(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)

	packagePolicy := &proto.PackagePolicy{
		PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:                "lodash",
		Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		Reason:              "Exception created via API",
		ExtraAllowedSpdxIds: []string{"GPL-2.0"},
		Contexts:            []string{"distributed"},
	}

	tests := []struct {
		name   string
		level  proto.PolicyLevel
		entity uint64
	}{
		{"repository", proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repositoryID},
		{"organization", proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, orgID},
		{"enterprise", proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, entID},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			updater, err := policy.NewWriter(app, tt.level, tt.entity)
			require.NoError(t, err)

			err = updater.AddPackage(ctx, packagePolicy, []string{"distributed"})
			require.NoError(t, err)

			var storedPolicy *proto.PackagePolicy
			switch tt.level {
			case proto.PolicyLevel_POLICY_LEVEL_REPOSITORY:
				repoPolicy, err := app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, repositoryID)
				require.NoError(t, err)
				require.NotNil(t, repoPolicy)
				for _, pp := range repoPolicy.Packages {
					if pp.Name == "lodash" {
						storedPolicy = pp
						break
					}
				}
			case proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION:
				orgPolicy, err := app.Subsystems.Storage.GetOrganizationPolicyByOrgID(ctx, orgID)
				require.NoError(t, err)
				require.NotNil(t, orgPolicy)
				for _, pp := range orgPolicy.DistributionPolicies[0].Packages {
					if pp.Name == "lodash" {
						storedPolicy = pp
						break
					}
				}
			case proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE:
				entPolicy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, entID)
				require.NoError(t, err)
				require.NotNil(t, entPolicy)
				for _, pp := range entPolicy.DistributionPolicies[0].Packages {
					if pp.Name == "lodash" {
						storedPolicy = pp
						break
					}
				}
			default:
				t.Fatalf("unexpected policy level: %v", tt.level)
			}
			require.NotNil(t, storedPolicy)
			require.Equal(t, packagePolicy.Name, storedPolicy.Name)
			require.Equal(t, packagePolicy.Action, storedPolicy.Action)
			require.Equal(t, packagePolicy.Reason, storedPolicy.Reason)
			require.ElementsMatch(t, packagePolicy.ExtraAllowedSpdxIds, storedPolicy.ExtraAllowedSpdxIds)
		})
	}
}

func TestLicenseRemover_RemoveLicenses_RepositoryLevel(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repoID := uint64(123)

	_, err := app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
		RepositoryId: repoID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-2.0", Contexts: testhelpers.AllDistributionContexts},
				{SpdxId: "Apache-2.0", Contexts: testhelpers.AllDistributionContexts},
				{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	remover, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repoID)
	require.NoError(t, err)

	err = remover.RemoveLicenses(ctx, []string{"GPL-2.0", "MIT"}, "")
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, repoID)
	require.NoError(t, err)
	require.Len(t, resultPolicy.Licenses.Allowed, 1)
	assert.Equal(t, "Apache-2.0", resultPolicy.Licenses.Allowed[0].SpdxId)
}

func TestLicenseRemover_RemoveLicenses_EnterpriseLevel(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	entID := uint64(7)

	_, err := app.Subsystems.Storage.CreateEnterprisePolicy(ctx, &proto.EnterprisePolicy{
		EnterpriseId: entID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "GPL-2.0"},
						{SpdxId: "Apache-2.0"},
						{SpdxId: "MIT"},
					},
				},
			},
		},
	})
	require.NoError(t, err)

	remover, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, entID)
	require.NoError(t, err)

	err = remover.RemoveLicenses(ctx, []string{"Apache-2.0"}, "distributed")
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, entID)
	require.NoError(t, err)
	allowedLicenses := resultPolicy.DistributionPolicies[0].Licenses.Allowed
	require.Len(t, allowedLicenses, 2)

	licenseIDs := []string{}
	for _, l := range allowedLicenses {
		licenseIDs = append(licenseIDs, l.SpdxId)
	}
	assert.Contains(t, licenseIDs, "GPL-2.0")
	assert.Contains(t, licenseIDs, "MIT")
	assert.NotContains(t, licenseIDs, "Apache-2.0")
}

func TestLicenseRemover_RemoveLicenses_ContextSpecific(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	entID := uint64(7)

	_, err := app.Subsystems.Storage.CreateEnterprisePolicy(ctx, &proto.EnterprisePolicy{
		EnterpriseId: entID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}},
				},
			},
			{
				Name: "network",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}},
				},
			},
		},
	})
	require.NoError(t, err)

	remover, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, entID)
	require.NoError(t, err)

	err = remover.RemoveLicenses(ctx, []string{"MIT"}, "network")
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, entID)
	require.NoError(t, err)

	for _, dp := range resultPolicy.DistributionPolicies {
		switch dp.Name {
		case "network":
			assert.Len(t, dp.Licenses.Allowed, 0, "MIT should be removed from network")
		case "distributed":
			assert.Len(t, dp.Licenses.Allowed, 1, "MIT should remain in distributed")
		default:
			t.Fatalf("unexpected distribution policy: %s", dp.Name)
		}
	}
}

func TestPackageRemover_RemovePackages_RepositoryLevel(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repoID := uint64(123)

	_, err := app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
		RepositoryId: repoID,
		Packages: []*proto.PackagePolicy{
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "express"},
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "react"},
		},
	})
	require.NoError(t, err)

	remover, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repoID)
	require.NoError(t, err)

	err = remover.RemovePackages(ctx, []*proto.PackagePolicy{
		{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
		{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "react"},
	}, "")
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, repoID)
	require.NoError(t, err)
	require.Len(t, resultPolicy.Packages, 1)
	assert.Equal(t, "express", resultPolicy.Packages[0].Name)
}

func TestPackageRemover_RemovePackages_EnterpriseLevel(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	entID := uint64(7)

	_, err := app.Subsystems.Storage.CreateEnterprisePolicy(ctx, &proto.EnterprisePolicy{
		EnterpriseId: entID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Packages: []*proto.PackagePolicy{
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "express"},
				},
			},
		},
	})
	require.NoError(t, err)

	remover, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, entID)
	require.NoError(t, err)

	err = remover.RemovePackages(ctx, []*proto.PackagePolicy{
		{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
	}, "distributed")
	require.NoError(t, err)

	resultPolicy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, entID)
	require.NoError(t, err)
	require.Len(t, resultPolicy.DistributionPolicies[0].Packages, 1)
	assert.Equal(t, "express", resultPolicy.DistributionPolicies[0].Packages[0].Name)
}

func TestOrganizationWriter_RemoveLicenses_RequiresDistributionContext(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	orgID := uint64(42)

	writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, orgID)
	require.NoError(t, err)

	err = writer.RemoveLicenses(ctx, []string{"MIT"}, "")

	assert.ErrorIs(t, err, policy.ErrDistributionContextRequired)
}

func TestOrganizationWriter_RemovePackages_RequiresDistributionContext(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	orgID := uint64(42)

	writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, orgID)
	require.NoError(t, err)

	err = writer.RemovePackages(ctx, []*proto.PackagePolicy{{Name: "test"}}, "")

	assert.ErrorIs(t, err, policy.ErrDistributionContextRequired)
}

func TestEnterpriseWriter_RemoveLicenses_RequiresDistributionContext(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	entID := uint64(42)

	writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, entID)
	require.NoError(t, err)

	err = writer.RemoveLicenses(ctx, []string{"MIT"}, "")

	assert.ErrorIs(t, err, policy.ErrDistributionContextRequired)
}

func TestEnterpriseWriter_RemovePackages_RequiresDistributionContext(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	entID := uint64(42)

	writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, entID)
	require.NoError(t, err)

	err = writer.RemovePackages(ctx, []*proto.PackagePolicy{{Name: "test"}}, "")

	assert.ErrorIs(t, err, policy.ErrDistributionContextRequired)
}

func TestAddLicenses_PublishesPolicyCreatedEvent_WhenPolicyDoesNotExist(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		repoID := uint64(123)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repoID)
		require.NoError(t, err)

		err = writer.AddLicenses(ctx, []string{"MIT"}, testhelpers.AllDistributionContexts)
		require.NoError(t, err)

		tp.AssertMessagesPublishedInAnyOrder(t, "github.dependencygraph.v1.LicensePolicyChanged", []gproto.Message{
			&dependencygraphv1.LicensePolicyChanged{
				Action:   eventpublisher.PolicyActionPolicyCreated,
				Level:    eventpublisher.PolicyLevelRepository,
				EntityId: int64(repoID),
			},
			&dependencygraphv1.LicensePolicyChanged{
				Action:   eventpublisher.PolicyActionLicenseAdded,
				Level:    eventpublisher.PolicyLevelRepository,
				EntityId: int64(repoID),
			},
		})
	})
}

func TestAddLicenses_PublishesLicenseAddedEvent_WhenPolicyExists(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		repoID := uint64(123)

		_, err := app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
			RepositoryId: repoID,
			Licenses:     &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}}},
		})
		require.NoError(t, err)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repoID)
		require.NoError(t, err)

		err = writer.AddLicenses(ctx, []string{"GPL-3.0"}, testhelpers.AllDistributionContexts)
		require.NoError(t, err)

		tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicensePolicyChanged", &dependencygraphv1.LicensePolicyChanged{
			Action:   eventpublisher.PolicyActionLicenseAdded,
			Level:    eventpublisher.PolicyLevelRepository,
			EntityId: int64(repoID),
		})
	})
}

func TestRemoveLicenses_PublishesLicenseRemovedEvent(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		repoID := uint64(123)

		_, err := app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
			RepositoryId: repoID,
			Licenses:     &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}}},
		})
		require.NoError(t, err)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repoID)
		require.NoError(t, err)

		err = writer.RemoveLicenses(ctx, []string{"MIT"}, "")
		require.NoError(t, err)

		tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicensePolicyChanged", &dependencygraphv1.LicensePolicyChanged{
			Action:   eventpublisher.PolicyActionLicenseRemoved,
			Level:    eventpublisher.PolicyLevelRepository,
			EntityId: int64(repoID),
		})
	})
}

func TestAddPackage_PublishesPolicyCreatedEvent_WhenPolicyDoesNotExist(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		repoID := uint64(123)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repoID)
		require.NoError(t, err)

		err = writer.AddPackage(ctx, &proto.PackagePolicy{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
		}, []string{"distributed"})
		require.NoError(t, err)

		tp.AssertMessagesPublishedInAnyOrder(t, "github.dependencygraph.v1.LicensePolicyChanged", []gproto.Message{
			&dependencygraphv1.LicensePolicyChanged{
				Action:   eventpublisher.PolicyActionPolicyCreated,
				Level:    eventpublisher.PolicyLevelRepository,
				EntityId: int64(repoID),
			},
			&dependencygraphv1.LicensePolicyChanged{
				Action:   eventpublisher.PolicyActionPackageExemptionAdded,
				Level:    eventpublisher.PolicyLevelRepository,
				EntityId: int64(repoID),
			},
		})
	})
}

func TestAddPackage_PublishesPackageExemptionAddedEvent_WhenPolicyExists(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		repoID := uint64(123)

		_, err := app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
			RepositoryId: repoID,
		})
		require.NoError(t, err)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repoID)
		require.NoError(t, err)

		err = writer.AddPackage(ctx, &proto.PackagePolicy{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
		}, []string{"distributed"})
		require.NoError(t, err)

		tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicensePolicyChanged", &dependencygraphv1.LicensePolicyChanged{
			Action:   eventpublisher.PolicyActionPackageExemptionAdded,
			Level:    eventpublisher.PolicyLevelRepository,
			EntityId: int64(repoID),
		})
	})
}

func TestRemovePackages_PublishesPackageExemptionRemovedEvent(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		repoID := uint64(123)

		_, err := app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
			RepositoryId: repoID,
			Packages: []*proto.PackagePolicy{
				{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
			},
		})
		require.NoError(t, err)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, repoID)
		require.NoError(t, err)

		err = writer.RemovePackages(ctx, []*proto.PackagePolicy{
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
		}, "")
		require.NoError(t, err)

		tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicensePolicyChanged", &dependencygraphv1.LicensePolicyChanged{
			Action:   eventpublisher.PolicyActionPackageExemptionRemoved,
			Level:    eventpublisher.PolicyLevelRepository,
			EntityId: int64(repoID),
		})
	})
}

func TestAddLicenses_OrganizationLevel_PublishesEventWithDistributionContexts(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		orgID := uint64(42)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, orgID)
		require.NoError(t, err)

		err = writer.AddLicenses(ctx, []string{"MIT"}, testhelpers.AllDistributionContexts)
		require.NoError(t, err)

		tp.AssertMessagesPublishedInAnyOrder(t, "github.dependencygraph.v1.LicensePolicyChanged", []gproto.Message{
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionPolicyCreated,
				Level:                eventpublisher.PolicyLevelOrganization,
				EntityId:             int64(orgID),
				DistributionContexts: testhelpers.AllDistributionContexts,
			},
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionLicenseAdded,
				Level:                eventpublisher.PolicyLevelOrganization,
				EntityId:             int64(orgID),
				DistributionContexts: testhelpers.AllDistributionContexts,
			},
		})
	})
}

func TestRemoveLicenses_OrganizationLevel_PublishesEventWithDistributionContext(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		orgID := uint64(42)

		_, err := app.Subsystems.Storage.CreateOrganizationPolicy(ctx, &proto.OrganizationPolicy{
			OrganizationId: orgID,
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name:     "distributed",
					Licenses: &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}}},
				},
			},
		})
		require.NoError(t, err)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, orgID)
		require.NoError(t, err)

		err = writer.RemoveLicenses(ctx, []string{"MIT"}, "distributed")
		require.NoError(t, err)

		tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicensePolicyChanged", &dependencygraphv1.LicensePolicyChanged{
			Action:               eventpublisher.PolicyActionLicenseRemoved,
			Level:                eventpublisher.PolicyLevelOrganization,
			EntityId:             int64(orgID),
			DistributionContexts: []string{"distributed"},
		})
	})
}

func TestAddLicenses_EnterpriseLevel_PublishesEventWithDistributionContexts(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		entID := uint64(7)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, entID)
		require.NoError(t, err)

		err = writer.AddLicenses(ctx, []string{"MIT"}, testhelpers.AllDistributionContexts)
		require.NoError(t, err)

		tp.AssertMessagesPublishedInAnyOrder(t, "github.dependencygraph.v1.LicensePolicyChanged", []gproto.Message{
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionPolicyCreated,
				Level:                eventpublisher.PolicyLevelEnterprise,
				EntityId:             int64(entID),
				DistributionContexts: testhelpers.AllDistributionContexts,
			},
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionLicenseAdded,
				Level:                eventpublisher.PolicyLevelEnterprise,
				EntityId:             int64(entID),
				DistributionContexts: testhelpers.AllDistributionContexts,
			},
		})
	})
}

func TestRemoveLicenses_EnterpriseLevel_PublishesEventWithDistributionContext(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		entID := uint64(7)

		_, err := app.Subsystems.Storage.CreateEnterprisePolicy(ctx, &proto.EnterprisePolicy{
			EnterpriseId: entID,
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name:     "distributed",
					Licenses: &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}}},
				},
			},
		})
		require.NoError(t, err)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, entID)
		require.NoError(t, err)

		err = writer.RemoveLicenses(ctx, []string{"MIT"}, "distributed")
		require.NoError(t, err)

		tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicensePolicyChanged", &dependencygraphv1.LicensePolicyChanged{
			Action:               eventpublisher.PolicyActionLicenseRemoved,
			Level:                eventpublisher.PolicyLevelEnterprise,
			EntityId:             int64(entID),
			DistributionContexts: []string{"distributed"},
		})
	})
}

func TestUpdateMultiple_ChangesAreMadeAndEventsArePublished(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		enterpriseID := uint64(123)

		_, err := app.Subsystems.Storage.CreateEnterprisePolicy(ctx, &proto.EnterprisePolicy{
			EnterpriseId: enterpriseID,
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name:     "distributed",
					Licenses: &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}}},
					Packages: []*proto.PackagePolicy{
						{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
					},
				},
			},
		})
		require.NoError(t, err)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, enterpriseID)
		require.NoError(t, err)

		updates := &policy.MultipleUpdates{
			AddSpdxIDs:    []string{"GPL-3.0"},
			DeleteSpdxIDs: []string{"MIT"},
			AddPackages: []*proto.PackagePolicy{
				{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "express"},
			},
			DeletePackages: []*proto.PackagePolicy{
				{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
			},
			DistributionContext: "distributed",
		}
		err = writer.UpdateMultiple(ctx, updates)
		require.NoError(t, err)

		// Verify storage changes
		resultPolicy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, enterpriseID)
		require.NoError(t, err)
		dp := resultPolicy.DistributionPolicies[0]
		require.Len(t, dp.Licenses.Allowed, 1)
		assert.Equal(t, "GPL-3.0", dp.Licenses.Allowed[0].SpdxId)
		require.Len(t, dp.Packages, 1)
		assert.Equal(t, "express", dp.Packages[0].Name)

		expectedMessages := []gproto.Message{
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionLicenseAdded,
				Level:                eventpublisher.PolicyLevelEnterprise,
				EntityId:             int64(enterpriseID),
				DistributionContexts: []string{"distributed"},
			},
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionLicenseRemoved,
				Level:                eventpublisher.PolicyLevelEnterprise,
				EntityId:             int64(enterpriseID),
				DistributionContexts: []string{"distributed"},
			},
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionPackageExemptionAdded,
				Level:                eventpublisher.PolicyLevelEnterprise,
				EntityId:             int64(enterpriseID),
				DistributionContexts: []string{"distributed"},
			},
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionPackageExemptionRemoved,
				Level:                eventpublisher.PolicyLevelEnterprise,
				EntityId:             int64(enterpriseID),
				DistributionContexts: []string{"distributed"},
			},
		}

		tp.AssertMessagesPublishedInAnyOrder(t, "github.dependencygraph.v1.LicensePolicyChanged", expectedMessages)
	})
}

func TestUpdateMultiple_CreatesPolicyAndHandlesMixedUpdatesIfMissing(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		app := newTestApp(t)
		app.Subsystems.EventPublisher = tp.Publisher
		ctx := t.Context()
		enterpriseID := uint64(123)

		writer, err := policy.NewWriter(app, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, enterpriseID)
		require.NoError(t, err)

		updates := &policy.MultipleUpdates{
			AddSpdxIDs:    []string{"GPL-3.0"},
			DeleteSpdxIDs: []string{"MIT"},
			DeletePackages: []*proto.PackagePolicy{
				{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
			},
			DistributionContext: "distributed",
		}
		err = writer.UpdateMultiple(ctx, updates)
		require.NoError(t, err)

		resultPolicy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, enterpriseID)
		require.NoError(t, err)
		require.Len(t, resultPolicy.DistributionPolicies, 1)
		dp := resultPolicy.DistributionPolicies[0]
		require.Len(t, dp.Licenses.Allowed, 1)
		require.Len(t, dp.Packages, 0)

		expectedMessages := []gproto.Message{
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionPolicyCreated,
				Level:                eventpublisher.PolicyLevelEnterprise,
				EntityId:             int64(enterpriseID),
				DistributionContexts: []string{"distributed"},
			},
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionLicenseAdded,
				Level:                eventpublisher.PolicyLevelEnterprise,
				EntityId:             int64(enterpriseID),
				DistributionContexts: []string{"distributed"},
			},
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionLicenseRemoved,
				Level:                eventpublisher.PolicyLevelEnterprise,
				EntityId:             int64(enterpriseID),
				DistributionContexts: []string{"distributed"},
			},
			&dependencygraphv1.LicensePolicyChanged{
				Action:               eventpublisher.PolicyActionPackageExemptionRemoved,
				Level:                eventpublisher.PolicyLevelEnterprise,
				EntityId:             int64(enterpriseID),
				DistributionContexts: []string{"distributed"},
			},
		}

		tp.AssertMessagesPublishedInAnyOrder(t, "github.dependencygraph.v1.LicensePolicyChanged", expectedMessages)
	})
}
