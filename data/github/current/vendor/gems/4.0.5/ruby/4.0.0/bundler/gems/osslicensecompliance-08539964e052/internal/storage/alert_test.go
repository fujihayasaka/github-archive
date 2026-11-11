package storage_test

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"testing"
	"time"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/storage/sqlite"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetAlert_WithNoMatchReturnsNil(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	result, err := s.GetAlert(ctx, 1, 1)
	r.NoError(err)
	r.Nil(result)
}

func TestGetAlertByID_WithNoMatchReturnsNil(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	result, err := s.GetAlertByID(ctx, 999)
	r.NoError(err)
	r.Nil(result)
}

func TestGetAlertByID_ReturnsAlert(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	enterpriseID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)

	retrievedAlert, err := s.GetAlertByID(ctx, createdAlert.ID)
	r.NoError(err)
	r.NotNil(retrievedAlert)

	r.EqualExportedValues(createdAlert, retrievedAlert)
}

func TestCreateAlert_CreatesAnAlert_ThatIsRetrievableWithDefaultValues(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	enterpriseID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, createdAlert.Number)
	r.NoError(err)
	r.NotNil(retrievedAlert)

	r.EqualExportedValues(createdAlert, retrievedAlert, "returned alert should match response of GetAlert")

	r.NotZero(retrievedAlert.ID)
	r.Equal(uint32(1), retrievedAlert.Number)
	r.Equal(models.AlertStatusOpen, retrievedAlert.Status)
	r.Equal(models.AlertResolutionUnknown, retrievedAlert.Resolution) // default is Unknown
	r.NotZero(retrievedAlert.CreatedAt)
	now := time.Now()
	r.True(now.After(retrievedAlert.CreatedAt))
	r.Equal(alert.RepositoryID, retrievedAlert.RepositoryID)
	r.Equal(alert.OrganizationID, retrievedAlert.OrganizationID)
	r.Equal(alert.EnterpriseID, retrievedAlert.EnterpriseID)
	r.Equal(alert.ManifestName, retrievedAlert.ManifestName)
	r.Equal(alert.ManifestLineNumber, retrievedAlert.ManifestLineNumber)
	r.Equal(alert.PackageEcosystem, retrievedAlert.PackageEcosystem)
	r.Equal(alert.PackageName, retrievedAlert.PackageName)
	r.Equal(alert.PackageVersion, retrievedAlert.PackageVersion)
	r.Equal(alert.SPDXLicenseExpression, retrievedAlert.SPDXLicenseExpression)
	r.Equal(alert.PullRequestNumber, retrievedAlert.PullRequestNumber)
}

func TestCreateAlert_CreatesAnAlert_ThatIsRetrievableWithSetResolutionValue(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	enterpriseID := uint64(3)
	repositoryID := uint64(1)
	resolution := models.AlertResolutionLicensesAdded
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		Resolution:            resolution,
		RepositoryID:          repositoryID,
		OrganizationID:        1,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, 1)
	r.NoError(err)

	r.Equal(resolution, retrievedAlert.Resolution)
	r.EqualExportedValues(createdAlert, retrievedAlert, "returned alert should match response of GetAlert")
}

func TestGetOpenAlertsByLicenses_ReturnsAlertsInNonClosedStatus(t *testing.T) {
	ctx := t.Context()
	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	openStatuses := []models.AlertStatus{models.AlertStatusOpen, models.AlertStatusReviewRequested, models.AlertStatusReviewDenied}
	statuses := slices.Clone(openStatuses)
	statuses = append(statuses, models.AlertStatusClosed)
	s := newSqliteStorage(t)
	for _, status := range statuses {
		alert := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        organizationID,
			EnterpriseID:          &enterpriseID,
			ManifestName:          "package.json",
			ManifestLineNumber:    1,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "test-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "MIT",
			Status:                status,
			PullRequestNumber:     &pullRequestNumber,
		}

		_, err := s.CreateAlert(ctx, alert)
		require.NoError(t, err)
	}
	retrievedAlerts, err := s.GetOpenAlertsByLicenses(ctx, []string{"MIT"}, storage.NewRepositoryScope(repositoryID))
	require.NoError(t, err)

	assert.Equal(t, 3, len(retrievedAlerts), "expected 3 alerts to be retrieved")
	returnedStatuses := make([]models.AlertStatus, 0, len(retrievedAlerts))
	for _, alert := range retrievedAlerts {
		returnedStatuses = append(returnedStatuses, alert.Status)
	}
	assert.ElementsMatch(t, openStatuses, returnedStatuses, "expected open statuses to be present got %v", returnedStatuses)
	assert.NotContains(t, returnedStatuses, models.AlertStatusClosed, "expected closed status to not be present got %v", returnedStatuses)
}

