// Package suggestedfixes contains the suggested fixes db service.
package suggestedfixes

import (
	"context"
	"strings"
	"time"

	"github.com/jinzhu/gorm"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/github/turboscan/ts/proto"
	"github.com/pkg/errors"
)

type Service struct {
	db *gorm.DB
}

func NewService(db *gorm.DB) *Service {
	as := &Service{
		db: db,
	}
	return as
}

func (s *Service) GetSuggestedFixAlert(ctx context.Context, sfaID ts.SuggestedFixAlertID, opt *ts.FindOptions) (*ts.SuggestedFixAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	sfa := &ts.SuggestedFixAlert{}
	q := db.Where("id = ?", sfaID)
	q = opt.Apply(q)
	err := q.
		First(sfa).Error
	if err != nil {
		return nil, err
	}

	return sfa, nil
}

func (s *Service) GetSuggestedFixAlerts(ctx context.Context, repoID ts.RepositoryEID, alertNumbers []uint32, refs [][]byte) ([]ts.SuggestedFixAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	sfAlerts := []ts.SuggestedFixAlert{}
	sfaIds := []ts.SuggestedFixAlertID{}
	err := db.Table("ts_suggested_fix_alerts").
		Select("logical_alert_number, max(id)").
		Where("logical_alert_number IN (?) AND repository_id = ? AND ref_bytes IN (?)", alertNumbers, repoID, refs).
		Group("logical_alert_number").
		Pluck("max(id)", &sfaIds).Error
	if err != nil {
		return nil, err
	}
	if len(sfaIds) == 0 {
		return sfAlerts, nil
	}

	err = db.Model(&ts.SuggestedFixAlert{}).
		Where("id in (?)", sfaIds).
		Preload("SuggestedFix", "repository_id = ?", repoID).
		Preload("SuggestedFix.Files", "repository_id = ?", repoID).
		Order("ts_suggested_fix_alerts.created_at").
		Find(&sfAlerts).Error

	if err != nil {
		return nil, err
	}

	return sfAlerts, nil
}

func (s *Service) GetAllSuggestedFixAlertsByRefs(ctx context.Context, repoID ts.RepositoryEID, refs [][]byte) ([]ts.SuggestedFixAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	sfAlerts := []ts.SuggestedFixAlert{}
	err := db.Model(&ts.SuggestedFixAlert{}).
		Where("repository_id = ? AND ref_bytes IN (?)", repoID, refs).
		Preload("SuggestedFix", "repository_id = ?", repoID).
		Preload("SuggestedFix.Files", "repository_id = ?", repoID).
		Order("ts_suggested_fix_alerts.created_at").
		Find(&sfAlerts).Error

	if err != nil {
		return nil, err
	}

	return sfAlerts, nil
}

type FileInfo struct {
	Filepath     string
	FileChecksum ts.Sha1Checksum
}

func (s *Service) CreateSuggestedFix(ctx context.Context, sfa *ts.SuggestedFixAlert) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	err := db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(sfa).Error; err != nil {
			return err
		}
		return nil
	})

	return err
}

// FindInvalidSuggestedFix a SuggestedFixAlert for which no fix was found
func (s *Service) FindInvalidSuggestedFix(ctx context.Context, repoID ts.RepositoryEID, alertNo uint32) (*ts.SuggestedFixAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	sfa := &ts.SuggestedFixAlert{}
	sq := db.
		Select("MAX(ts_suggested_fix_alerts.id) as sf_alert_id").
		Table("ts_suggested_fix_alerts").
		Where("ts_suggested_fix_alerts.repository_id = ?", repoID).
		Where("ts_suggested_fix_alerts.logical_alert_number = ?", alertNo).
		Where("ts_suggested_fix_alerts.state = ?", ts.SuggestedFixAlertStateInvalid).QueryExpr()

	err := db.Model(&ts.SuggestedFixAlert{}).
		Where("ts_suggested_fix_alerts.id = (?)", sq).
		Preload("SuggestedFix", "repository_id = ?", repoID).
		First(&sfa).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}

	return sfa, nil
}

// FindSuggestedFixAlertsWithFixes returns the SuggestedFixAlerts for the given repository and alert numbers
// It returns the latest SuggestedFixAlerts for each alert number that contain a suggested fix
func (s *Service) FindSuggestedFixAlertsWithFixes(ctx context.Context, repoID ts.RepositoryEID, alertNOs []uint32, ref []byte) (results []*ts.SuggestedFixAlert, err error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	sq := db.
		Select("MAX(ts_suggested_fix_alerts.id) as sf_alert_id, ts_suggested_fix_alerts.logical_alert_number").
		Table("ts_suggested_fix_alerts").
		Where("ts_suggested_fix_alerts.repository_id = ?", repoID).
		Where("ts_suggested_fix_alerts.logical_alert_number IN (?)", alertNOs).
		Where("ts_suggested_fix_alerts.ref_bytes = ?", ref).
		Where("ts_suggested_fix_alerts.suggested_fix_id IS NOT NULL").
		Group("ts_suggested_fix_alerts.repository_id, ts_suggested_fix_alerts.logical_alert_number").
		QueryExpr()
	err = db.Model(&ts.SuggestedFixAlert{}).
		Joins("INNER JOIN (?) sq ON sq.sf_alert_id = ts_suggested_fix_alerts.id", sq).
		Preload("SuggestedFix", "repository_id = ?", repoID).
		Find(&results).Error
	if err != nil {
		return nil, err
	}
	return
}

