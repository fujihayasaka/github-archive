// Package repocheck runs a policy evaluation on a repository.
package repocheck

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-server/runtime/telemetry/reporter"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/internal/dsapiclient"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/eventpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/pointers"
	"github.com/github/osslicensecompliance/internal/remediation"
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
	metrics          stats.Client
	logger           log.Logger
	tags             stats.Tags
	app              *application.Application
}

// NewChecker creates a new Checker with dependencies from the application.
func NewChecker(app *application.Application, metrics stats.Client) *Checker {
	return &Checker{
		storage:          app.Subsystems.Storage,
		dependencyGetter: app.Subsystems.DependencyGetter,
		diffStatusGetter: app.Subsystems.DiffStatusGetter,
		publisher:        app.Subsystems.EventPublisher,
		metrics:          metrics,
		logger:           app.Logger,
		app:              app,
	}
}

// WithTags sets the tags for the Checker.
func (c *Checker) WithTags(tags map[string]string) *Checker {
	c.tags = stats.Tags(tags)
	return c
}

// Request provides the data necessary to check a repository against a policy.
// It holds only the state and validation logic needed for the check.
type Request struct {
	EnterpriseID      uint64
	OrganizationID    uint64
	RepositoryID      uint64
	PullRequestID     uint64
	ForkRepositoryID  uint64
	HeadRef           string
	Context           string
	CommitSHA         string
	BaseSHA           string
	PullRequestNumber uint32
}

// Start sets up a CheckJob and prepares to start or restart a check run. If snapshots are pending,
// it sets the state to 'waiting'. If there aren't any snapshots, it runs the license check.
func (c *Checker) Start(ctx context.Context, checkJob *models.CheckJob, req *Request) error {
	fields := []zapcore.Field{semconv.Method("Start")}
	fields = append(fields, semconv.RepoCheckRequestFields(
		req.EnterpriseID, req.OrganizationID, req.RepositoryID,
		req.PullRequestID, req.PullRequestNumber, req.CommitSHA, req.BaseSHA, req.ForkRepositoryID)...)

	logger := c.logger.Named("Start").WithFields(fields...)

	if req.ForkRepositoryID != 0 {
		c.metrics.Counter("repocheck.start", stats.Tags{"fork": "true"}, 1)
	} else {
		c.metrics.Counter("repocheck.start", stats.Tags{"fork": "false"}, 1)
	}

	var err error
	if checkJob == nil {
		// create new check job when first time trying to start the check
		logger.Info("Start: handling new request")
		checkJob, err = c.storage.CreateCheckJob(ctx, models.CheckJob{
			RepositoryID:      req.RepositoryID,
			OrganizationID:    req.OrganizationID,
			EnterpriseID:      &req.EnterpriseID,
			ForkRepositoryID:  pointers.ZeroToNil(req.ForkRepositoryID),
			HeadRef:           pointers.ZeroToNil(req.HeadRef),
			PullRequestID:     req.PullRequestID,
			PullRequestNumber: req.PullRequestNumber,
			BaseSHA:           req.BaseSHA,
			CommitSHA:         req.CommitSHA,
		})
		if err != nil {
			c.fail(ctx, nil, req, ErrCheckJobCreation)
			return fmt.Errorf("%w: %w", ErrCheckJobCreation, err)
		}
		if checkJob == nil {
			createErr := fmt.Errorf("%w: checkJob is nil", ErrCheckJobCreation)
			c.fail(ctx, nil, req, createErr)
			return createErr
		}
	} else {
		// handle existing checkJob - either SHA changed or this is a restart
		if checkJob.CommitSHA != req.CommitSHA || checkJob.BaseSHA != req.BaseSHA {
			logger.Info("Start: handling existing checkJob with changed SHA")
			checkJob.CommitSHA = req.CommitSHA
			checkJob.BaseSHA = req.BaseSHA
		} else {
			logger.Info("Start: restarting existing checkJob")
		}
		// Preserve fork_repository_id from the persisted CheckJob so API calls
		// use the correct target repo even if the caller omits it on restart.
		if checkJob.ForkRepositoryID != nil && req.ForkRepositoryID == 0 {
			req.ForkRepositoryID = *checkJob.ForkRepositoryID
		}
		// Update head_ref from the request when provided.
		if req.HeadRef != "" {
			checkJob.HeadRef = pointers.ZeroToNil(req.HeadRef)
		}
	}

	checkJob.Status = models.Starting
	c.publisher.PublishLicenseCheckProgress(ctx, checkJob)

	snapStatus, err := GetSnapshotStatus(ctx, c.logger, c.diffStatusGetter, checkJob.RepositoryID, req.CommitSHA, req.BaseSHA, req.ForkRepositoryID, req.OrganizationID)

	// Always overwrite MissingDetectors with the latest snapshot status. This
	// both populates it on transition into Waiting and clears it (to []) once
	// all snapshots have been received.
	checkJob.ExpectedSnapshots = snapStatus.Expected
	checkJob.ReceivedSnapshots = snapStatus.Received
	checkJob.MissingDetectors = snapStatus.MissingDetectors
	checkJob.DependabotPending = snapStatus.DependabotPending
	if snapStatus.IsWaiting() {
		logger.Info("Start", kvp.String("diffStatus", "waiting for snapshots before running check"))
		checkJob.Status = models.Waiting
	}

	// Always attempt to update checkJob even if GetSnapshotStatus returns an error.
	// In that case, snapStatus.Expected and snapStatus.Received remain zero and are stored as such.
	updateErr := c.storage.UpdateCheckJob(ctx, checkJob)
	if updateErr != nil {
		c.fail(ctx, checkJob, req, ErrCheckJobUpdate)
		return fmt.Errorf("%w: %w", ErrCheckJobUpdate, updateErr)
	}

	if err != nil {
		c.fail(ctx, checkJob, req, ErrSnapshotStatus)
		return fmt.Errorf("%w: %w", ErrSnapshotStatus, err)
	}

	if snapStatus.IsWaiting() {
		c.publisher.PublishLicenseCheckProgress(ctx, checkJob)
		return nil
	}

	return c.ExecuteJob(ctx, checkJob, req)
}

