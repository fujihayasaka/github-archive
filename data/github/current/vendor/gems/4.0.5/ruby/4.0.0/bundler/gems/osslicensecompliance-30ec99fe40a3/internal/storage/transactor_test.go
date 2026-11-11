package storage_test

import (
	"context"
	"errors"
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/require"
)

func TestTransactor_RollsBackOnHookFailure(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()

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

	hook := func(ctx context.Context) error {
		return errors.New("hook failed")
	}

	tx := s.NewTransactor(ctx)
	createdAlert.Resolution = models.AlertResolutionLicensesAdded
	tx.AddStep(storage.NewCloseAlertStep(createdAlert))
	tx.AddPostUpdateHook(hook)

	err = tx.Execute()
	r.Error(err)
	r.Contains(err.Error(), "hook failed")

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, createdAlert.Number)
	r.NoError(err)
	r.Equal(models.AlertStatusOpen, retrievedAlert.Status, "Alert should still be open after rollback")
}

func TestTransactor_CallsHookFunc(t *testing.T) {
	r := require.New(t)
	s := newSqliteStorage(t)
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()

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

	hookCalled := false
	hook := func(ctx context.Context) error {
		hookCalled = true
		return nil
	}

	tx := s.NewTransactor(ctx)
	createdAlert.Status = models.AlertStatusReviewRequested
	tx.AddStep(storage.NewTransitionAlertStep(createdAlert, models.AlertStatusOpen))
	tx.AddPostUpdateHook(hook)

	err = tx.Execute()
	r.NoError(err)
	r.True(hookCalled, "hook should be called")

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, createdAlert.Number)
	r.NoError(err)
	r.Equal(models.AlertStatusReviewRequested, retrievedAlert.Status)
}
