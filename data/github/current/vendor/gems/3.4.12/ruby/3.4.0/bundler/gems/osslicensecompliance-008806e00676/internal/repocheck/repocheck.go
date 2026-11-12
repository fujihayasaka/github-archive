// Package repocheck runs a policy evaluation on a repository.
package repocheck

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/internal/dsapiclient"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/eventpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/semconv"
	"github.com/github/osslicensecompliance/internal/storage"
	"go.uber.org/zap/zapcore"
)

// Checker provides the ability to check repositories against policies.
// It holds the dependencies necessary to perform repository checks.
type Checker struct {
	storage          *storage.Storage
	dependencyGetter *dependencies.DependencyGetter
	diffStatusGetter *dsapiclient.StatusGetter
	publisher        *eventpublisher.Publisher
	logger           log.Logger
}

// NewChecker creates a new Checker with dependencies from the application.
func NewChecker(app *application.Application) *Checker {
	return &Checker{
		storage:          app.Subsystems.Storage,
		dependencyGetter: app.Subsystems.DependencyGetter,
		diffStatusGetter: app.Subsystems.DiffStatusGetter,
		publisher:        app.Subsystems.EventPublisher,
		logger:           app.Logger,
	}
}

// Request provides the data necessary to check a repository against a policy.
// It holds only the state and validation logic needed for the check.
type Request struct {
	EnterpriseID      uint64
	OrganizationID    uint64
	RepositoryID      uint64
	PullRequestID     uint64
	Context           string
	CommitSHA         string
	BaseSHA           string
	PullRequestNumber uint32
}

// Check runs through all of the steps to evaluate a repository
// against applicable license policy.
func (c *Checker) Check(ctx context.Context, req *Request) (evaluator.RepositoryResults, error) {
	fields := []zapcore.Field{semconv.Method("Check")}
	fields = append(fields, semconv.RepoCheckRequestFields(
		req.EnterpriseID, req.OrganizationID, req.RepositoryID,
		req.PullRequestID, req.PullRequestNumber, req.CommitSHA, req.BaseSHA)...)

	logger := c.logger.Named("repocheck").WithFields(fields...)
	logger.Debug("Checking repository")

	err := req.Validate()
	if err != nil {
		return evaluator.RepositoryResults{}, err
	}

	// Load the policy
	policy, err := c.storage.GetCompletePolicy(ctx, req.EnterpriseID, req.OrganizationID, req.RepositoryID)
	if err != nil {
		return evaluator.RepositoryResults{}, fmt.Errorf("check repository failed to load policy: %w", err)
	}
	logger.Debug("Loaded policy")

	if policy.EnterprisePolicy != nil {
		logger.Debug(fmt.Sprintf("Enterprise policy: %v", policy.EnterprisePolicy.Data.CreatedAt))
	}

	if policy.OrganizationPolicy != nil {
		logger.Debug(fmt.Sprintf("Organization policy: %v", policy.OrganizationPolicy.Data.CreatedAt))
	}

	// Get the dependencies for the repository
	var deps map[string]models.Package

	// If BaseSHA is provided, use the new DRA diff dependencies
	deps, err = c.dependencyGetter.GetDiffDependenciesForRepo(ctx, req.RepositoryID, req.CommitSHA, req.BaseSHA)
	if err != nil {
		return evaluator.RepositoryResults{}, err
	}

	logger.Debug(fmt.Sprintf("Loaded %d dependencies", len(deps)))

	// Evaluate the policy against the dependencies
	results := evaluator.PolicyResultsForRepository(deps, policy, req.Context, logger)
	logger.Debug(fmt.Sprintf("Policy evaluation results: %+v", results))

	// Get existing check job record for repository and pull request
	checkJob, err := c.storage.GetCheckJob(ctx, req.RepositoryID, req.PullRequestNumber)
	if err != nil && !errors.Is(err, storage.ErrNotFound) {
		return evaluator.RepositoryResults{}, err
	}

	// Only update alerts if there are no new commits for pull request (commit and base SHAs are the same)
	if checkJob != nil && checkJob.CommitSHA == req.CommitSHA && checkJob.BaseSHA == req.BaseSHA {
		if err := c.UpdateAlerts(ctx, results, models.Unknown, req, policy.GetRemediationGuidance()); err != nil { // Using Unknown resolution as we cannot determine the specific cause yet.
			return evaluator.RepositoryResults{}, err
		}
	}

	return results, nil
}