func TestGetOpenAlertsByLicenses_MatchesLicenseStrings(t *testing.T) {
	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	testCases := []struct {
		name                   string
		alertLicenseExpression string
		searchLicense          string
		alertReturned          bool
	}{
		{
			name:                   "exact match single license",
			alertLicenseExpression: "MIT",
			searchLicense:          "MIT",
			alertReturned:          true,
		},
		{
			name:                   "returns alert when one license in expression matches OR",
			alertLicenseExpression: "MIT OR Apache-2.0",
			searchLicense:          "MIT",
			alertReturned:          true,
		},
		{
			name:                   "returns alert when one license in expression matches AND",
			alertLicenseExpression: "MIT AND ISC",
			searchLicense:          "MIT",
			alertReturned:          true,
		},
		{
			name:                   "case insensitive match lowercase",
			alertLicenseExpression: "MIT",
			searchLicense:          "mit",
			alertReturned:          true,
		},
		{
			name:                   "case insensitive match mixed case",
			alertLicenseExpression: "Apache-2.0",
			searchLicense:          "apache-2.0",
			alertReturned:          true,
		},
		{
			name:                   "matches exact spdx licenses only, not partial strings",
			alertLicenseExpression: "MIT-Click",
			searchLicense:          "MIT",
			alertReturned:          false,
		},
		{
			name:                   "no match different license",
			alertLicenseExpression: "GPL-3.0",
			searchLicense:          "MIT",
			alertReturned:          false,
		},
		{
			name:                   "complex SPDX expression",
			alertLicenseExpression: "(MIT OR Apache-2.0) AND ISC",
			searchLicense:          "ISC",
			alertReturned:          true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			s := newSqliteStorage(t)
			alert := models.Alert{
				RepositoryID:          repositoryID,
				OrganizationID:        organizationID,
				EnterpriseID:          &enterpriseID,
				ManifestName:          "package.json",
				ManifestLineNumber:    1,
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           fmt.Sprintf("test-package-%s", tc.name),
				PackageVersion:        "1.0.0",
				SPDXLicenseExpression: tc.alertLicenseExpression,
				PullRequestNumber:     &pullRequestNumber,
			}

			_, err := s.CreateAlert(t.Context(), alert)
			require.NoError(t, err)
			retrievedAlerts, err := s.GetOpenAlertsByLicenses(t.Context(), []string{tc.searchLicense}, storage.NewRepositoryScope(repositoryID))
			require.NoError(t, err)
			assert.Equal(t, tc.alertReturned, len(retrievedAlerts) == 1, "expected alerts retrieved to be %v", tc.alertReturned)
		})
	}
}

func TestGetOpenAlertsByLicenses_RetrievesAlertsByLevel(t *testing.T) {
	ctx := t.Context()
	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)
	s := newSqliteStorage(t)
	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	require.NoError(t, err)

	testCases := []struct {
		name  string
		scope storage.AlertScope
	}{
		{
			name:  "Where Repository ID",
			scope: storage.NewRepositoryScope(repositoryID),
		},
		{
			name:  "Where Organization ID",
			scope: storage.NewOrganizationScope(organizationID),
		},
		{
			name:  "Where Enterprise ID",
			scope: storage.NewEnterpriseScope(enterpriseID),
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			retrievedAlerts, err := s.GetOpenAlertsByLicenses(ctx, []string{"MIT"}, tc.scope)
			require.NoError(t, err)

			assert.EqualExportedValues(
				t,
				[]*models.Alert{createdAlert},
				retrievedAlerts,
			)
		})
	}
}

func TestGetOpenAlertsByLicenses_ReturnsEmptySliceIfNotFound(t *testing.T) {
	ctx := t.Context()
	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)
	s := newSqliteStorage(t)
	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	_, err := s.CreateAlert(ctx, alert)
	require.NoError(t, err)

	retrievedAlerts, err := s.GetOpenAlertsByLicenses(ctx, []string{"foo"}, storage.NewRepositoryScope(repositoryID))
	require.NoError(t, err)

	assert.Empty(t, retrievedAlerts)
}

