// Description: This adds commands to be used to setup codespaces
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/osslicensecompliance/internal/command"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

func main() {
	err := run()
	if err != nil {
		log.Fatalf("failed to run service: %v", err)
	}
}

const minimumArgs = 2

func run() error {
	if len(os.Args) < minimumArgs {
		return errors.New("usage: codespace-cli <command> [additional options]\n" + command.ListCommands(allCommands))
	}

	return command.DispatchCommand(os.Args[1], allCommands)
}

var allCommands = []command.Command{
	{Name: "seed_alerts", Desc: "Seeds alerts and alert events for testing (non-production only)", Execute: seedAlerts},
}

type seedContext struct {
	store      *storage.Storage
	ctx        context.Context
	userID     uint64
	prNumber   uint32
	repoID     uint64
	orgID      uint64
	businessID uint64
}

func seedAlerts(c *command.Command) error {
	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		return err
	}

	logger := telemetryProvider.Logger.Named("codespace-cli")

	store, err := storage.NewNullStorage("./olc_sqlite.db", logger)
	if err != nil {
		return err
	}
	defer func() {
		err := store.Close()
		if err != nil {
			logger.WithError(err).Error("failed to close storage")
		}
	}()

	sc := seedContext{
		store:      store,
		ctx:        context.Background(),
		userID:     uint64(2), // monalisa
		prNumber:   uint32(1), // create PR #1 in github/public-server; all alerts will be associated with this PR
		repoID:     uint64(3), // public-server
		orgID:      uint64(6), // github
		businessID: uint64(1), // GitHub, Inc
	}

	err = sc.seedAlert1Open()
	if err != nil {
		return err
	}
	err = sc.seedAlert2ReviewRequested()
	if err != nil {
		return err
	}
	err = sc.seedAlert3LicenseAdded()
	if err != nil {
		return err
	}
	err = sc.seedAlert4PackageException()
	if err != nil {
		return err
	}
	err = sc.seedAlert5ClosedBySideEffect()
	if err != nil {
		return err
	}
	err = sc.seedAlert6ExpiredReview()
	if err != nil {
		return err
	}
	err = sc.seedAlert7AllEventTypes()
	if err != nil {
		return err
	}

	fmt.Println("\n✓ Successfully seeded 7 alerts with realistic event workflows!")
	fmt.Println("\nTo view the alerts, you need to create PR #1 in the github/public-server repository.  You do not need any specific changes in the PR, but it does need to be PR #1.")
	return nil
}

func (sc *seedContext) seedAlert1Open() error {
	fmt.Println("Alert 1: Creating open alert with no events...")
	alert := models.Alert{
		Status:                models.AlertStatusOpen,
		RepositoryID:          sc.repoID,
		OrganizationID:        sc.orgID,
		EnterpriseID:          &sc.businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    23,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "express",
		PackageVersion:        "4.18.0",
		SPDXLicenseExpression: "GPL-2.0",
		PullRequestNumber:     &sc.prNumber,
		PackageRepoNWO:        "expressjs/express",
	}
	created, err := sc.store.CreateAlert(sc.ctx, alert)
	if err != nil {
		return fmt.Errorf("failed to create alert 1: %w", err)
	}
	sc.printAlertCreated(created, &alert, "no events")
	return nil
}

func (sc *seedContext) seedAlert2ReviewRequested() error {
	fmt.Println("\nAlert 2: Creating review requested alert...")
	alert := models.Alert{
		Status:                models.AlertStatusReviewRequested,
		RepositoryID:          sc.repoID,
		OrganizationID:        sc.orgID,
		EnterpriseID:          &sc.businessID,
		ManifestName:          "Gemfile.lock",
		ManifestLineNumber:    15,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
		PackageName:           "rails",
		PackageVersion:        "7.0.0",
		SPDXLicenseExpression: "AGPL-3.0",
		PullRequestNumber:     &sc.prNumber,
		PackageRepoNWO:        "rails/rails",
	}
	created, err := sc.store.CreateAlert(sc.ctx, alert)
	if err != nil {
		return fmt.Errorf("failed to create alert 2: %w", err)
	}

	err = sc.createReviewRequestedEvent(created.ID, time.Now())
	if err != nil {
		return err
	}

	sc.printAlertCreated(created, &alert, "review requested")
	return nil
}

