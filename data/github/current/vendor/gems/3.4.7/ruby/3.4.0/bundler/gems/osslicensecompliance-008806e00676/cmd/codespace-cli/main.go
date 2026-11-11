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
	if err := run(); err != nil {
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
	defer store.Close()

	sc := seedContext{
		store:      store,
		ctx:        context.Background(),
		userID:     uint64(2),
		prNumber:   uint32(1),
		repoID:     uint64(3),
		orgID:      uint64(6),
		businessID: uint64(1),
	}

	if err := sc.seedAlert1Open(); err != nil {
		return err
	}
	if err := sc.seedAlert2ReviewRequested(); err != nil {
		return err
	}
	if err := sc.seedAlert3LicenseAdded(); err != nil {
		return err
	}
	if err := sc.seedAlert4PackageException(); err != nil {
		return err
	}
	if err := sc.seedAlert5ClosedBySideEffect(); err != nil {
		return err
	}
	if err := sc.seedAlert6AllEventTypes(); err != nil {
		return err
	}

	fmt.Println("\n✓ Successfully seeded 5 alerts with realistic event workflows!")
	fmt.Println("\nView all alerts at:")
	fmt.Println("  http://github.localhost/github/public-server/security/license-compliance-scanning-alerts")
	return nil
}

func (sc *seedContext) seedAlert1Open() error {
	fmt.Println("Alert 1: Creating open alert with no events...")
	alert := models.Alert{
		Status:                models.Open,
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
		Status:                models.ReviewRequested,
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
	}
	created, err := sc.store.CreateAlert(sc.ctx, alert)
	if err != nil {
		return fmt.Errorf("failed to create alert 2: %w", err)
	}

	if err := sc.createReviewRequestedEvent(created.ID, time.Now()); err != nil {
		return err
	}

	sc.printAlertCreated(created, &alert, "review requested")
	return nil
}

func (sc *seedContext) seedAlert3LicenseAdded() error {
	fmt.Println("\nAlert 3: Creating closed alert (license added workflow)...")
	resolution := models.PolicyChanged
	alert := models.Alert{
		Status:                models.Closed,
		Resolution:            &resolution,
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
	}
	created, err := sc.store.CreateAlert(sc.ctx, alert)
	if err != nil {
		return fmt.Errorf("failed to create alert 3: %w", err)
	}

	now := time.Now()
	if err := sc.createReviewRequestedEvent(created.ID, now); err != nil {
		return err
	}
	if err := sc.createReviewApprovedEvent(created.ID, now.Add(1*time.Minute), "BSD-3-Clause approved for use"); err != nil {
		return err
	}
	if err := sc.createLicensesAddedEvent(created.ID, now.Add(2*time.Minute), []string{"BSD-3-Clause"}); err != nil {
		return err
	}
	if err := sc.createClosedEvent(created.ID, now.Add(3*time.Minute), &sc.userID); err != nil {
		return err
	}

	sc.printAlertCreated(created, &alert, "review requested → review approved → license added → closed")
	return nil
}

func (sc *seedContext) seedAlert4PackageException() error {
	fmt.Println("\nAlert 4: Creating closed alert (package exception workflow)...")
	resolution := models.ExceptionAdded
	alert := models.Alert{
		Status:                models.Closed,
		Resolution:            &resolution,
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
	if err := sc.createReviewRequestedEvent(created.ID, now); err != nil {
		return err
	}
	if err := sc.createReviewApprovedEvent(created.ID, now.Add(1*time.Minute), "It's ok to add this to package exceptions"); err != nil {
		return err
	}
	if err := sc.createExceptionAddedEvent(created.ID, now.Add(2*time.Minute), "go_modules", "github.com/example/internal"); err != nil {
		return err
	}
	if err := sc.createClosedEvent(created.ID, now.Add(3*time.Minute), &sc.userID); err != nil {
		return err
	}

	sc.printAlertCreated(created, &alert, "review requested → package exception → closed")
	return nil
}

func (sc *seedContext) seedAlert5ClosedBySideEffect() error {
	fmt.Println("\nAlert 5: Creating closed alert (package exception workflow)...")
	resolution := models.ExceptionAdded
	alert := models.Alert{
		Status:                models.Closed,
		Resolution:            &resolution,
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
	if err := sc.createClosedEvent(created.ID, now.Add(2*time.Minute), nil); err != nil {
		return err
	}

	sc.printAlertCreated(created, &alert, "closed by side effect")
	return nil
}

func (sc *seedContext) seedAlert6AllEventTypes() error {
	fmt.Println("\nAlert 5: Creating alert with all event types...")
	resolution := models.PolicyChanged
	alert := models.Alert{
		Status:                models.Closed,
		Resolution:            &resolution,
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
		return fmt.Errorf("failed to create alert 5: %w", err)
	}

	now := time.Now()
	if err := sc.createReviewRequestedEvent(created.ID, now); err != nil {
		return err
	}
	if err := sc.createReviewDeniedEvent(created.ID, now.Add(1*time.Minute), "This license is not approved for use in production environments"); err != nil {
		return err
	}
	if err := sc.createExceptionAddedEvent(created.ID, now.Add(2*time.Minute), "npm", "lodash"); err != nil {
		return err
	}
	if err := sc.createLicensesAddedEvent(created.ID, now.Add(3*time.Minute), []string{"GPL-3.0", "GPL-3.0-or-later"}); err != nil {
		return err
	}
	if err := sc.createReviewApprovedEvent(created.ID, now.Add(4*time.Minute), "BSD-3-Clause approved for use"); err != nil {
		return err
	}
	if err := sc.createClosedEvent(created.ID, now.Add(4*time.Minute), nil); err != nil {
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
	if err := sc.store.CreateAlertEvent(sc.ctx, event); err != nil {
		return fmt.Errorf("failed to create review requested event: %w", err)
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
	if err := sc.store.CreateAlertEvent(sc.ctx, event); err != nil {
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
	if err := sc.store.CreateAlertEvent(sc.ctx, event); err != nil {
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
	if err := sc.store.CreateAlertEvent(sc.ctx, event); err != nil {
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
	if err := sc.store.CreateAlertEvent(sc.ctx, event); err != nil {
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
	if err := sc.store.CreateAlertEvent(sc.ctx, event); err != nil {
		return fmt.Errorf("failed to create closed event: %w", err)
	}
	return nil
}

func (sc *seedContext) printAlertCreated(created, alert *models.Alert, workflow string) {
	fmt.Printf("✓ Alert #%d: %s@%s - %s (%s)\n", created.Number, alert.PackageName, alert.PackageVersion, created.Status.String(), workflow)
	fmt.Printf("  http://github.localhost/github/public-server/security/license-compliance-scanning-alerts/%d\n", created.Number)
}