const checkRepositoryTimeout = 90 * time.Second

// failCleanupTimeout bounds how long fail() cleanup operations (such as DB updates)
// are allowed to take. This is separate from checkRepositoryTimeout so cleanup can proceed
// even after the check timeout has fired.
const failCleanupTimeout = 10 * time.Second

// ExecuteJob runs the actual license check for a repository after required snapshots are available.
// It updates the check job status, performs the policy evaluation, and records the results.
// Uses optimistic locking to detect policy changes during execution and retries if needed.
func (c *Checker) ExecuteJob(ctx context.Context, checkJob *models.CheckJob, req *Request) error {
	start := time.Now()
	defer func() {
		c.metrics.DistributionMs("repocheck.execute_job.duration", c.tags, time.Since(start))
	}()

	fields := []zapcore.Field{semconv.Method("ExecuteJob")}
	fields = append(fields, semconv.RepoCheckRequestFields(
		req.EnterpriseID, req.OrganizationID, req.RepositoryID,
		req.PullRequestID, req.PullRequestNumber, req.CommitSHA, req.BaseSHA, req.ForkRepositoryID)...)

	logger := c.logger.Named("ExecuteJob").WithFields(fields...)

	// Make sure the checks don't run forever.
	ctx, cancel := context.WithTimeoutCause(ctx, checkRepositoryTimeout, ErrCheckTimeout)
	defer cancel()

	const maxRetries = 10
	var results evaluator.RepositoryResults
	var finalStatus models.CheckStatus

	for attempt := 1; attempt <= maxRetries; attempt++ {
		// Update CheckJob status to running in DB
		checkJob.Status = models.Running
		err := c.storage.UpdateCheckJob(ctx, checkJob)
		if err != nil {
			c.fail(ctx, checkJob, req, ErrCheckJobUpdate)
			return fmt.Errorf("%w: %w", ErrCheckJobUpdate, err)
		}

		if attempt == 1 {
			logger.Info("starting check for repository")
			c.publisher.PublishLicenseCheckProgress(ctx, checkJob)
		} else {
			logger.Info("retrying check due to policy change", kvp.Int("attempt", attempt), kvp.Int("max_retries", maxRetries))
		}

		// Get policy with version before check
		policy, versionBefore, err := c.storage.GetCompletePolicyWithVersion(ctx, req.EnterpriseID, req.OrganizationID, req.RepositoryID)
		if err != nil {
			if errors.Is(err, storage.ErrNotFound) {
				c.fail(ctx, checkJob, req, ErrPolicyNotFound)
				return ErrPolicyNotFound
			}
			c.fail(ctx, checkJob, req, ErrPolicyLoad)
			return fmt.Errorf("%w: %w", ErrPolicyLoad, err)
		}

		// Perform check with the policy we just fetched
		results, err = c.checkWithPolicy(ctx, req, policy, logger)
		if err != nil {
			c.fail(ctx, checkJob, req, err)
			return err
		}

		// Verify policy didn't change during check
		versionAfter, err := c.storage.GetPolicyVersion(ctx, req.EnterpriseID, req.OrganizationID, req.RepositoryID)
		if err != nil {
			logger.WithError(err).Warn("failed to get policy version after check, proceeding with results")
			// Continue with results we have
		} else if !versionBefore.Equals(versionAfter) {
			// Policy changed during check
			changedFields := versionBefore.ChangedFields(versionAfter)
			logger.Info("policy changed during check, retrying", kvp.String("changed_fields", changedFields))
			c.metrics.Counter("policy_version_mismatch", nil, 1)

			if attempt < maxRetries {
				// Retry with fresh policy
				continue
			}

			// Max retries exhausted
			logger.Warn("policy changed multiple times during check, using last results", kvp.Int("retry_count", maxRetries))
			c.metrics.Counter("policy_version_retry_exhausted", nil, 1)
		}

		// Policy was stable (or we exhausted retries), proceed with results
		break
	}

	// Set the final status based on results
	finalStatus = models.Pass
	if results.FailureCount > 0 || results.ErrorCount > 0 {
		logger.Info("check completed with failures", kvp.Int("failure_count", results.FailureCount), kvp.Int("error_count", results.ErrorCount))
		finalStatus = models.Fail
	} else {
		logger.Info("check completed with all passing")
	}

	// Update CheckJob final status in DB
	checkJob.Status = finalStatus
	err := c.storage.UpdateCheckJob(ctx, checkJob)
	if err != nil {
		c.fail(ctx, checkJob, req, ErrCheckJobUpdate)
		return fmt.Errorf("%w: %w", ErrCheckJobUpdate, err)
	}

	c.publisher.PublishLicenseCheckResult(ctx, checkJob, results.FailureCount)

	return nil
}