func (sc *seedContext) seedAlert3LicenseAdded() error {
	fmt.Println("\nAlert 3: Creating closed alert (license added workflow)...")
	resolution := models.AlertResolutionLicensesAdded
	alert := models.Alert{
		Status:                models.AlertStatusClosed,
		Resolution:            resolution,
		RepositoryID:          sc.repoID,
		OrganizationID:        sc.orgID,
		EnterpriseID:          &sc.businessID,
		ManifestName:          "requirements.txt",
		ManifestLineNumber:    8,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_PIP,
		PackageName:           "django",
		PackageVersion:        "4.2.0",
		SPDXLicenseExpression: "BSD-3-Clause",
		PullRequestNumber:     &sc.prNumber,
		PackageRepoNWO:        "django/django",
	}
	created, err := sc.store.CreateAlert(sc.ctx, alert)
	if err != nil {
		return fmt.Errorf("failed to create alert 3: %w", err)
	}

	now := time.Now()
	err = sc.createReviewRequestedEvent(created.ID, now)
	if err != nil {
		return err
	}
	err = sc.createReviewApprovedEvent(created.ID, now.Add(1*time.Minute), "BSD-3-Clause approved for use")
	if err != nil {
		return err
	}
	err = sc.createLicensesAddedEvent(created.ID, now.Add(2*time.Minute), []string{"BSD-3-Clause"})
	if err != nil {
		return err
	}
	err = sc.createClosedEvent(created.ID, now.Add(3*time.Minute), &sc.userID)
	if err != nil {
		return err
	}

	sc.printAlertCreated(created, &alert, "review requested → review approved → license added → closed")
	return nil
}

func (sc *seedContext) seedAlert4PackageException() error {
	fmt.Println("\nAlert 4: Creating closed alert (package exception workflow)...")
	resolution := models.AlertResolutionExceptionAdded
	alert := models.Alert{
		Status:                models.AlertStatusClosed,
		Resolution:            resolution,
		RepositoryID:          sc.repoID,
		OrganizationID:        sc.orgID,
		EnterpriseID:          &sc.businessID,
		ManifestName:          "go.mod",
		ManifestLineNumber:    12,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_GOMOD,
		PackageName:           "github.com/example/internal",
		PackageVersion:        "v1.2.3",
		SPDXLicenseExpression: "AGPL-3.0",
		PullRequestNumber:     &sc.prNumber,
	}
	created, err := sc.store.CreateAlert(sc.ctx, alert)
	if err != nil {
		return fmt.Errorf("failed to create alert 4: %w", err)
	}

	now := time.Now()
	err = sc.createReviewRequestedEvent(created.ID, now)
	if err != nil {
		return err
	}
	err = sc.createReviewApprovedEvent(created.ID, now.Add(1*time.Minute), "It's ok to add this to package exceptions")
	if err != nil {
		return err
	}
	err = sc.createExceptionAddedEvent(created.ID, now.Add(1*time.Minute), "go_modules", "github.com/example/internal")
	if err != nil {
		return err
	}
	err = sc.createClosedEvent(created.ID, now.Add(2*time.Minute), &sc.userID)
	if err != nil {
		return err
	}

	sc.printAlertCreated(created, &alert, "review requested → package exception → closed")
	return nil
}

func (sc *seedContext) seedAlert5ClosedBySideEffect() error {
	fmt.Println("\nAlert 4: Creating closed alert (package exception workflow)...")
	resolution := models.AlertResolutionOutdated
	alert := models.Alert{
		Status:                models.AlertStatusClosed,
		Resolution:            resolution,
		RepositoryID:          sc.repoID,
		OrganizationID:        sc.orgID,
		EnterpriseID:          &sc.businessID,
		ManifestName:          "go.mod",
		ManifestLineNumber:    12,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_GOMOD,
		PackageName:           "github.com/example/internal",
		PackageVersion:        "v1.2.3",
		SPDXLicenseExpression: "AGPL-3.0",
		PullRequestNumber:     &sc.prNumber,
		PackageRepoNWO:        "example/internal",
	}
	created, err := sc.store.CreateAlert(sc.ctx, alert)
	if err != nil {
		return fmt.Errorf("failed to create alert 4: %w", err)
	}

	now := time.Now()
	err = sc.createClosedEvent(created.ID, now.Add(2*time.Minute), nil)
	if err != nil {
		return err
	}

	sc.printAlertCreated(created, &alert, "review requested → package exception → closed")
	return nil
}