func TestGetOpenAlertsByLicenses_MultipleLicenseStrings(t *testing.T) {
	ctx := t.Context()
	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)
	s := newSqliteStorage(t)

	mitAlert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "mit-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}
	gplAlert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    2,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "gpl-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
		PullRequestNumber:     &pullRequestNumber,
	}
	apache2Alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    3,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "apache-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "Apache-2.0",
		PullRequestNumber:     &pullRequestNumber,
	}

	createdMIT, err := s.CreateAlert(ctx, mitAlert)
	require.NoError(t, err)
	createdGPL, err := s.CreateAlert(ctx, gplAlert)
	require.NoError(t, err)
	_, err = s.CreateAlert(ctx, apache2Alert)
	require.NoError(t, err)

	retrievedAlerts, err := s.GetOpenAlertsByLicenses(ctx, []string{"MIT", "GPL-3.0"}, storage.NewRepositoryScope(repositoryID))
	require.NoError(t, err)

	require.Equal(t, 2, len(retrievedAlerts), "expected 2 alerts to be retrieved")
	retrievedIDs := []uint64{retrievedAlerts[0].ID, retrievedAlerts[1].ID}
	expectedIDs := []uint64{createdMIT.ID, createdGPL.ID}
	assert.ElementsMatch(t, expectedIDs, retrievedIDs)
}

func TestGetOpenAlertsByLicenses_CompoundExpressionReturnedOnce(t *testing.T) {
	ctx := t.Context()
	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)
	s := newSqliteStorage(t)

	// Alert with compound expression that matches multiple search licenses
	compoundAlert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "compound-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT OR Apache-2.0",
		PullRequestNumber:     &pullRequestNumber,
	}

	created, err := s.CreateAlert(ctx, compoundAlert)
	require.NoError(t, err)

	// Search for both licenses that are in the compound expression
	retrievedAlerts, err := s.GetOpenAlertsByLicenses(ctx, []string{"MIT", "Apache-2.0"}, storage.NewRepositoryScope(repositoryID))
	require.NoError(t, err)

	// Should only return the alert once, not twice
	require.Equal(t, 1, len(retrievedAlerts), "compound license alert should only be returned once")
	assert.Equal(t, created.ID, retrievedAlerts[0].ID)
	assert.Equal(t, "MIT OR Apache-2.0", retrievedAlerts[0].SPDXLicenseExpression)
}

func TestGetOpenAlertsByPackage_ReturnsAlertsWithMatchingPackageNameAndEcosystem(t *testing.T) {
	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	testCases := []struct {
		caseName          string
		ecosystem         proto.PackageManager
		packageName       string
		searchEcosystem   proto.PackageManager
		searchPackageName string
		searchStatus      models.AlertStatus
		scope             storage.AlertScope
		alertReturned     bool
	}{
		{
			caseName:          "basic match",
			ecosystem:         proto.PackageManager_PACKAGE_MANAGER_NPM,
			packageName:       "lodash",
			searchEcosystem:   proto.PackageManager_PACKAGE_MANAGER_NPM,
			searchPackageName: "lodash",
			scope:             storage.NewRepositoryScope(repositoryID),
			alertReturned:     true,
		},
		{
			caseName:          "a match at org level with different package manager and status",
			ecosystem:         proto.PackageManager_PACKAGE_MANAGER_PIP,
			packageName:       "requests",
			searchEcosystem:   proto.PackageManager_PACKAGE_MANAGER_PIP,
			searchPackageName: "requests",
			searchStatus:      models.AlertStatusReviewRequested,
			scope:             storage.NewOrganizationScope(organizationID),
			alertReturned:     true,
		},
		{
			caseName:          "wildcard match",
			ecosystem:         proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			packageName:       "github.com/github/github-telemetry-go",
			searchEcosystem:   proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			searchPackageName: "github.com/github/*",
			scope:             storage.NewRepositoryScope(repositoryID),
			alertReturned:     true,
		},
		{
			caseName:          "wildcard match in the middle",
			ecosystem:         proto.PackageManager_PACKAGE_MANAGER_NPM,
			packageName:       "express-server-core",
			searchEcosystem:   proto.PackageManager_PACKAGE_MANAGER_NPM,
			searchPackageName: "express-*-core",
			scope:             storage.NewRepositoryScope(repositoryID),
			alertReturned:     true,
		},
		{
			caseName:          "no match due to different package name",
			ecosystem:         proto.PackageManager_PACKAGE_MANAGER_NPM,
			packageName:       "lodash",
			searchEcosystem:   proto.PackageManager_PACKAGE_MANAGER_NPM,
			searchPackageName: "react",
			scope:             storage.NewRepositoryScope(repositoryID),
			alertReturned:     false,
		},
		{
			caseName:          "no match due to different ecosystem",
			ecosystem:         proto.PackageManager_PACKAGE_MANAGER_NPM,
			packageName:       "lodash",
			searchEcosystem:   proto.PackageManager_PACKAGE_MANAGER_PIP,
			searchPackageName: "lodash",
			scope:             storage.NewRepositoryScope(repositoryID),
			alertReturned:     false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.caseName, func(t *testing.T) {
			s := newSqliteStorage(t)
			ctx := t.Context()
			alert := models.Alert{
				RepositoryID:          repositoryID,
				OrganizationID:        organizationID,
				EnterpriseID:          &enterpriseID,
				ManifestName:          "package.json",
				ManifestLineNumber:    1,
				PackageEcosystem:      tc.ecosystem,
				PackageName:           tc.packageName,
				PackageVersion:        "1.0.0",
				SPDXLicenseExpression: "MIT",
				PullRequestNumber:     &pullRequestNumber,
			}

			_, err := s.CreateAlert(ctx, alert)
			require.NoError(t, err)

			retrievedAlerts, err := s.GetOpenAlertsByPackage(ctx, tc.searchEcosystem, tc.searchPackageName, tc.scope)
			require.NoError(t, err)
			assert.Equal(t, tc.alertReturned, len(retrievedAlerts) == 1, "expected alerts retrieved to be %v", tc.alertReturned)
		})
	}
}