// UpdateAlerts manages license compliance alerts based on policy evaluation results.
// It creates new alerts for packages that failed policy evaluation (avoiding duplicates) and closes
// existing alerts for packages that are no longer failing. This function only runs during
// Check when all CheckJob snapshots are available.
func (c *Checker) UpdateAlerts(ctx context.Context, results evaluator.RepositoryResults, req *Request, guidance string) error {
	fields := []zapcore.Field{semconv.Method("UpdateAlerts")}
	fields = append(fields, semconv.RepoCheckRequestFields(
		req.EnterpriseID, req.OrganizationID, req.RepositoryID,
		req.PullRequestID, req.PullRequestNumber, req.CommitSHA, req.BaseSHA, req.ForkRepositoryID)...)

	logger := c.logger.Named("updatealerts").WithFields(fields...)
	c.logger = logger

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
			PackageRepoNWO:        pkg.Package.PackageRepoNWO,
		}

		createdAlert, err := c.storage.CreateAlert(ctx, newAlert)
		if err != nil {
			return fmt.Errorf("failed to create alert: %w", err)
		}

		openAlerts = append(openAlerts, createdAlert)
	}
	logger.Debug("Created alerts", kvp.Int("count", len(results.Failures)))

	// Close alerts for packages that no longer fail policy evaluation
	for alertKey, alerts := range openAlertsMap {
		if !failureKeys[alertKey] {
			remediation.CloseOutdatedAlerts(ctx, c.app, alerts, req.PullRequestID)
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
		if reportErr := reporter.ReportWithValues(ctx, err, nil); reportErr != nil {
			c.logger.WithError(reportErr).Error("failed to report error to Sentry")
		}
	}
	return nil
}

