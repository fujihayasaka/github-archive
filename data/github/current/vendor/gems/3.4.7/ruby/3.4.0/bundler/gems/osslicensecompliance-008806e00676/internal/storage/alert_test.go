package storage_test

import (
	"context"
	"encoding/json"
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
	r.Equal(models.Open, retrievedAlert.Status)
	r.Nil(retrievedAlert.Resolution) // default is nil
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
	resolution := models.PolicyChanged
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		Resolution:            &resolution, // set resolution
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

	r.Equal(resolution, *retrievedAlert.Resolution)
	r.EqualExportedValues(createdAlert, retrievedAlert, "returned alert should match response of GetAlert")
}

func TestGetOpenAlertsByLicenses_ReturnsAlertsInNonClosedStatus(t *testing.T) {
	ctx := t.Context()
	enterpriseID := testhelpers.RandomIDForDatabase()
	organizationID := testhelpers.RandomIDForDatabase()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	openStatuses := []models.AlertStatus{models.Open, models.ReviewRequested, models.ReviewDenied}
	statuses := slices.Clone(openStatuses)
	statuses = append(statuses, models.Closed)
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
	assert.NotContains(t, returnedStatuses, models.Closed, "expected closed status to not be present got %v", returnedStatuses)
}

func TestGetOpenAlertsByLicenses_MatchesLicenseStrings(t *testing.T) {
	ctx := t.Context()
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

			_, err := s.CreateAlert(ctx, alert)
			require.NoError(t, err)
			retrievedAlerts, err := s.GetOpenAlertsByLicenses(ctx, []string{tc.searchLicense}, storage.NewRepositoryScope(repositoryID))
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
			searchStatus:      models.ReviewRequested,
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

	openStatuses := []models.AlertStatus{models.Open, models.ReviewRequested, models.ReviewDenied}
	statuses := slices.Clone(openStatuses)
	statuses = append(statuses, models.Closed)
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
	assert.NotContains(t, returnedStatuses, models.Closed, "expected closed status to not be present got %v", returnedStatuses)
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

func TestUpdateAlertStatusWithEvent_OpenToReviewRequestedToDenied(t *testing.T) {
	s := newSqliteStorage(t)
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
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
	require.Equal(t, models.Open, alert.Status)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)

	// Open -> ReviewRequested
	err = s.UpdateAlertStatusWithEvent(ctx, retrievedAlert, models.ReviewRequested, models.EventReviewRequested, json.RawMessage("{}"), nil)
	require.NoError(t, err)

	retrievedAlert, err = s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	require.Equal(t, models.ReviewRequested, retrievedAlert.Status)

	// ReviewRequested -> ReviewDenied
	err = s.UpdateAlertStatusWithEvent(ctx, retrievedAlert, models.ReviewDenied, models.EventReviewDenied, json.RawMessage("{}"), nil)
	require.NoError(t, err)

	retrievedAlert, err = s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	require.Equal(t, models.ReviewDenied, retrievedAlert.Status)

	// Verify alert events
	events, err := s.GetAlertEvents(ctx, retrievedAlert.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)

	require.Equal(t, models.EventReviewRequested, events[0].EventType)
	require.Equal(t, models.EventReviewDenied, events[1].EventType)
}

func TestUpdateAlertStatusWithEvent_ClosedToReviewRequested_DoesNotUpdate(t *testing.T) {
	s := newSqliteStorage(t)
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
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
	require.Equal(t, models.Open, alert.Status)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)

	// Move to Closed
	err = s.CloseAlertWithEvent(ctx, retrievedAlert, nil, models.ExceptionAdded, nil)
	require.NoError(t, err)
	retrievedAlert, err = s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	require.Equal(t, models.Closed, retrievedAlert.Status)

	// Invalid transition: Closed to ReviewRequested
	err = s.UpdateAlertStatusWithEvent(ctx, retrievedAlert, models.ReviewRequested, models.EventReviewRequested, json.RawMessage("{}"), nil)
	require.ErrorIs(t, err, storage.ErrStatusChangeNotAllowed)
	retrievedAlert, err = s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	require.Equal(t, models.Closed, retrievedAlert.Status) // still Closed

	// No new events created
	events, err := s.GetAlertEvents(ctx, retrievedAlert.ID)
	require.NoError(t, err)
	require.Len(t, events, 1)
	require.Equal(t, models.EventClosed, events[0].EventType)
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
		Status:                models.Open,
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
		Status:                models.Open,
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
		Status:                models.ReviewRequested,
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
	err = s.CloseAlertWithEvent(ctx, retrievedAlert, nil, models.ExceptionAdded, nil)
	r.NoError(err)

	// Get open alerts - should be empty since we closed the only alert
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
	for i := 0; i < 5; i++ {
		alert := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &enterpriseID,
			Status:                models.ReviewRequested,
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
		Status:                models.ReviewRequested,
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

func TestCloseAlertWithEvent_WithNilEventBody(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()
	userID := testhelpers.RandomIDForDatabase()

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "test-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal(models.Open, createdAlert.Status)

	err = s.CloseAlertWithEvent(ctx, createdAlert, &userID, models.PolicyChanged, nil)
	r.NoError(err)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, createdAlert.Number)
	r.NoError(err)
	r.Equal(models.Closed, retrievedAlert.Status)
	r.NotNil(retrievedAlert.Resolution)
	r.Equal(models.PolicyChanged, *retrievedAlert.Resolution)

	events, err := s.GetAlertEvents(ctx, createdAlert.ID)
	r.NoError(err)
	r.Len(events, 1)
	r.Equal(models.EventClosed, events[0].EventType)
	r.Equal(&userID, events[0].UserID)
	r.JSONEq("{}", string(events[0].EventBody))
}

func TestCloseAlertWithEvent_WithStructuredEventBody(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()
	enterpriseID := testhelpers.RandomIDForDatabase()
	userID := testhelpers.RandomIDForDatabase()

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		EnterpriseID:          &enterpriseID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "test-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal(models.Open, createdAlert.Status)

	eventBody := models.LicensesAddedEventBody{
		Licenses: []string{"MIT", "Apache-2.0"},
		Level:    "repository",
	}

	err = s.CloseAlertWithEvent(ctx, createdAlert, &userID, models.PolicyChanged, eventBody)
	r.NoError(err)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, createdAlert.Number)
	r.NoError(err)
	r.Equal(models.Closed, retrievedAlert.Status)
	r.NotNil(retrievedAlert.Resolution)
	r.Equal(models.PolicyChanged, *retrievedAlert.Resolution)

	events, err := s.GetAlertEvents(ctx, createdAlert.ID)
	r.NoError(err)
	r.Len(events, 1)
	r.Equal(models.EventClosed, events[0].EventType)
	r.Equal(&userID, events[0].UserID)

	var storedBody models.LicensesAddedEventBody
	err = json.Unmarshal(events[0].EventBody, &storedBody)
	r.NoError(err)
	r.Equal(eventBody.Licenses, storedBody.Licenses)
	r.Equal(eventBody.Level, storedBody.Level)
}

type failingSequenceGenerator struct{}

func (f *failingSequenceGenerator) Next(ctx context.Context, repositoryID uint64) (uint32, error) {
	return 0, errors.New("sequence generator failure")
}