func (sc *seedContext) seedAlert6ExpiredReview() error {
	fmt.Println("\nAlert 6: Creating alert with expired review request...")
	alert := models.Alert{
		Status:                models.AlertStatusOpen,
		RepositoryID:          sc.repoID,
		OrganizationID:        sc.orgID,
		EnterpriseID:          &sc.businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    50,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "moment",
		PackageVersion:        "2.29.1",
		SPDXLicenseExpression: "LGPL-2.1",
		PullRequestNumber:     &sc.prNumber,
		PackageRepoNWO:        "moment/moment",
	}
	created, err := sc.store.CreateAlert(sc.ctx, alert)
	if err != nil {
		return fmt.Errorf("failed to create alert 6: %w", err)
	}

	// Review was requested 10 days ago
	reviewRequestedTime := time.Now().Add(-10 * 24 * time.Hour)
	err = sc.createReviewRequestedEvent(created.ID, reviewRequestedTime)
	if err != nil {
		return err
	}

	// Review expired 3 days ago (7 days after request)
	reviewExpiredTime := reviewRequestedTime.Add(7 * 24 * time.Hour)
	err = sc.createReviewExpiredEvent(created.ID, reviewExpiredTime)
	if err != nil {
		return err
	}

	sc.printAlertCreated(created, &alert, "expired review")
	return nil
}

func (sc *seedContext) seedAlert7AllEventTypes() error {
	fmt.Println("\nAlert 7: Creating alert with all event types...")
	resolution := models.AlertResolutionLicensesAdded
	alert := models.Alert{
		Status:                models.AlertStatusClosed,
		Resolution:            resolution,
		RepositoryID:          sc.repoID,
		OrganizationID:        sc.orgID,
		EnterpriseID:          &sc.businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    42,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "4.17.20",
		SPDXLicenseExpression: "GPL-3.0",
		PullRequestNumber:     &sc.prNumber,
	}
	created, err := sc.store.CreateAlert(sc.ctx, alert)
	if err != nil {
		return fmt.Errorf("failed to create alert 7: %w", err)
	}

	now := time.Now()
	err = sc.createReviewRequestedEvent(created.ID, now)
	if err != nil {
		return err
	}
	err = sc.createReviewDeniedEvent(created.ID, now.Add(1*time.Minute), "This license is not approved for use in production environments")
	if err != nil {
		return err
	}
	err = sc.createReviewExpiredEvent(created.ID, now.Add(2*time.Minute))
	if err != nil {
		return err
	}
	err = sc.createExceptionAddedEvent(created.ID, now.Add(3*time.Minute), "npm", "lodash")
	if err != nil {
		return err
	}
	err = sc.createLicensesAddedEvent(created.ID, now.Add(4*time.Minute), []string{"GPL-3.0", "GPL-3.0-or-later"})
	if err != nil {
		return err
	}
	err = sc.createReviewApprovedEvent(created.ID, now.Add(5*time.Minute), "BSD-3-Clause approved for use")
	if err != nil {
		return err
	}
	err = sc.createClosedEvent(created.ID, now.Add(6*time.Minute), nil)
	if err != nil {
		return err
	}

	sc.printAlertCreated(created, &alert, "all event types")
	return nil
}

func (sc *seedContext) createReviewRequestedEvent(alertID uint64, occurredAt time.Time) error {
	event := models.AlertEvent{
		AlertID:    alertID,
		EventType:  models.EventReviewRequested,
		UserID:     &sc.userID,
		OccurredAt: occurredAt,
		EventBody:  json.RawMessage("{}"),
	}
	err := sc.store.CreateAlertEvent(sc.ctx, event)
	if err != nil {
		return fmt.Errorf("failed to create review requested event: %w", err)
	}
	return nil
}