func TestGetOpenAlertsByPackage_ReturnsAlertsInNonClosedStatus(t *testing.T) {
	ctx := t.Context()
	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	openStatuses := []models.AlertStatus{models.AlertStatusOpen, models.AlertStatusReviewRequested, models.AlertStatusReviewDenied}
	statuses := slices.Clone(openStatuses)
	statuses = append(statuses, models.AlertStatusClosed)
	s := newSqliteStorage(t)
	for _, status := range statuses {
		alert := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        organizationID,
			EnterpriseID:          &enterpriseID,
			ManifestName:          "package.json",
			ManifestLineNumber:    1,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "test-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "MIT",
			Status:                status,
			PullRequestNumber:     &pullRequestNumber,
		}

		_, err := s.CreateAlert(ctx, alert)
		require.NoError(t, err)
	}

	retrievedAlerts, err := s.GetOpenAlertsByPackage(ctx, proto.PackageManager_PACKAGE_MANAGER_NPM, "test-package", storage.NewRepositoryScope(repositoryID))
	require.NoError(t, err)

	assert.Equal(t, 3, len(retrievedAlerts), "expected 3 alerts to be retrieved")
	returnedStatuses := make([]models.AlertStatus, 0, len(retrievedAlerts))
	for _, alert := range retrievedAlerts {
		returnedStatuses = append(returnedStatuses, alert.Status)
	}
	assert.ElementsMatch(t, openStatuses, returnedStatuses, "expected open statuses to be present got %v", returnedStatuses)
	assert.NotContains(t, returnedStatuses, models.AlertStatusClosed, "expected closed status to not be present got %v", returnedStatuses)
}

type failingSequenceGenerator struct{}

func (f *failingSequenceGenerator) Next(ctx context.Context, repositoryID uint64) (uint32, error) {
	return 0, errors.New("sequence generator failure")
}

func TestCreateAlert_ReturnsErrorWithSequenceFailure(t *testing.T) {
	r := require.New(t)

	// Create storage with failing sequence generator
	db, err := sqlite.New(":memory:")
	r.NoError(err)

	failingSeqGen := &failingSequenceGenerator{}
	s, err := storage.NewStorage(db, nil, nil, nil, failingSeqGen, nil, nil)
	r.NoError(err)

	_, err = s.CreateAlert(t.Context(), models.Alert{})
	r.Error(err)
	r.Contains(err.Error(), "sequence generator failure")
}

type duplicateSequenceGenerator struct{}

func (f *duplicateSequenceGenerator) Next(ctx context.Context, repositoryID uint64) (uint32, error) {
	return 1, nil
}