// Start sets up a CheckJob and prepares to start or restart a check run. If snapshots are pending,
// it sets the state to 'waiting'. If there aren't any snapshots, it runs the license check.
func (c *Checker) Start(ctx context.Context, checkJob *models.CheckJob, req *Request) error {
	fields := []zapcore.Field{semconv.Method("Start")}
	fields = append(fields, semconv.RepoCheckRequestFields(
		req.EnterpriseID, req.OrganizationID, req.RepositoryID,
		req.PullRequestID, req.PullRequestNumber, req.CommitSHA, req.BaseSHA)...)

	logger := c.logger.Named("Start").WithFields(fields...)

	var err error
	if checkJob == nil {
		// create new check job when first time trying to start the check
		logger.Info("Start: handling new request")
		checkJob, err = c.storage.CreateCheckJob(ctx, models.CheckJob{
			RepositoryID:      req.RepositoryID,
			OrganizationID:    req.OrganizationID,
			EnterpriseID:      &req.EnterpriseID,
			PullRequestID:     req.PullRequestID,
			PullRequestNumber: req.PullRequestNumber,
			BaseSHA:           req.BaseSHA,
			CommitSHA:         req.CommitSHA,
		})
		if err != nil {
			return fmt.Errorf("%w: %w", ErrCheckJobCreation, err)
		}
		if checkJob == nil {
			return fmt.Errorf("%w: checkJob is nil", ErrCheckJobCreation)
		}
	} else {
		// handle new commit or change to base to existing PR
		logger.Info("Start: handling existing checkJob with changed SHA")
		checkJob.CommitSHA = req.CommitSHA
		checkJob.BaseSHA = req.BaseSHA
	}

	// Reset snapshot diff status
	checkJob.ExpectedSnapshots = EmptySnapshotDiffStatus.Expected
	checkJob.ReceivedSnapshots = EmptySnapshotDiffStatus.Received
	checkJob.Status = models.Starting
	err = c.storage.UpdateCheckJob(ctx, checkJob)
	if err != nil {
		return fmt.Errorf("%w: %w", ErrCheckJobUpdate, err)
	}

	// Check if need to wait for snapshots
	var waiting bool
	var diffStatus *SnapshotDiffStatus
	if diffStatus, waiting, err = WaitingForSnapshots(ctx, c.logger, c.diffStatusGetter, checkJob.RepositoryID, req.CommitSHA, req.BaseSHA); waiting {
		logger.Info("Start", kvp.String("diffStatus", "waiting for snapshots before running check"))
		checkJob.ExpectedSnapshots = diffStatus.Expected
		checkJob.ReceivedSnapshots = diffStatus.Received
		checkJob.Status = models.Waiting
		err = c.storage.UpdateCheckJob(ctx, checkJob)
		if err != nil {
			return fmt.Errorf("%w: %w", ErrCheckJobUpdate, err)
		}
		return nil
	}
	if err != nil {
		return fmt.Errorf("failed checking snapshot wait status: %w", err)
	}

	return c.ExecuteJob(ctx, checkJob, req)
}

// ExecuteJob runs the actual license check for a repository after required snapshots are available.
// It updates the check job status, performs the policy evaluation, and records the results.
func (c *Checker) ExecuteJob(ctx context.Context, checkJob *models.CheckJob, req *Request) error {
	fields := []zapcore.Field{semconv.Method("ExecuteJob")}
	fields = append(fields, semconv.RepoCheckRequestFields(
		req.EnterpriseID, req.OrganizationID, req.RepositoryID,
		req.PullRequestID, req.PullRequestNumber, req.CommitSHA, req.BaseSHA)...)

	logger := c.logger.Named("ExecuteJob").WithFields(fields...)

	// Update CheckJob status to running in DB
	checkJob.Status = models.Running
	err := c.storage.UpdateCheckJob(ctx, checkJob)
	if err != nil {
		return fmt.Errorf("%w: %w", ErrCheckJobUpdate, err)
	}

	logger.Info("starting check for repository")
	results, err := c.Check(ctx, req)
	if err != nil {
		return fmt.Errorf("policy check failed: %w", err)
	}

	// Set the final status based on results
	finalStatus := models.Pass
	if results.FailureCount > 0 || results.ErrorCount > 0 {
		logger.Info(fmt.Sprintf("check completed with %d failures and %d errors", results.FailureCount, results.ErrorCount))
		finalStatus = models.Fail
	} else {
		logger.Info("check completed with all passing")
	}

	// Update CheckJob final status in DB
	checkJob.Status = finalStatus
	err = c.storage.UpdateCheckJob(ctx, checkJob)
	if err != nil {
		return fmt.Errorf("%w: %w", ErrCheckJobUpdate, err)
	}

	return nil
}

