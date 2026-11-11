package storage

import (
	"context"
	"database/sql"
	"encoding/json"
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

func (s *Storage) safeRollback(tx *sql.Tx) {
	if rollbackErr := tx.Rollback(); rollbackErr != nil {
		s.logger.Error("failed to rollback transaction", kvp.Err(rollbackErr))
	}
}

// CreateAlert creates a new alert in the database based on the provided alert model.
// Returns the created alert with populated ID, Number, and CreatedAt fields.
func (s *Storage) CreateAlert(ctx context.Context, alertInfo models.Alert) (*models.Alert, error) {
	number, err := s.sequenceGen.Next(ctx, alertInfo.RepositoryID)
	if err != nil {
		return nil, fmt.Errorf("failed to generate alert number: %w", err)
	}

	// status will always be "open" on creation, except in tests
	status := alertInfo.Status.String()
	var resolution sql.NullString
	if alertInfo.Resolution != nil {
		resolution.String = alertInfo.Resolution.String()
		resolution.Valid = true
	} else {
		resolution.Valid = false
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
			pull_request_number
		)
		VALUES (
			?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
		)
	`

	result, err := s.db.ExecContext(ctx, query, number, status, resolution, createdAt, alertInfo.RepositoryID,
		alertInfo.OrganizationID, alertInfo.EnterpriseID, alertInfo.ManifestName, alertInfo.ManifestLineNumber,
		alertInfo.PackageEcosystem, alertInfo.PackageName, alertInfo.PackageVersion, alertInfo.SPDXLicenseExpression,
		alertInfo.PullRequestNumber)
	if err != nil {
		return nil, fmt.Errorf("failed to insert alert: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("failed to get inserted alert ID: %w", err)
	}

	if s.metrics != nil && alertInfo.Status == models.Open {
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

	return &createdAlert, nil
}

// GetAlert retrieves an alert by its number and repository ID.
func (s *Storage) GetAlert(ctx context.Context, repositoryID uint64, number uint32) (*models.Alert, error) {
	query := `
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
			pull_request_number
		FROM olc_alerts
		WHERE repository_id = ?
		AND number = ?
	`

	alert := &models.Alert{}
	var status string
	var resolution sql.NullString

	err := s.db.QueryRowContext(ctx, query, repositoryID, number).Scan(
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
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	alert.SetStatusAndResolution(status, resolution)

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
			spdx_license_expression, pull_request_number
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

	whereSQL, whereValue := scope.toWhereClause()

	// Build OR conditions for multiple licenses
	licenseConditions := make([]string, len(licenses))
	args := []any{whereValue}
	for i, license := range licenses {
		licenseConditions[i] = "spdx_license_expression LIKE ? ESCAPE ?"
		escapedLicense := escapeLikePattern(license)
		args = append(args, "%"+escapedLicense+"%", "!")
	}

	sqlQuery := fmt.Sprintf(getBaseAlertQuery()+`
		  %s
		  AND status != 'closed'
		  AND (%s)`, whereSQL, strings.Join(licenseConditions, " OR "))

	rows, err := s.db.QueryContext(ctx, sqlQuery, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to query alerts by licenses: %w", err)
	}
	defer rows.Close()

	return s.rowsToAlerts(rows, withLicensesFilter(licenses))
}

// GetOpenAlertsByPackage retrieves open alerts that match a specific package name.
func (s *Storage) GetOpenAlertsByPackage(ctx context.Context, ecosystem proto.PackageManager, packageName string, scope AlertScope) ([]*models.Alert, error) {
	start := time.Now()
	s.metrics.DistributionMs("storage.get_open_alerts.duration", stats.Tags{"method": "GetOpenAlertsByPackage"}, time.Since(start))
	whereSQL, whereValue := scope.toWhereClause()

	sqlQuery := fmt.Sprintf(getBaseAlertQuery()+`
		  %s
		  AND status != 'closed'
		  AND package_ecosystem = ?`, whereSQL)

	// Look for the * character in packageName and use LIKE if present
	var args []any
	if strings.Contains(packageName, "*") {
		escapedPattern := escapeLikePattern(packageName)
		// Replace the * wildcard with % for SQL LIKE. We only support a single * wildcard for simplicity.
		likePattern := strings.ReplaceAll(escapedPattern, "*", "%")
		sqlQuery += " AND package_name LIKE ? ESCAPE ?"
		args = []any{
			whereValue,
			ecosystem,
			likePattern,
			"!",
		}
	} else {
		sqlQuery += " AND package_name = ?"
		args = []any{
			whereValue,
			ecosystem,
			packageName,
		}
	}

	rows, err := s.db.QueryContext(ctx, sqlQuery, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to query alerts by package: %w", err)
	}
	defer rows.Close()

	return s.rowsToAlerts(rows)
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

		err := rows.Scan(
			&alert.ID, &alert.Number, &statusStr, &resolution,
			&alert.CreatedAt, &alert.RepositoryID, &alert.OrganizationID,
			&alert.EnterpriseID, &alert.ManifestName, &alert.ManifestLineNumber,
			&alert.PackageEcosystem, &alert.PackageName, &alert.PackageVersion,
			&alert.SPDXLicenseExpression, &alert.PullRequestNumber,
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
		alerts = append(alerts, alert)
	}

	if err := rows.Err(); err != nil {
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

// CloseAlertWithEvent updates the status of an alert to closed, sets its resolution, and creates an alert event in the same transaction.
// The eventBody parameter can be any type that is JSON-marshalable (e.g., models.ExceptionAddedEventBody, models.LicensesAddedEventBody, or nil for empty body).
func (s *Storage) CloseAlertWithEvent(ctx context.Context, alert *models.Alert, userID *uint64, resolution models.AlertResolution, eventBody any) (err error) {
	closeAlertQuery := `
		UPDATE olc_alerts
		SET status = ?, resolution = ?
		WHERE repository_id = ? AND number = ?
	`

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}

	defer func() {
		if err != nil {
			s.safeRollback(tx)
		}
	}()

	// Close alert status using transaction
	res, err := tx.ExecContext(ctx, closeAlertQuery, models.Closed.String(), resolution.String(), alert.RepositoryID, alert.Number)
	if err != nil {
		return fmt.Errorf("failed to close alert: %w", err)
	}

	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected when closing alert: %w", err)
	}
	// Don't error if no rows affected — alert could be closed already
	if rowsAffected == 0 {
		s.logger.Info("alert is already closed", kvp.Uint32("number", alert.Number), kvp.Uint64("repositoryID", alert.RepositoryID))
		return nil
	}

	// Marshal event body to JSON
	var eventBodyJSON json.RawMessage
	if eventBody == nil {
		eventBodyJSON = json.RawMessage("{}")
	} else {
		eventBodyJSON, err = json.Marshal(eventBody)
		if err != nil {
			return fmt.Errorf("failed to marshal event body: %w", err)
		}
	}

	// Create alert event using transaction
	_, err = tx.ExecContext(ctx, CreateAlertEventQuery, alert.ID, models.EventClosed.String(), userID, time.Now(), eventBodyJSON)
	if err != nil {
		return fmt.Errorf("failed to create close event: %w", err)
	}

	// Commit transaction
	if err = tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	if s.metrics != nil {
		s.metrics.Counter("storage.alerts.closed", stats.Tags{
			"resolution": resolution.String(),
		}, 1)
	}

	return nil
}

// GetOpenAlerts retrieves all open alerts for a specific repository and pull request, grouped by package key (ecosystem-name-version-license).
func (s *Storage) GetOpenAlerts(ctx context.Context, repositoryID uint64, pullRequestNumber *uint32) (map[string][]*models.Alert, error) {
	query := `
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
			pull_request_number
	FROM olc_alerts
		WHERE repository_id = ? AND pull_request_number = ? AND status != 'closed'
	`

	openAlertsMap := make(map[string][]*models.Alert)

	rows, err := s.db.QueryContext(ctx, query, repositoryID, pullRequestNumber)
	if err != nil {
		return nil, fmt.Errorf("failed to query open alerts: %w", err)
	}
	defer rows.Close()

	// Iterate through all rows and add them to the open alert map
	for rows.Next() {
		alert := &models.Alert{}
		var status string
		var resolution sql.NullString

		err := rows.Scan(
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
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan alert row: %w", err)
		}

		alert.SetStatusAndResolution(status, resolution)

		key := CreatePackageKey(models.PackageManagerToString(alert.PackageEcosystem), alert.PackageName, alert.SPDXLicenseExpression)
		openAlertsMap[key] = append(openAlertsMap[key], alert)
	}

	// Catches errors during row iteration
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating over alert rows: %w", err)
	}

	return openAlertsMap, nil
}

// CreatePackageKey creates a key by concatenating package information (ecosystem, name, version, and license)
func CreatePackageKey(packageEcosystem, packageName, license string) string {
	return fmt.Sprintf("%s-%s-%s", packageEcosystem, packageName, license)
}

// ErrStatusChangeNotAllowed is returned when an attempt to change the status of an alert is not allowed.
var ErrStatusChangeNotAllowed = errors.New("status change not allowed")

// UpdateAlertStatusWithEvent updates the status of an alert, ensuring valid status transitions, and creates an alert event.
func (s *Storage) UpdateAlertStatusWithEvent(ctx context.Context, alert *models.Alert, newStatus models.AlertStatus, eventType models.AlertEventType, eventBody json.RawMessage, userID *uint64) (err error) {
	alertUpdateQuery := `
		UPDATE olc_alerts
		SET status = ?
		WHERE repository_id = ? 
		AND number = ? 
		AND status = ?
	`

	// Guard against invalid status transitions
	var allowedPrevStatus models.AlertStatus
	switch newStatus {
	case models.ReviewDenied:
		allowedPrevStatus = models.ReviewRequested
	case models.ReviewRequested:
		allowedPrevStatus = models.Open
	case models.Open:
		allowedPrevStatus = models.ReviewRequested
	default:
		// The CloseAlert method should be used to update to the close status
		return fmt.Errorf("status change to %s not allowed", newStatus.String())
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}

	defer func() {
		if err != nil {
			s.safeRollback(tx)
		}
	}()

	// Update alert status using transaction
	result, err := tx.ExecContext(ctx, alertUpdateQuery, newStatus.String(), alert.RepositoryID, alert.Number, allowedPrevStatus.String())
	if err != nil {
		return fmt.Errorf("failed to update alert status: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}
	if rowsAffected == 0 {
		return ErrStatusChangeNotAllowed
	}

	// Create alert event using transaction
	_, err = tx.ExecContext(ctx, CreateAlertEventQuery, alert.ID, eventType.String(), userID, time.Now(), eventBody)
	if err != nil {
		return fmt.Errorf("failed to create alert event: %w", err)
	}

	// Commit transaction
	if err = tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	if s.metrics != nil {
		s.metrics.Counter("storage.alerts.status_updated", stats.Tags{
			"new_status": newStatus.String(),
		}, 1)
	}

	return nil
}

// GetReviewableAlertsForOrgOrEnterprise retrieves all alerts with status "ReviewRequested" for a given organization or enterprise.
// Only one of organizationID or enterpriseID should be provided (non-zero).
func (s *Storage) GetReviewableAlertsForOrgOrEnterprise(ctx context.Context, organizationID, enterpriseID uint64) ([]*models.Alert, error) {
	query := `
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
			pull_request_number
		FROM olc_alerts
		WHERE status = 'review_requested'
	`

	var idArg uint64
	switch {
	case organizationID != 0 && enterpriseID != 0:
		return nil, errors.New("only one of organizationID or enterpriseID should be provided")
	case organizationID != 0:
		query += " AND organization_id = ?"
		idArg = organizationID
	case enterpriseID != 0:
		query += " AND enterprise_id = ?"
		idArg = enterpriseID
	default:
		return nil, errors.New("either organizationID or enterpriseID must be provided")
	}

	rows, err := s.db.QueryContext(ctx, query, idArg)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var alerts []*models.Alert
	for rows.Next() {
		alert := &models.Alert{}
		var status string
		var resolution sql.NullString
		if err := rows.Scan(
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
		); err != nil {
			return nil, err
		}
		alert.Status = models.AlertStatusFromString(status)
		if resolution.Valid {
			alert.Resolution = models.AlertResolutionPtrFromString(resolution.String)
		} else {
			alert.Resolution = nil
		}
		alerts = append(alerts, alert)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return alerts, nil
}