func TestCreateAlert_ReturnsErrorWithDuplicateFailure(t *testing.T) {
	r := require.New(t)

	// Create storage with duplicate sequence generator
	db, err := sqlite.New(":memory:")
	r.NoError(err)

	duplicateSeqGen := &duplicateSequenceGenerator{}
	s, err := storage.NewStorage(db, nil, nil, nil, duplicateSeqGen, nil, nil)
	r.NoError(err)

	repoID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	newAlert := models.Alert{
		RepositoryID:          repoID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    42,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "4.17.21",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	_, err = s.CreateAlert(t.Context(), newAlert)
	r.NoError(err)
	_, err = s.CreateAlert(t.Context(), newAlert)
	r.ErrorContains(err, "UNIQUE constraint failed")
}

func TestGetOpenAlerts_ReturnsGroupedAlertsByPackageKey(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	repositoryID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(1)

	// Create first alert for lodash@4.17.21 with MIT license
	alert1 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "4.17.21",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
		Status:                models.AlertStatusOpen,
	}

	// Create second alert for the same package (should be grouped together)
	alert2 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package-lock.json",
		ManifestLineNumber:    10,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "4.17.21",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
		Status:                models.AlertStatusOpen,
	}

	// Create third alert for different package
	alert3 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    5,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "react",
		PackageVersion:        "18.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
		Status:                models.AlertStatusReviewRequested,
	}

	// Create alerts
	_, err := s.CreateAlert(ctx, alert1)
	r.NoError(err)
	_, err = s.CreateAlert(ctx, alert2)
	r.NoError(err)
	_, err = s.CreateAlert(ctx, alert3)
	r.NoError(err)

	// Get open alerts
	openAlertsMap, err := s.GetOpenAlerts(ctx, repositoryID, &pullRequestNumber)
	r.NoError(err)
	r.NotNil(openAlertsMap)

	// Should have 2 groups (lodash and react)
	r.Equal(2, len(openAlertsMap))

	// Check lodash group has 2 alerts
	lodashKey := storage.CreatePackageKey("npm", "lodash", "MIT")
	lodashAlerts, exists := openAlertsMap[lodashKey]
	r.True(exists)
	r.Equal(2, len(lodashAlerts))

	// Check react group has 1 alert
	reactKey := storage.CreatePackageKey("npm", "react", "MIT")
	reactAlerts, exists := openAlertsMap[reactKey]
	r.True(exists)
	r.Equal(1, len(reactAlerts))
}

func TestGetOpenAlerts_ReturnsEmptyMapWhenNoOpenAlerts(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(1)

	// Get open alerts for repository with no alerts
	openAlertsMap, err := s.GetOpenAlerts(ctx, repositoryID, &pullRequestNumber)
	r.NoError(err)
	r.NotNil(openAlertsMap)
	r.Equal(0, len(openAlertsMap))
}

func TestGetOpenAlerts_FiltersClosedAlerts(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	repositoryID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(1)

	// Create an alert
	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "4.17.21",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	_, err := s.CreateAlert(ctx, alert)
	r.NoError(err)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, 1)
	r.NoError(err)

	// Close the alert
	tx := s.NewTransactor(ctx)
	retrievedAlert.Resolution = models.AlertResolutionExceptionAdded
	retrievedAlert.Status = models.AlertStatusClosed
	tx.AddStep(storage.NewCloseAlertStep(retrievedAlert))
	err = tx.Execute()
	r.NoError(err)

	openAlertsMap, err := s.GetOpenAlerts(ctx, repositoryID, &pullRequestNumber)
	r.NoError(err)
	r.NotNil(openAlertsMap)
	r.Equal(0, len(openAlertsMap))
}

func TestGetOpenAlerts_FiltersByPullRequestNumber(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	repositoryID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	pullRequestNumber1 := uint32(1)
	pullRequestNumber2 := uint32(2)

	// Create alert for PR 1
	alert1 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "4.17.21",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber1,
	}

	// Create alert for PR 2
	alert2 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "react",
		PackageVersion:        "18.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber2,
	}

	_, err := s.CreateAlert(ctx, alert1)
	r.NoError(err)
	_, err = s.CreateAlert(ctx, alert2)
	r.NoError(err)

	// Get open alerts for PR 1 - should only return lodash alert
	openAlertsMap, err := s.GetOpenAlerts(ctx, repositoryID, &pullRequestNumber1)
	r.NoError(err)
	r.NotNil(openAlertsMap)
	r.Equal(1, len(openAlertsMap))

	lodashKey := storage.CreatePackageKey("npm", "lodash", "MIT")
	_, exists := openAlertsMap[lodashKey]
	r.True(exists)

	// Get open alerts for PR 2 - should only return react alert
	openAlertsMap, err = s.GetOpenAlerts(ctx, repositoryID, &pullRequestNumber2)
	r.NoError(err)
	r.NotNil(openAlertsMap)
	r.Equal(1, len(openAlertsMap))

	reactKey := storage.CreatePackageKey("npm", "react", "MIT")
	_, exists = openAlertsMap[reactKey]
	r.True(exists)
}