// UpdateAlerts manages license compliance alerts based on policy evaluation results.
// It creates new alerts for packages that failed policy evaluation (avoiding duplicates) and closes
// existing alerts for packages that are no longer failing. This function only runs during
// Check when all CheckJob snapshots are available.
func (c *Checker) UpdateAlerts(ctx context.Context, results evaluator.RepositoryResults, resolution models.AlertResolution, req *Request, guidance string) error {
	fields := []zapcore.Field{semconv.Method("UpdateAlerts")}
	fields = append(fields, semconv.RepoCheckRequestFields(
		req.EnterpriseID, req.OrganizationID, req.RepositoryID,
		req.PullRequestID, req.PullRequestNumber, req.CommitSHA, req.BaseSHA)...)

	logger := c.logger.Named("updatealerts").WithFields(fields...)

	logger.Debug("Creating alerts for repository's failed packages")

	openAlertsMap, err := c.storage.GetOpenAlerts(ctx, req.RepositoryID, &req.PullRequestNumber)
	if err != nil {
		return fmt.Errorf("failed to retrieve open alerts: %w", err)
	}

	// Create a set of keys for packages that failed license policy evaluation
	failureKeys := make(map[string]bool)

	openAlerts := []*models.Alert{}

	for _, pkg := range results.Failures {
		// Manifest name is by default an empty string to guard against cases where snapshots may not contain a manifest
		manifestName := ""
		if len(pkg.Package.Manifests) > 0 {
			manifestName = pkg.Package.Manifests[0] // Use first manifest only - avoids duplicate alerts for the same package
		}

		key := storage.CreatePackageKey(models.PackageManagerToString(pkg.Package.PackageManager), pkg.Package.Name, pkg.Package.License)
		failureKeys[key] = true

		if _, ok := openAlertsMap[key]; ok {
			continue // alert already exists, skip creating it
		}

		newAlert := models.Alert{
			RepositoryID:          req.RepositoryID,
			OrganizationID:        req.OrganizationID,
			EnterpriseID:          &req.EnterpriseID,
			ManifestName:          manifestName,
			PackageEcosystem:      pkg.Package.PackageManager, //nolint:gosec,G115 // Conversion is safe: PackageManager is always non-negative
			PackageName:           pkg.Package.Name,
			PackageVersion:        string(pkg.Package.Version),
			SPDXLicenseExpression: pkg.Package.License,
			PullRequestNumber:     &req.PullRequestNumber,
		}

		createdAlert, err := c.storage.CreateAlert(ctx, newAlert)
		if err != nil {
			return fmt.Errorf("failed to create alert: %w", err)
		}

		openAlerts = append(openAlerts, createdAlert)
	}
	logger.Debug(fmt.Sprintf("Created %d alerts", len(results.Failures)))

	// Close alerts for packages that no longer fail policy evaluation
	for alertKey, alerts := range openAlertsMap {
		if !failureKeys[alertKey] {
			for _, alert := range alerts {
				// TODO (@ashelytc): Can we pass in UserID through the check job?
				if err := c.storage.CloseAlertWithEvent(ctx, alert, nil, resolution, nil); err != nil {
					logger.Error("Failed to close alert", kvp.Uint32("number", alert.Number), kvp.String("error", err.Error()))
				}
			}
		} else {
			openAlerts = append(openAlerts, alerts...)
		}
	}
	err = c.publisher.PublishPRLicenseCheckCompleteEvent(
		ctx,
		req.RepositoryID,
		req.PullRequestID,
		req.PullRequestNumber,
		req.CommitSHA,
		req.BaseSHA,
		openAlerts,
		guidance,
	)
	if err != nil {
		c.logger.Error("Failed to publish PR license check complete event", kvp.String("error", err.Error()))
	}
	return nil
}

// ValidationError is returned when required fields are missing in Request.
type ValidationError struct {
	MissingFields []string
}

// NewValidationError creates a new ValidationError with the given missing fields.
func NewValidationError(missingFields []string) error {
	return &ValidationError{MissingFields: missingFields}
}

// Error implements the error interface for ValidationError.
func (e *ValidationError) Error() string {
	return fmt.Sprintf("missing required fields: %v", e.MissingFields)
}

// ErrCheckJobCreation is returned when a check job cannot be created.
var ErrCheckJobCreation = errors.New("failed to create check job")

// ErrCheckJobUpdate is returned when a check job cannot be updated.
var ErrCheckJobUpdate = errors.New("failed to update check job")

// Validate checks that all required fields are present in the Request.
// It returns a ValidationError if any required fields are missing.
func (req *Request) Validate() error {
	missingFields := []string{}
	if req.RepositoryID == 0 {
		missingFields = append(missingFields, "repository_id")
	}
	if req.PullRequestNumber == 0 {
		missingFields = append(missingFields, "pull_request_number")
	}
	if req.OrganizationID == 0 {
		missingFields = append(missingFields, "organization_id")
	}
	if req.CommitSHA == "" {
		missingFields = append(missingFields, "commit_sha")
	}
	if req.BaseSHA == "" {
		missingFields = append(missingFields, "base_sha")
	}

	if len(missingFields) > 0 {
		return NewValidationError(missingFields)
	}
	return nil
}
