package storage

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-spdx/v2/spdxexp"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

// AlertHook is a function that is called after an alert is modified but before the transaction is committed.
// It receives the updated alert and can perform additional operations like publishing events.
// If the hook returns an error, the transaction will be rolled back.
type AlertHook func(*models.Alert) error

// CreateAlert creates a new alert in the database based on the provided alert model.
// Returns the created alert with populated ID, Number, and CreatedAt fields.
func (s *Storage) CreateAlert(ctx context.Context, alertInfo models.Alert) (*models.Alert, error) {
	number, err := s.sequenceGen.Next(ctx, alertInfo.RepositoryID)
	if err != nil {
		return nil, fmt.Errorf("failed to generate alert number: %w", err)
	}

	// status will always be "open" on creation, except in tests
	status := alertInfo.Status.String()

	// Only set resolution if it's not Unknown (default zero value)
	// Open alerts have Unknown resolution (NULL in DB)
	var resolution sql.NullString
	if alertInfo.Resolution != models.AlertResolutionUnknown {
		resolution = sql.NullString{String: alertInfo.Resolution.String(), Valid: true}
	}
	createdAt := time.Now()

	// Insert the alert into the database
	query := `
		INSERT INTO olc_alerts (
			number,
			status,
			resolution,
			created_at,
			repository_id,
			organization_id,
			enterprise_id,
			manifest_name,
			manifest_line_number,
			package_ecosystem,
			package_name,
			package_version,
			spdx_license_expression,
			pull_request_number,
			package_repo_nwo,
			dismissal_reason
		)
		VALUES (
			?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
		)
	`

	result, err := s.db.ExecContext(ctx, query, number, status, resolution, createdAt, alertInfo.RepositoryID,
		alertInfo.OrganizationID, alertInfo.EnterpriseID, alertInfo.ManifestName, alertInfo.ManifestLineNumber,
		alertInfo.PackageEcosystem, alertInfo.PackageName, alertInfo.PackageVersion, alertInfo.SPDXLicenseExpression,
		alertInfo.PullRequestNumber, alertInfo.PackageRepoNWO, alertInfo.ClosureReason)
	if err != nil {
		return nil, fmt.Errorf("failed to insert alert: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("failed to get inserted alert ID: %w", err)
	}

	if s.metrics != nil && alertInfo.Status == models.AlertStatusOpen {
		s.metrics.Counter("storage.alerts.created", stats.Tags{
			"status":    "open",
			"ecosystem": models.PackageManagerToString(alertInfo.PackageEcosystem),
		}, 1)
	}

	// Return the created alert with populated fields
	createdAlert := alertInfo
	createdAlert.ID = uint64(id) // #nosec G115
	createdAlert.Number = number
	createdAlert.CreatedAt = createdAt
	createdAlert.Status = alertInfo.Status
	createdAlert.ClosureReason = alertInfo.ClosureReason

	return &createdAlert, nil
}

// GetAlert retrieves an alert by its number and repository ID.
func (s *Storage) GetAlert(ctx context.Context, repositoryID uint64, number uint32) (*models.Alert, error) {
	query := alertSelectQuery + `WHERE repository_id = ? AND number = ?`
	return s.scanAlert(s.db.QueryRowContext(ctx, query, repositoryID, number))
}

// GetAlertByID retrieves an alert by its unique ID.
func (s *Storage) GetAlertByID(ctx context.Context, alertID uint64) (*models.Alert, error) {
	query := alertSelectQuery + `WHERE id = ?`
	return s.scanAlert(s.db.QueryRowContext(ctx, query, alertID))
}

const alertSelectQuery = `
	SELECT
		id,
		number,
		status,
		resolution,
		created_at,
		repository_id,
		organization_id,
		enterprise_id,
		manifest_name,
		manifest_line_number,
		package_ecosystem,
		package_name,
		package_version,
		spdx_license_expression,
		pull_request_number,
		package_repo_nwo,
		dismissal_reason
	FROM olc_alerts
`

func (s *Storage) scanAlert(row *sql.Row) (*models.Alert, error) {
	alert := &models.Alert{}
	var status string
	var resolution sql.NullString
	var packageRepoNWO sql.NullString
	var dismissalReason sql.NullString

	err := row.Scan(
		&alert.ID,
		&alert.Number,
		&status,
		&resolution,
		&alert.CreatedAt,
		&alert.RepositoryID,
		&alert.OrganizationID,
		&alert.EnterpriseID,
		&alert.ManifestName,
		&alert.ManifestLineNumber,
		&alert.PackageEcosystem,
		&alert.PackageName,
		&alert.PackageVersion,
		&alert.SPDXLicenseExpression,
		&alert.PullRequestNumber,
		&packageRepoNWO,
		&dismissalReason,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	alert.SetStatusAndResolution(status, resolution)
	if packageRepoNWO.Valid {
		alert.PackageRepoNWO = packageRepoNWO.String
	}
	if dismissalReason.Valid {
		alert.ClosureReason = &dismissalReason.String
	}

	return alert, nil
}

// AlertScope defines the scope for querying alerts (repository, organization, or enterprise).
type AlertScope struct {
	scopeType string
	value     uint64
}

// NewRepositoryScope returns an AlertScope that filters alerts by repository ID.
func NewRepositoryScope(id uint64) AlertScope {
	return AlertScope{scopeType: "repository_id", value: id}
}

// NewOrganizationScope returns an AlertScope that filters alerts by organization ID.
func NewOrganizationScope(id uint64) AlertScope {
	return AlertScope{scopeType: "organization_id", value: id}
}

// NewEnterpriseScope returns an AlertScope that filters alerts by enterprise ID.
func NewEnterpriseScope(id uint64) AlertScope {
	return AlertScope{scopeType: "enterprise_id", value: id}
}

// toWhereClause restricts the scope where clause to statements defined in this
// package.
func (s AlertScope) toWhereClause() (clause string, value uint64) {
	switch s.scopeType {
	case "repository_id":
		return "repository_id = ?", s.value
	case "organization_id":
		return "organization_id = ?", s.value
	case "enterprise_id":
		return "enterprise_id = ?", s.value
	default:
		return "", 0
	}
}

func getBaseAlertQuery() string {
	return `
		SELECT DISTINCT
			id, number, status, resolution, created_at,
			repository_id, organization_id, enterprise_id,
			manifest_name, manifest_line_number,
			package_ecosystem, package_name, package_version,
			spdx_license_expression, pull_request_number, package_repo_nwo,
			dismissal_reason
		FROM olc_alerts
		WHERE
	`
}

// GetOpenAlertsByLicenses retrieves alerts that match any of the provided SPDX license expressions,
// Using Indexes on repo, org and enterprise ids
func (s *Storage) GetOpenAlertsByLicenses(ctx context.Context, licenses []string, scope AlertScope) ([]*models.Alert, error) {
	start := time.Now()
	defer func() {
		s.metrics.DistributionMs("storage.get_open_alerts.duration", stats.Tags{"method": "GetOpenAlertsByLicenses"}, time.Since(start))
	}()

	if len(licenses) == 0 {
		return []*models.Alert{}, nil
	}

	return s.GetAlerts(ctx, WithScope(scope), WithLicenses(licenses))
}

// GetOpenAlertsByPackage retrieves open alerts that match a specific package name.
func (s *Storage) GetOpenAlertsByPackage(ctx context.Context, ecosystem proto.PackageManager, packageName string, scope AlertScope) ([]*models.Alert, error) {
	start := time.Now()
	s.metrics.DistributionMs("storage.get_open_alerts.duration", stats.Tags{"method": "GetOpenAlertsByPackage"}, time.Since(start))

	return s.GetAlerts(ctx, WithScope(scope), WithPackage(ecosystem, packageName))
}

// AlertQueryOption is a function that modifies an alert query.
type AlertQueryOption func(*alertQueryOptions)

// alertQueryOptions holds the configuration for querying alerts.
type alertQueryOptions struct {
	scope             *AlertScope
	statuses          []models.AlertStatus
	licenses          []string
	packageEcosystem  *proto.PackageManager
	packageName       *string
	pullRequestNumber *uint32
	repositoryID      *uint64
	organizationID    *uint64
	enterpriseID      *uint64
	licenseFilter     bool
}

// WithScope filters alerts by repository, organization, or enterprise.
func WithScope(scope AlertScope) AlertQueryOption {
	return func(opts *alertQueryOptions) {
		opts.scope = &scope
	}
}

// WithStatuses filters alerts by status. If empty, excludes closed alerts by default.
func WithStatuses(statuses ...models.AlertStatus) AlertQueryOption {
	return func(opts *alertQueryOptions) {
		opts.statuses = statuses
	}
}

// WithLicenses filters alerts by SPDX license expressions.
func WithLicenses(licenses []string) AlertQueryOption {
	return func(opts *alertQueryOptions) {
		opts.licenses = licenses
		opts.licenseFilter = true
	}
}

// WithPackage filters alerts by package ecosystem and name.
func WithPackage(ecosystem proto.PackageManager, packageName string) AlertQueryOption {
	return func(opts *alertQueryOptions) {
		opts.packageEcosystem = &ecosystem
		opts.packageName = &packageName
	}
}

// WithPullRequest filters alerts by pull request number.
func WithPullRequest(pullRequestNumber uint32) AlertQueryOption {
	return func(opts *alertQueryOptions) {
		opts.pullRequestNumber = &pullRequestNumber
	}
}

// WithRepositoryID filters alerts by repository ID.
func WithRepositoryID(repositoryID uint64) AlertQueryOption {
	return func(opts *alertQueryOptions) {
		opts.repositoryID = &repositoryID
	}
}

// WithOrganizationID filters alerts by organization ID.
func WithOrganizationID(organizationID uint64) AlertQueryOption {
	return func(opts *alertQueryOptions) {
		opts.organizationID = &organizationID
	}
}

// WithEnterpriseID filters alerts by enterprise ID.
func WithEnterpriseID(enterpriseID uint64) AlertQueryOption {
	return func(opts *alertQueryOptions) {
		opts.enterpriseID = &enterpriseID
	}
}

// GetAlerts retrieves alerts based on the provided query options.
func (s *Storage) GetAlerts(ctx context.Context, options ...AlertQueryOption) ([]*models.Alert, error) {
	opts := &alertQueryOptions{}
	for _, opt := range options {
		opt(opts)
	}

	query := getBaseAlertQuery()
	args := []any{}
	whereClauses := []string{}

	// Apply scope filter
	if opts.scope != nil {
		whereSQL, whereValue := opts.scope.toWhereClause()
		if whereSQL != "" {
			whereClauses = append(whereClauses, whereSQL)
			args = append(args, whereValue)
		}
	}

	// Apply repository ID filter
	if opts.repositoryID != nil {
		whereClauses = append(whereClauses, "repository_id = ?")
		args = append(args, *opts.repositoryID)
	}

	// Apply organization ID filter
	if opts.organizationID != nil {
		whereClauses = append(whereClauses, "organization_id = ?")
		args = append(args, *opts.organizationID)
	}

	// Apply enterprise ID filter
	if opts.enterpriseID != nil {
		whereClauses = append(whereClauses, "enterprise_id = ?")
		args = append(args, *opts.enterpriseID)
	}

	// Apply status filters
	if len(opts.statuses) > 0 {
		statusPlaceholders := make([]string, len(opts.statuses))
		for i, status := range opts.statuses {
			statusPlaceholders[i] = "?"
			args = append(args, status.String())
		}
		whereClauses = append(whereClauses, fmt.Sprintf("status IN (%s)", strings.Join(statusPlaceholders, ", ")))
	} else {
		// Default: exclude closed alerts
		whereClauses = append(whereClauses, "status != 'closed'")
	}

	// Apply pull request filter
	if opts.pullRequestNumber != nil {
		whereClauses = append(whereClauses, "pull_request_number = ?")
		args = append(args, *opts.pullRequestNumber)
	}

	// Apply package filters
	if opts.packageEcosystem != nil {
		whereClauses = append(whereClauses, "package_ecosystem = ?")
		args = append(args, *opts.packageEcosystem)
	}

	if opts.packageName != nil {
		if strings.Contains(*opts.packageName, "*") {
			escapedPattern := escapeLikePattern(*opts.packageName)
			likePattern := strings.ReplaceAll(escapedPattern, "*", "%")
			whereClauses = append(whereClauses, "package_name LIKE ? ESCAPE ?")
			args = append(args, likePattern, "!")
		} else {
			whereClauses = append(whereClauses, "package_name = ?")
			args = append(args, *opts.packageName)
		}
	}

	// Apply license filters (using LIKE for SQL matching)
	if len(opts.licenses) > 0 {
		licenseConditions := make([]string, len(opts.licenses))
		for i, license := range opts.licenses {
			licenseConditions[i] = "spdx_license_expression LIKE ? ESCAPE ?"
			escapedLicense := escapeLikePattern(license)
			args = append(args, "%"+escapedLicense+"%", "!")
		}
		whereClauses = append(whereClauses, fmt.Sprintf("(%s)", strings.Join(licenseConditions, " OR ")))
	}

	// Build final query
	query += strings.Join(whereClauses, " AND ")

	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to query alerts: %w", err)
	}
	defer func() {
		err := rows.Close()
		if err != nil {
			s.logger.Error("failed to close alert rows in GetAlerts", kvp.Err(err))
		}
	}()

	// Apply post-query license filter if needed
	var filters []alertFilter
	if opts.licenseFilter && len(opts.licenses) > 0 {
		filters = append(filters, withLicensesFilter(opts.licenses))
	}

	return s.rowsToAlerts(rows, filters...)
}

type alertFilter func(*models.Alert) (bool, error)

// withLicensesFilter checks if the alert's SPDX license expression includes any of the specified licenses.
func withLicensesFilter(licenses []string) alertFilter {
	return func(alert *models.Alert) (bool, error) {
		alertLicenses, err := spdxexp.ExtractLicenses(alert.SPDXLicenseExpression)
		if err != nil {
			return false, fmt.Errorf("failed to extract licenses from expression %q: %w", alert.SPDXLicenseExpression, err)
		}
		for _, license := range licenses {
			for _, alertLicense := range alertLicenses {
				if strings.EqualFold(alertLicense, license) {
					return true, nil
				}
			}
		}
		return false, nil
	}
}

func (s *Storage) rowsToAlerts(rows *sql.Rows, filters ...alertFilter) ([]*models.Alert, error) {
	var alerts []*models.Alert
	for rows.Next() {
		alert := &models.Alert{}
		var statusStr string
		var resolution sql.NullString
		var packageRepoNWO sql.NullString
		var closureReason sql.NullString

		err := rows.Scan(
			&alert.ID, &alert.Number, &statusStr, &resolution,
			&alert.CreatedAt, &alert.RepositoryID, &alert.OrganizationID,
			&alert.EnterpriseID, &alert.ManifestName, &alert.ManifestLineNumber,
			&alert.PackageEcosystem, &alert.PackageName, &alert.PackageVersion,
			&alert.SPDXLicenseExpression, &alert.PullRequestNumber, &packageRepoNWO,
			&closureReason,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan alert: %w", err)
		}

		shouldInclude := true
		for _, filter := range filters {
			include, err := filter(alert)
			if err != nil {
				s.logger.Error("error applying alert filter", kvp.Err(err), kvp.Uint64("alertID", alert.ID))
			}
			shouldInclude = include
		}

		if !shouldInclude {
			continue
		}

		alert.SetStatusAndResolution(statusStr, resolution)

		if packageRepoNWO.Valid {
			alert.PackageRepoNWO = packageRepoNWO.String
		}

		if closureReason.Valid {
			alert.ClosureReason = &closureReason.String
		}

		alerts = append(alerts, alert)
	}

	err := rows.Err()
	if err != nil {
		return nil, fmt.Errorf("error iterating alert rows: %w", err)
	}

	return alerts, nil
}

// escapeLikePattern escapes special LIKE wildcards (%, _) for use in SQL LIKE patterns.
// The escaped string must be used with ESCAPE '!' in the SQL query.
func escapeLikePattern(s string) string {
	s = strings.ReplaceAll(s, "!", "!!") // Escape the escape character first
	s = strings.ReplaceAll(s, "%", "!%") // Escape % wildcard
	s = strings.ReplaceAll(s, "_", "!_") // Escape _ wildcard
	return s
}

type closeAlertStep struct {
	alert *models.Alert
}

func (cas *closeAlertStep) Execute(ctx context.Context, tx *sql.Tx) error {
	updateQuery := `
		UPDATE olc_alerts
		SET status = ?, resolution = ?, dismissal_reason = ?
		WHERE repository_id = ? AND number = ?
	`
	_, err := tx.ExecContext(ctx, updateQuery, models.AlertStatusClosed.String(), cas.alert.Resolution.String(), cas.alert.ClosureReason, cas.alert.RepositoryID, cas.alert.Number)
	if err != nil {
		return fmt.Errorf("failed to close alert: %w", err)
	}
	return nil
}

// NewCloseAlertStep creates a step for closing an alert in the database and setting the resolution.
// This step does not change the alert model and uses the resolution provided on the alert struct.
func NewCloseAlertStep(alert *models.Alert) Step {
	return &closeAlertStep{
		alert: alert,
	}
}

// ErrConcurrentStatusChange is returned by transition alert steps when the alert status
// in the database doesn't match the expected previous status.
var ErrConcurrentStatusChange = errors.New("alert status has changed since it was last read; concurrent modification detected")

type transitionAlertStep struct {
	alert          *models.Alert
	previousStatus models.AlertStatus
}

func (tas *transitionAlertStep) Execute(ctx context.Context, tx *sql.Tx) error {
	alertUpdateQuery := `
		UPDATE olc_alerts
		SET status = ?, dismissal_reason = ?
		WHERE repository_id = ?
		AND number = ?
		AND status = ?
	`
	result, err := tx.ExecContext(ctx, alertUpdateQuery, tas.alert.Status.String(), tas.alert.ClosureReason, tas.alert.RepositoryID, tas.alert.Number, tas.previousStatus.String())
	if err != nil {
		return fmt.Errorf("failed to update alert status: %w", err)
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected for alert status update: %w", err)
	}
	if rows == 0 {
		return ErrConcurrentStatusChange
	}
	return nil
}

// NewTransitionAlertStep is used for transitioning an alert to a new status.
// You pass in the alert and the previousStatus. The previousStatus is used to
// ensure that the alert hasn't changed status since it was last read to avoid
// potentially invalid transitions.
// The new status is assumed to already be set on the alert.
// If you're closing an alert, use NewCloseAlert step instead.
func NewTransitionAlertStep(alert *models.Alert, previousStatus models.AlertStatus) Step {
	return &transitionAlertStep{
		alert:          alert,
		previousStatus: previousStatus,
	}
}

// GetOpenAlerts retrieves all open alerts for a specific repository and pull request, grouped by package key (ecosystem-name-version-license).
func (s *Storage) GetOpenAlerts(ctx context.Context, repositoryID uint64, pullRequestNumber *uint32) (map[string][]*models.Alert, error) {
	// Use GetAlerts to retrieve open alerts (default excludes closed)
	alerts, err := s.GetAlerts(ctx, WithRepositoryID(repositoryID), WithPullRequest(*pullRequestNumber))
	if err != nil {
		return nil, fmt.Errorf("failed to get alerts: %w", err)
	}

	// Group alerts by package key
	openAlertsMap := make(map[string][]*models.Alert)
	for _, alert := range alerts {
		key := CreatePackageKey(models.PackageManagerToString(alert.PackageEcosystem), alert.PackageName, alert.SPDXLicenseExpression)
		openAlertsMap[key] = append(openAlertsMap[key], alert)
	}

	return openAlertsMap, nil
}

// CreatePackageKey creates a key by concatenating package information (ecosystem, name, version, and license)
func CreatePackageKey(packageEcosystem, packageName, license string) string {
	return fmt.Sprintf("%s-%s-%s", packageEcosystem, packageName, license)
}

// GetReviewableAlertsForOrgOrEnterprise retrieves all alerts with status "ReviewRequested" for a given organization or enterprise.
// Only one of organizationID or enterpriseID should be provided (non-zero).
func (s *Storage) GetReviewableAlertsForOrgOrEnterprise(ctx context.Context, organizationID, enterpriseID uint64) ([]*models.Alert, error) {
	switch {
	case organizationID != 0 && enterpriseID != 0:
		return nil, errors.New("only one of organizationID or enterpriseID should be provided")
	case organizationID != 0:
		return s.GetAlerts(ctx, WithOrganizationID(organizationID), WithStatuses(models.AlertStatusReviewRequested))
	case enterpriseID != 0:
		return s.GetAlerts(ctx, WithEnterpriseID(enterpriseID), WithStatuses(models.AlertStatusReviewRequested))
	default:
		return nil, errors.New("either organizationID or enterpriseID must be provided")
	}
}

// GetAlertsForPullRequest retrieves all alerts for a specific repository and pull request number.
func (s *Storage) GetAlertsForPullRequest(ctx context.Context, repositoryID uint64, pullRequestNumber uint32) ([]*models.Alert, error) {
	// Include all statuses by explicitly passing them
	return s.GetAlerts(ctx,
		WithRepositoryID(repositoryID),
		WithPullRequest(pullRequestNumber),
		WithStatuses(models.AlertStatusOpen, models.AlertStatusReviewRequested, models.AlertStatusReviewDenied, models.AlertStatusClosed))
}