func TestGetAlertsForOrgOrEnterprise(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	orgID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)
	alerts := []*models.Alert{}
	for i := range 5 {
		alert := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &enterpriseID,
			Status:                models.AlertStatusReviewRequested,
			ManifestName:          "package.json",
			ManifestLineNumber:    1,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "jest",
			PackageVersion:        fmt.Sprintf("1.0.%d", i),
			SPDXLicenseExpression: "MIT",
			PullRequestNumber:     &pullRequestNumber,
		}
		alerts = append(alerts, &alert)
		_, err := s.CreateAlert(ctx, alert)
		require.NoError(t, err)
	}
	alertWrongOrg := models.Alert{
		RepositoryID:          repositoryID + 1,
		OrganizationID:        orgID + 1, // different org
		EnterpriseID:          &enterpriseID,
		Status:                models.AlertStatusReviewRequested,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "this better not get returned",
		PackageVersion:        "99.99.99",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}
	_, err := s.CreateAlert(ctx, alertWrongOrg)
	require.NoError(t, err)
	alertWrongStatus := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "this better not get returned",
		PackageVersion:        "99.99.99",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}
	_, err = s.CreateAlert(ctx, alertWrongStatus)
	require.NoError(t, err)
	retrievedAlerts, err := s.GetReviewableAlertsForOrgOrEnterprise(ctx, orgID, 0)
	r.NoError(err)
	r.Len(retrievedAlerts, len(alerts))
	// Check that all created alerts are in the retrieved alerts
	for _, createdAlert := range alerts {
		found := false
		for _, retrievedAlert := range retrievedAlerts {
			if createdAlert.PackageVersion == retrievedAlert.PackageVersion &&
				createdAlert.PackageName == retrievedAlert.PackageName {
				found = true
				break
			}
		}
		r.True(found, "Created alert with package version %s not found in retrieved alerts", createdAlert.PackageVersion)
	}
	// Ensure the non-matching alert is not in the results
	for _, retrievedAlert := range retrievedAlerts {
		r.NotEqual("this better not get returned", retrievedAlert.PackageName)
	}
}

func TestGetAlertsForPullRequest_ReturnsAllAlerts(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(42)

	// Create multiple alerts for the same PR
	alert1 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "4.17.21",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	alert2 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "requirements.txt",
		ManifestLineNumber:    5,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_PIP,
		PackageName:           "requests",
		PackageVersion:        "2.28.0",
		SPDXLicenseExpression: "Apache-2.0",
		PullRequestNumber:     &pullRequestNumber,
	}

	created1, err := s.CreateAlert(ctx, alert1)
	r.NoError(err)
	created2, err := s.CreateAlert(ctx, alert2)
	r.NoError(err)

	// Create an alert for a different PR (should not be returned)
	differentPR := uint32(99)
	alert3 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "go.mod",
		ManifestLineNumber:    10,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_GOMOD,
		PackageName:           "github.com/stretchr/testify",
		PackageVersion:        "1.8.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &differentPR,
	}
	_, err = s.CreateAlert(ctx, alert3)
	r.NoError(err)

	// Get alerts for the specific PR
	alerts, err := s.GetAlertsForPullRequest(ctx, repositoryID, pullRequestNumber)
	r.NoError(err)
	r.Len(alerts, 2, "should return exactly 2 alerts for the PR")

	// Verify the returned alerts match what we created
	alertIDs := []uint64{alerts[0].ID, alerts[1].ID}
	r.Contains(alertIDs, created1.ID)
	r.Contains(alertIDs, created2.ID)
}

func TestGetAlertsForPullRequest_ReturnsEmptyForNonExistentPR(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(999)

	alerts, err := s.GetAlertsForPullRequest(ctx, repositoryID, pullRequestNumber)
	r.NoError(err)
	r.Empty(alerts, "should return empty slice for non-existent PR")
}

func TestGetAlertsForPullRequest_ReturnsAlertsWithAllStatuses(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(50)

	// Create alerts with different statuses
	openAlert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "open-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
		Status:                models.AlertStatusOpen,
	}

	closedAlert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    2,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "closed-package",
		PackageVersion:        "2.0.0",
		SPDXLicenseExpression: "Apache-2.0",
		PullRequestNumber:     &pullRequestNumber,
		Status:                models.AlertStatusClosed,
		Resolution:            models.AlertResolutionExceptionAdded,
	}

	_, err := s.CreateAlert(ctx, openAlert)
	r.NoError(err)
	_, err = s.CreateAlert(ctx, closedAlert)
	r.NoError(err)

	// Get all alerts for the PR (including closed ones)
	alerts, err := s.GetAlertsForPullRequest(ctx, repositoryID, pullRequestNumber)
	r.NoError(err)
	r.Len(alerts, 2, "should return alerts with all statuses")

	// Verify we have both open and closed alerts
	statuses := []models.AlertStatus{alerts[0].Status, alerts[1].Status}
	r.Contains(statuses, models.AlertStatusOpen)
	r.Contains(statuses, models.AlertStatusClosed)
}