type StatisticsFilter struct {
	OwnerIds       []uint64
	RepositoryIds  []uint64
	RuleIds        []string
	ExcludeRuleIds []string
	Severities     []proto.Severity
	Start          time.Time
	End            time.Time
}

func (s *Service) GetSuggestedFixStatistics(ctx context.Context, filter StatisticsFilter) (*ts.SuggestedFixStatistics, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	var totalSuggested uint64
	q := db.Model(&ts.SuggestedFixAlert{})

	var severityClauses []string
	var severityArgs []any

	if len(filter.RuleIds) > 0 {
		q = q.Where("ts_suggested_fix_alerts.rule_sarif_identifier in (?)", filter.RuleIds)
	}

	if len(filter.ExcludeRuleIds) > 0 {
		q = q.Where("ts_suggested_fix_alerts.rule_sarif_identifier not in (?)", filter.ExcludeRuleIds)
	}

	if len(filter.RepositoryIds) > 0 {
		q = q.Where("ts_suggested_fix_alerts.repository_id in (?)", filter.RepositoryIds)
	}

	if len(filter.OwnerIds) > 0 {
		q = q.Joins("INNER JOIN ts_repositories on ts_suggested_fix_alerts.repository_id = ts_repositories.repository_id")
		q = q.Where("ts_repositories.owner_id in (?)", filter.OwnerIds)
	}

	q = q.Where("ts_suggested_fix_alerts.suggested_fix_id IS NOT NULL")
	q = q.Where("ts_suggested_fix_alerts.created_at >= ? AND ts_suggested_fix_alerts.created_at < ?", filter.Start, filter.End)

	if len(filter.Severities) > 0 {
		q = q.Joins("INNER JOIN ts_logical_alerts ON ts_logical_alerts.repository_id = ts_suggested_fix_alerts.repository_id AND ts_logical_alerts.number = ts_suggested_fix_alerts.logical_alert_number")

		for _, severity := range filter.Severities {
			sc, args := severityFilter(severity)
			severityClauses = append(severityClauses, sc)
			severityArgs = append(severityArgs, args...)
		}
		orClause := strings.Join(severityClauses, " OR ")
		q = q.Where(orClause, severityArgs...)
	}

	err := q.
		Select("ts_suggested_fix_alerts.repository_id, ts_suggested_fix_alerts.logical_alert_number, min(ts_suggested_fix_alerts.id)").
		Group("ts_suggested_fix_alerts.repository_id, ts_suggested_fix_alerts.logical_alert_number").
		Count(&totalSuggested).Error
	if err != nil {
		return nil, err
	}

	res := ts.SuggestedFixStatistics{
		TotalSuggested: totalSuggested,
	}

	return &res, nil
}

func (s *Service) UpdateSFA(ctx context.Context, sfa *ts.SuggestedFixAlert) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	if sfa.ID == 0 {
		return errors.New("object does not specify a valid ID")
	}

	return db.Save(sfa).Error
}

func severityFilter(severity proto.Severity) (string, []any) {
	// We explicitly require the Security Severity to be NOT NULL because otherwise, the negated version of this query will return null instead of true/false.
	var args []any
	switch severity {
	case proto.Severity_SEVERITY_CRITICAL:
		return "(ts_logical_alerts.security_severity IS NOT NULL AND 9 <= ts_logical_alerts.security_severity AND ts_logical_alerts.security_severity <= 10)", args
	case proto.Severity_SEVERITY_HIGH:
		return "(ts_logical_alerts.security_severity IS NOT NULL AND 7 <= ts_logical_alerts.security_severity AND ts_logical_alerts.security_severity < 9)", args
	case proto.Severity_SEVERITY_MEDIUM:
		return "(ts_logical_alerts.security_severity IS NOT NULL AND 4 <= ts_logical_alerts.security_severity AND ts_logical_alerts.security_severity < 7)", args
	case proto.Severity_SEVERITY_LOW:
		return "(ts_logical_alerts.security_severity IS NOT NULL AND 0 <= ts_logical_alerts.security_severity AND ts_logical_alerts.security_severity < 4)", args
	case proto.Severity_SEVERITY_ERROR:
		return ruleSeverityFilter(ts.SeverityLevelError)
	case proto.Severity_SEVERITY_WARNING:
		return ruleSeverityFilter(ts.SeverityLevelWarning)
	case proto.Severity_SEVERITY_NOTE:
		return ruleSeverityFilter(ts.SeverityLevelNote)
	case proto.Severity_NO_SEVERITY:
		return "", args
	}

	return "", args
}

func ruleSeverityFilter(ruleSeverity ts.SeverityLevel) (string, []any) {
	// Security severity must be empty or invalid for rule severity to apply.
	filterSecuritySeverity := `
	(ts_logical_alerts.security_severity IS NULL
     OR ts_logical_alerts.security_severity <= 0
	 OR 10 < ts_logical_alerts.security_severity)`
	filterRuleSeverity := "(ts_logical_alerts.severity_level = ?)"

	return "(" + filterSecuritySeverity + " AND " + filterRuleSeverity + ")", []any{int(ruleSeverity)}
}
