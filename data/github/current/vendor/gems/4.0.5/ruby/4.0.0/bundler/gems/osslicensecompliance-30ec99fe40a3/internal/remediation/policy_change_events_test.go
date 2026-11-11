package remediation

import (
	"testing"

	"github.com/github/github-telemetry-go/log"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	proto_v0 "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/require"
)

func TestPublishEventsForAffectedPRs_NoCheckJob(t *testing.T) {
	ctx := t.Context()
	logger := log.NewNullLogger()

	// Create test storage
	store, err := storage.NewNullStorage("", logger)
	require.NoError(t, err)
	defer func() { _ = store.Close() }()

	// Create test publisher that captures events
	tp := testpublisher.NewTestPublisher(t)

	// Create application
	app := &application.Application{
		Subsystems: &application.Subsystems{
			Storage:        store,
			EventPublisher: tp.Publisher,
		},
		Logger: logger,
	}

	// Create an alert without a check job
	repoID := testhelpers.RandomIDForDatabase()
	orgID := testhelpers.RandomIDForDatabase()
	prNumber := uint32(1)

	alert := models.Alert{
		RepositoryID:          repoID,
		OrganizationID:        orgID,
		ManifestName:          "package.json",
		PackageEcosystem:      proto_v0.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "test-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &prNumber,
		Status:                models.AlertStatusOpen,
	}
	createdAlert, err := store.CreateAlert(ctx, alert)
	require.NoError(t, err)

	closedAlerts := []*models.Alert{createdAlert}

	// Should not fail even though check job doesn't exist
	err = PublishEventsForAffectedPRs(ctx, app, closedAlerts)
	require.NoError(t, err)

	// Verify no event was published since there's no check job
	tp.AssertNoMessagePublished(t)
}

func TestPublishEventsForAffectedPRs_AlertsWithoutPRNumber(t *testing.T) {
	ctx := t.Context()
	logger := log.NewNullLogger()

	// Create test storage
	store, err := storage.NewNullStorage("", logger)
	require.NoError(t, err)
	defer func() { _ = store.Close() }()

	// Create test publisher that captures events
	tp := testpublisher.NewTestPublisher(t)

	// Create application
	app := &application.Application{
		Subsystems: &application.Subsystems{
			Storage:        store,
			EventPublisher: tp.Publisher,
		},
		Logger: logger,
	}

	// Create alerts without PR numbers (shouldn't happen in practice but should be handled)
	repoID := testhelpers.RandomIDForDatabase()
	orgID := testhelpers.RandomIDForDatabase()

	alert := models.Alert{
		RepositoryID:          repoID,
		OrganizationID:        orgID,
		ManifestName:          "package.json",
		PackageEcosystem:      proto_v0.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "test-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     nil, // No PR number
		Status:                models.AlertStatusOpen,
	}
	createdAlert, err := store.CreateAlert(ctx, alert)
	require.NoError(t, err)

	closedAlerts := []*models.Alert{createdAlert}

	// Should not fail or try to publish events for alerts without PR numbers
	err = PublishEventsForAffectedPRs(ctx, app, closedAlerts)
	require.NoError(t, err)

	// Verify no event was published since the alert has no PR number
	tp.AssertNoMessagePublished(t)
}

func TestPublishEventForPR_DirectCall(t *testing.T) {
	ctx := t.Context()
	logger := log.Named("test")

	// Create test storage
	store, err := storage.NewNullStorage("", logger)
	require.NoError(t, err)
	defer func() { _ = store.Close() }()

	// Create test publisher that captures events
	tp := testpublisher.NewTestPublisher(t)

	// Create application
	app := &application.Application{
		Subsystems: &application.Subsystems{
			Storage:        store,
			EventPublisher: tp.Publisher,
		},
		Logger: logger,
	}

	// Create test data
	repoID := testhelpers.RandomIDForDatabase()
	orgID := testhelpers.RandomIDForDatabase()
	entID := testhelpers.RandomIDForDatabase()
	prNumber := uint32(1)
	prID := uint64(1001)

	// Create policies (required for GetCompletePolicy)
	_, err = store.UpsertRepositoryPolicy(ctx, repoID, func(policy *proto_v0.RepositoryPolicy) (*proto_v0.RepositoryPolicy, error) {
		return &proto_v0.RepositoryPolicy{}, nil
	})
	require.NoError(t, err)

	// Create check job
	checkJob := models.CheckJob{
		RepositoryID:      repoID,
		OrganizationID:    orgID,
		EnterpriseID:      &entID,
		PullRequestID:     prID,
		PullRequestNumber: prNumber,
		CommitSHA:         "abc123",
		BaseSHA:           "def456",
	}
	_, err = store.CreateCheckJob(ctx, checkJob)
	require.NoError(t, err)

	// Call publishEventForPR directly
	err = publishEventForPR(ctx, app, repoID, prNumber)
	require.NoError(t, err)

	// Verify event was published
	expectedProto := &dependencygraphv1.PullRequestLicenseCheckComplete{
		PullRequestId:       int64(prID),     // #nosec G115
		PullRequestNumber:   int32(prNumber), // #nosec G115
		CommitSha:           "abc123",
		BaseSha:             "def456",
		RepositoryId:        int64(repoID), // #nosec G115
		RemediationGuidance: "",
	}
	tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckComplete", expectedProto)
}