func TestGetAlerts_WithMultipleOptions(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(42)

	// Create test alerts with different attributes
	testAlerts := []models.Alert{
		{
			RepositoryID:          repositoryID,
			OrganizationID:        organizationID,
			EnterpriseID:          &enterpriseID,
			ManifestName:          "package.json",
			ManifestLineNumber:    1,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "lodash",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "MIT",
			Status:                models.AlertStatusOpen,
			PullRequestNumber:     &pullRequestNumber,
		},
		{
			RepositoryID:          repositoryID,
			OrganizationID:        organizationID,
			EnterpriseID:          &enterpriseID,
			ManifestName:          "package.json",
			ManifestLineNumber:    2,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "express",
			PackageVersion:        "2.0.0",
			SPDXLicenseExpression: "Apache-2.0",
			Status:                models.AlertStatusReviewRequested,
			PullRequestNumber:     &pullRequestNumber,
		},
		{
			RepositoryID:          repositoryID,
			OrganizationID:        organizationID,
			EnterpriseID:          &enterpriseID,
			ManifestName:          "go.mod",
			ManifestLineNumber:    3,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			PackageName:           "github.com/pkg/errors",
			PackageVersion:        "3.0.0",
			SPDXLicenseExpression: "BSD-2-Clause",
			Status:                models.AlertStatusClosed,
			PullRequestNumber:     &pullRequestNumber,
		},
	}

	for _, alert := range testAlerts {
		_, err := s.CreateAlert(ctx, alert)
		r.NoError(err)
	}

	t.Run("Filter by repository and status", func(t *testing.T) {
		alerts, err := s.GetAlerts(ctx,
			storage.WithRepositoryID(repositoryID),
			storage.WithStatuses(models.AlertStatusOpen))
		r.NoError(err)
		r.Len(alerts, 1)
		r.Equal("lodash", alerts[0].PackageName)
		r.Equal(models.AlertStatusOpen, alerts[0].Status)
	})

	t.Run("Filter by multiple statuses", func(t *testing.T) {
		alerts, err := s.GetAlerts(ctx,
			storage.WithRepositoryID(repositoryID),
			storage.WithStatuses(models.AlertStatusOpen, models.AlertStatusReviewRequested))
		r.NoError(err)
		r.Len(alerts, 2)
	})

	t.Run("Filter by repository and pull request", func(t *testing.T) {
		alerts, err := s.GetAlerts(ctx,
			storage.WithRepositoryID(repositoryID),
			storage.WithPullRequest(pullRequestNumber),
			storage.WithStatuses(models.AlertStatusOpen, models.AlertStatusReviewRequested, models.AlertStatusClosed))
		r.NoError(err)
		r.Len(alerts, 3)
	})

	t.Run("Filter by package", func(t *testing.T) {
		alerts, err := s.GetAlerts(ctx,
			storage.WithScope(storage.NewRepositoryScope(repositoryID)),
			storage.WithPackage(proto.PackageManager_PACKAGE_MANAGER_NPM, "lodash"))
		r.NoError(err)
		r.Len(alerts, 1)
		r.Equal("lodash", alerts[0].PackageName)
	})

	t.Run("Filter by package with wildcard", func(t *testing.T) {
		alerts, err := s.GetAlerts(ctx,
			storage.WithScope(storage.NewRepositoryScope(repositoryID)),
			storage.WithPackage(proto.PackageManager_PACKAGE_MANAGER_NPM, "*press"))
		r.NoError(err)
		r.Len(alerts, 1)
		r.Equal("express", alerts[0].PackageName)
	})

	t.Run("Filter by licenses", func(t *testing.T) {
		alerts, err := s.GetAlerts(ctx,
			storage.WithScope(storage.NewRepositoryScope(repositoryID)),
			storage.WithLicenses([]string{"MIT", "Apache-2.0"}))
		r.NoError(err)
		r.Len(alerts, 2)
	})

	t.Run("Filter by organization", func(t *testing.T) {
		alerts, err := s.GetAlerts(ctx,
			storage.WithOrganizationID(organizationID),
			storage.WithStatuses(models.AlertStatusOpen, models.AlertStatusReviewRequested, models.AlertStatusClosed))
		r.NoError(err)
		r.Len(alerts, 3)
	})

	t.Run("Default excludes closed alerts", func(t *testing.T) {
		alerts, err := s.GetAlerts(ctx,
			storage.WithRepositoryID(repositoryID))
		r.NoError(err)
		r.Len(alerts, 2)
		for _, alert := range alerts {
			r.NotEqual(models.AlertStatusClosed, alert.Status)
		}
	})
}