func (sc *seedContext) createReviewExpiredEvent(alertID uint64, occurredAt time.Time) error {
	event := models.AlertEvent{
		AlertID:    alertID,
		EventType:  models.EventReviewExpired,
		UserID:     nil, // System-generated event
		OccurredAt: occurredAt,
		EventBody:  json.RawMessage("{}"),
	}
	err := sc.store.CreateAlertEvent(sc.ctx, event)
	if err != nil {
		return fmt.Errorf("failed to create review expired event: %w", err)
	}
	return nil
}

func (sc *seedContext) createReviewDeniedEvent(alertID uint64, occurredAt time.Time, comment string) error {
	event := models.AlertEvent{
		AlertID:    alertID,
		EventType:  models.EventReviewDenied,
		UserID:     &sc.userID,
		OccurredAt: occurredAt,
		EventBody:  json.RawMessage(fmt.Sprintf(`{"comment": %q}`, comment)),
	}
	err := sc.store.CreateAlertEvent(sc.ctx, event)
	if err != nil {
		return fmt.Errorf("failed to create review denied event: %w", err)
	}
	return nil
}

func (sc *seedContext) createReviewApprovedEvent(alertID uint64, occurredAt time.Time, comment string) error {
	event := models.AlertEvent{
		AlertID:    alertID,
		EventType:  models.EventReviewApproved,
		UserID:     &sc.userID,
		OccurredAt: occurredAt,
		EventBody:  json.RawMessage(fmt.Sprintf(`{"comment": %q}`, comment)),
	}
	err := sc.store.CreateAlertEvent(sc.ctx, event)
	if err != nil {
		return fmt.Errorf("failed to create review approved event: %w", err)
	}
	return nil
}

func (sc *seedContext) createExceptionAddedEvent(alertID uint64, occurredAt time.Time, packageManager, packageName string) error {
	body := models.ExceptionAddedEventBody{
		PackageManager: packageManager,
		PackageName:    packageName,
		Level:          "organization",
	}
	bodyJSON, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("failed to marshal exception event body: %w", err)
	}
	event := models.AlertEvent{
		AlertID:    alertID,
		EventType:  models.EventExceptionAdded,
		UserID:     &sc.userID,
		OccurredAt: occurredAt,
		EventBody:  bodyJSON,
	}
	err = sc.store.CreateAlertEvent(sc.ctx, event)
	if err != nil {
		return fmt.Errorf("failed to create exception added event: %w", err)
	}
	return nil
}

func (sc *seedContext) createLicensesAddedEvent(alertID uint64, occurredAt time.Time, licenses []string) error {
	body := models.LicensesAddedEventBody{
		Licenses: licenses,
		Level:    "organization",
	}
	bodyJSON, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("failed to marshal licenses added event body: %w", err)
	}
	event := models.AlertEvent{
		AlertID:    alertID,
		EventType:  models.EventLicensesAdded,
		UserID:     &sc.userID,
		OccurredAt: occurredAt,
		EventBody:  bodyJSON,
	}
	err = sc.store.CreateAlertEvent(sc.ctx, event)
	if err != nil {
		return fmt.Errorf("failed to create licenses added event: %w", err)
	}
	return nil
}

func (sc *seedContext) createClosedEvent(alertID uint64, occurredAt time.Time, userID *uint64) error {
	event := models.AlertEvent{
		AlertID:    alertID,
		EventType:  models.EventClosed,
		UserID:     userID,
		OccurredAt: occurredAt,
		EventBody:  json.RawMessage(`{}`),
	}
	err := sc.store.CreateAlertEvent(sc.ctx, event)
	if err != nil {
		return fmt.Errorf("failed to create closed event: %w", err)
	}
	return nil
}

func (sc *seedContext) printAlertCreated(created, alert *models.Alert, workflow string) {
	fmt.Printf("✓ Alert #%d: %s@%s - %s (%s)\n", created.Number, alert.PackageName, alert.PackageVersion, created.Status.String(), workflow)
	fmt.Printf("  http://github.localhost/github/public-server/security/license-compliance/%d\n", created.Number)
}