// fail persists an error status on the check job and publishes an error progress event.
func (c *Checker) fail(ctx context.Context, checkJob *models.CheckJob, req *Request, errToReport error) {
	if errors.Is(context.Cause(ctx), ErrCheckTimeout) {
		errToReport = fmt.Errorf("%w: %w", ErrCheckTimeout, errToReport)
		c.logger.Error("check job timed out", kvp.String("error", errToReport.Error()))
	}

	// Detach from the caller's cancellation so cleanup can complete after a timeout
	cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), failCleanupTimeout)
	defer cancel()

	if checkJob != nil {
		checkJob.Status = models.Error
		err := c.storage.UpdateCheckJob(cleanupCtx, checkJob)
		if err != nil {
			c.logger.Error("failed to update check job status to error", kvp.String("error", err.Error()), semconv.RepositoryID(checkJob.RepositoryID))
			if reportErr := reporter.ReportWithValues(cleanupCtx, err, nil); reportErr != nil {
				c.logger.WithError(reportErr).Error("failed to report error to Sentry")
			}
		}
	}

	c.publisher.PublishLicenseCheckError(cleanupCtx, req.CommitSHA, req.RepositoryID, SanitizeError(errToReport))
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

// ErrDependencyFetch is returned when dependencies cannot be retrieved.
var ErrDependencyFetch = errors.New("failed to fetch dependencies")

// ErrPolicyLoad is returned when a license policy cannot be loaded.
var ErrPolicyLoad = errors.New("failed to load policy")

// ErrPolicyNotFound is returned when no license policy is configured for a repository.
var ErrPolicyNotFound = errors.New("policy not found")

// ErrAlertUpdate is returned when license alerts cannot be updated.
var ErrAlertUpdate = errors.New("failed to update alerts")

// ErrSnapshotStatus is returned when the snapshot diff status cannot be determined.
var ErrSnapshotStatus = errors.New("failed to check snapshot status")

// ErrCheckTimeout is returned when the overall license check timeout is exceeded.
// This distinguishes our explicit timeout from other context.DeadlineExceeded errors
// that may originate from downstream services (HTTP clients, gRPC, databases, etc.).
var ErrCheckTimeout = errors.New("license check timeout exceeded")

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

// checkWithPolicy performs the actual check using a specific policy instance.
// This is extracted to allow retry logic in ExecuteJob.
func (c *Checker) checkWithPolicy(ctx context.Context, req *Request, policy *models.CompletePolicy, logger log.Logger) (evaluator.RepositoryResults, error) {
	logger.Debug("Loaded policy")

	if policy.EnterprisePolicy != nil {
		logger.Debug("Enterprise policy loaded", kvp.String("created_at", policy.EnterprisePolicy.Data.CreatedAt.String()))
	}
	if policy.OrganizationPolicy != nil {
		logger.Debug("Organization policy loaded", kvp.String("created_at", policy.OrganizationPolicy.Data.CreatedAt.String()))
	}

	// Get the dependencies for the repository
	var deps map[string]models.Package
	var err error

	// If BaseSHA is provided, use the new DRA diff dependencies
	deps, err = c.dependencyGetter.GetDiffDependenciesForRepo(ctx, req.RepositoryID, req.CommitSHA, req.BaseSHA, req.ForkRepositoryID, req.OrganizationID, req.EnterpriseID)
	if err != nil {
		return evaluator.RepositoryResults{}, fmt.Errorf("%w: %w", ErrDependencyFetch, err)
	}

	logger.Debug("Loaded dependencies", kvp.Int("count", len(deps)))

	// Evaluate the policy against the dependencies
	results := evaluator.PolicyResultsForRepository(deps, policy, req.Context, logger)
	logger.Debug("Policy evaluation completed", kvp.Int("success_count", results.SuccessCount), kvp.Int("failure_count", results.FailureCount), kvp.Int("error_count", results.ErrorCount))

	// Get existing check job record for repository and pull request
	checkJob, err := c.storage.GetCheckJob(ctx, req.RepositoryID, req.PullRequestNumber)
	if err != nil && !errors.Is(err, storage.ErrNotFound) {
		return evaluator.RepositoryResults{}, err
	}

	// Only update alerts if there are no new commits for pull request (commit and base SHAs are the same)
	if checkJob != nil && checkJob.CommitSHA == req.CommitSHA && checkJob.BaseSHA == req.BaseSHA {
		if err := c.UpdateAlerts(ctx, results, req, policy.GetRemediationGuidance()); err != nil {
			return evaluator.RepositoryResults{}, fmt.Errorf("%w: %w", ErrAlertUpdate, err)
		}
	}

	return results, nil
}