func TestGetAlerts_CombinesLicenseAndPackageFilters(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(1)

	// Create alerts with different combinations
	testAlerts := []models.Alert{
		{
			RepositoryID:          repositoryID,
			OrganizationID:        organizationID,
			EnterpriseID:          &enterpriseID,
			ManifestName:          "package.json",
			ManifestLineNumber:    1,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "test-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "MIT",
			Status:                models.AlertStatusOpen,
			PullRequestNumber:     &pullRequestNumber,
		},
		{
			RepositoryID:          repositoryID,
			OrganizationID:        organizationID,
			EnterpriseID:          &enterpriseID,
			ManifestName:          "package.json",
			ManifestLineNumber:    2,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "other-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "MIT",
			Status:                models.AlertStatusOpen,
			PullRequestNumber:     &pullRequestNumber,
		},
		{
			RepositoryID:          repositoryID,
			OrganizationID:        organizationID,
			EnterpriseID:          &enterpriseID,
			ManifestName:          "package.json",
			ManifestLineNumber:    3,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "test-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "Apache-2.0",
			Status:                models.AlertStatusOpen,
			PullRequestNumber:     &pullRequestNumber,
		},
	}

	for _, alert := range testAlerts {
		_, err := s.CreateAlert(ctx, alert)
		r.NoError(err)
	}

	// Filter by both package name and license
	alerts, err := s.GetAlerts(ctx,
		storage.WithScope(storage.NewRepositoryScope(repositoryID)),
		storage.WithPackage(proto.PackageManager_PACKAGE_MANAGER_NPM, "test-package"),
		storage.WithLicenses([]string{"MIT"}))
	r.NoError(err)
	r.Len(alerts, 1)
	r.Equal("test-package", alerts[0].PackageName)
	r.Equal("MIT", alerts[0].SPDXLicenseExpression)
}

func TestGetAlerts_EnterpriseScope(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()

	enterpriseID1 := testhelpers.RandomIDForDatabase()
	enterpriseID2 := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(1)

	// Create alerts for different enterprises
	alert1 := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        organizationID,
		EnterpriseID:          &enterpriseID1,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "test-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		Status:                models.AlertStatusOpen,
		PullRequestNumber:     &pullRequestNumber,
	}
	alert2 := alert1
	alert2.EnterpriseID = &enterpriseID2

	_, err := s.CreateAlert(ctx, alert1)
	r.NoError(err)
	_, err = s.CreateAlert(ctx, alert2)
	r.NoError(err)

	// Filter by enterprise
	alerts, err := s.GetAlerts(ctx,
		storage.WithEnterpriseID(enterpriseID1))
	r.NoError(err)
	r.Len(alerts, 1)
	r.Equal(&enterpriseID1, alerts[0].EnterpriseID)
}

func TestCreateAlert_SavesPackageRepoNWO(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "4.17.21",
		SPDXLicenseExpression: "MIT",
		PackageRepoNWO:        "lodash/lodash",
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal("lodash/lodash", createdAlert.PackageRepoNWO)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, createdAlert.Number)
	r.NoError(err)
	r.NotNil(retrievedAlert)
	r.Equal("lodash/lodash", retrievedAlert.PackageRepoNWO)
}

func TestCreateAlert_SavesEmptyPackageRepoNWO(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "unknown-pkg",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PackageRepoNWO:        "",
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal("", createdAlert.PackageRepoNWO)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, createdAlert.Number)
	r.NoError(err)
	r.NotNil(retrievedAlert)
	r.Equal("", retrievedAlert.PackageRepoNWO)
}

func TestTransitionAlertStep_ChecksForConcurrentWriters(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	enterpriseID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)

	createdAlert.Status = models.AlertStatusReviewDenied
	tx := s.NewTransactor(ctx)
	tx.AddStep(storage.NewTransitionAlertStep(createdAlert, models.AlertStatusReviewRequested))
	err = tx.Execute()
	r.ErrorIs(err, storage.ErrConcurrentStatusChange)
}
