package alert

import (
	"context"
	"sort"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cocofix"
	"github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/transforms"
	"github.com/jinzhu/gorm"
)

// DEFAULT_MAX_ALERTS_TO_LOAD is the maximum number of alerts to load for a single repository.
// This safety measure was introduced to prevent a single repo for monopolizing the ES indexer in a single run.
// See https://github.com/github/code-scanning/issues/10755 for more context.
const DEFAULT_MAX_ALERTS_TO_LOAD = 500000

const DEFAULT_BATCH_SIZE = 1000

// Loader is used to (bulk) load alerts for a repository from MySQL.
// This is useful when syncing alert information to Elasticsearch or Insights.
type Loader struct {
	db          *gorm.DB
	sfDBService *suggestedfixes.Service

	repo       *ts.Repository
	batchSize  int
	cutoff     *time.Time
	ids        []ts.LogicalAlertID
	numbers    []uint32
	lastNumber int
	alertCount int
	startTime  time.Time
	maxLoad    int
	maxTime    time.Duration
}

// NewLoader returns a new Loader instance for a specific repository.
// It will load alerts in batches of batchSize, and can filter them based on a cutoff date or a list of IDs.
func (s *Service) NewLoader(repo *ts.Repository) *Loader {
	return &Loader{
		db:          s.db,
		sfDBService: suggestedfixes.NewService(s.db),
		repo:        repo,
		batchSize:   DEFAULT_BATCH_SIZE,
		cutoff:      nil,
		ids:         nil,
		lastNumber:  0,
		alertCount:  0,
		maxLoad:     DEFAULT_MAX_ALERTS_TO_LOAD,
		maxTime:     0,
	}
}

// Repo returns the repository for the loader.
func (l *Loader) Repo() *ts.Repository {
	return l.repo
}

// SetBatchSize sets the batch size for the loader.
func (l *Loader) SetBatchSize(size int) {
	l.batchSize = size
}

// SetCutoff sets the cutoff date for the loader.
func (l *Loader) SetCutoff(cutoff *time.Time) {
	l.cutoff = cutoff
}

// SetIDs sets the list of alert IDs to load.
func (l *Loader) SetIDs(ids []ts.LogicalAlertID) {
	l.ids = ids
}

// SetNumbers sets the list of alert numbers to load.
func (l *Loader) SetNumbers(numbers []uint32) {
	l.numbers = numbers
}

// SetMaxLoad sets the maximum number of alerts to load.
func (l *Loader) SetMaxLoad(maxAlerts int) {
	l.maxLoad = maxAlerts
}

// SetMaxTime sets the maximum time to load alerts, this both
// counts the time spent loading and the time spent processing the alerts.
func (l *Loader) SetMaxTime(maxTime time.Duration) {
	l.maxTime = maxTime
}

// BatchedLoad loads alerts in batches and calls the provided process function for each batch.
func (l *Loader) BatchedLoad(ctx context.Context, process func([]*ts.LogicalAlert) error) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	for {
		logicalAlerts, err := l.NextBatch(ctx)
		if err != nil {
			return err
		}
		if len(logicalAlerts) == 0 {
			break
		}
		err = process(logicalAlerts)
		if err != nil {
			return err
		}
	}
	return nil
}

// NextBatch returns the next batch of alerts for the repository.
// The loader is stateful and will batch alerts based on alert number (in an ascending order).
func (l *Loader) NextBatch(ctx context.Context) ([]*ts.LogicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	var err error
	var logicalAlerts []*ts.LogicalAlert
	startTime := time.Now()
	if l.startTime.IsZero() {
		// The first load triggers the timer.
		l.startTime = startTime
	}

	// Check if we have loaded more than the maximum number of alerts,
	// or if we have spent more than the maximum time loading alerts.
	if l.maxExceeded(ctx) {
		return nil, nil
	}

	// Time to use in stats
	metricTime := time.Now()

	query := l.db.Table("ts_logical_alerts").
		Where("number > (?)", l.lastNumber).
		Where("repository_id = ?", l.repo.RepositoryID)
	query = preloadRules(query)
	query = preloadLinks(query)
	query = preloadSecurityCampaignAlerts(query)
	if l.cutoff != nil {
		query = query.Where("updated_at>?", l.cutoff)
	}
	if len(l.ids) > 0 {
		query = query.Where("id IN (?)", l.ids)
	}
	if len(l.numbers) > 0 {
		query = query.Where("number IN (?)", l.numbers)
	}
	err = query.Order("number").Limit(l.batchSize).Find(&logicalAlerts).Error
	if err != nil {
		return nil, err
	}
	appctx.Stats(ctx).DistributionMs("alert_loader.next_batch", stats.Tags{"kind": "logical_alerts"}, time.Since(metricTime))

	metricTime = time.Now()
	err = batchPreloadPhysicalAlerts(ctx, l.db, logicalAlerts, l.repo)
	if err != nil {
		return nil, err
	}
	appctx.Stats(ctx).DistributionMs("alert_loader.next_batch", stats.Tags{"kind": "physical_alerts"}, time.Since(metricTime))

	if len(logicalAlerts) == 0 {
		return logicalAlerts, nil
	}
	baselines := []ts.AnalysisID{}
	for _, l := range logicalAlerts {
		if len(l.PhysicalAlerts) > 0 {
			sort.Slice(l.PhysicalAlerts, func(i, j int) bool {
				t1 := l.PhysicalAlerts[i].CreatedAt.Time
				t2 := l.PhysicalAlerts[j].CreatedAt.Time
				return t1.After(t2) || (t1.Equal(t2) && l.PhysicalAlerts[i].ID > l.PhysicalAlerts[j].ID)
			})
			fixed := true
			for _, pa := range l.PhysicalAlerts {
				if !pa.IsFixed {
					fixed = false
					break
				}
				baselines = append(baselines, *pa.LastSeenAnalysisID)
			}
			l.IsFixed = &fixed
		}
	}

	// To populate the `fixed_at` date for the fixed alerts, we need to find the last analysis that
	// fixed an instance of the alert.
	// However, since we only have the LastSeenAnalysisID for each physical alert, a fixing analysis would
	// have to be one that has the LastSeenAnalysis as a baseline.
	if len(baselines) > 0 {
		metricTime = time.Now()
		var fixingAnalyses []*ts.Analysis
		err = l.db.Table("ts_analyses").
			Select("baseline_id, created_at").
			Where("repository_id = ?", l.repo.RepositoryID).
			Where("baseline_id IN (?)", baselines).
			Find(&fixingAnalyses).Error
		if err != nil {
			return nil, err
		}
		appctx.Stats(ctx).DistributionMs("alert_loader.next_batch", stats.Tags{"kind": "fixing_analyses"}, time.Since(metricTime))

		maxCreatedAtByBaseline := map[ts.AnalysisID]sqltime.Time{}
		for _, a := range fixingAnalyses {
			if fixedAt, ok := maxCreatedAtByBaseline[*a.BaselineID]; ok {
				if a.CreatedAt.After(fixedAt.Time) {
					maxCreatedAtByBaseline[*a.BaselineID] = a.CreatedAt
				}
			} else {
				maxCreatedAtByBaseline[*a.BaselineID] = a.CreatedAt
			}
		}

		for _, l := range logicalAlerts {
			if l.IsFixed == nil || !*l.IsFixed {
				continue
			}
			for _, p := range l.PhysicalAlerts {
				fixingAnalysisCreatedAt, ok := maxCreatedAtByBaseline[*p.LastSeenAnalysisID]
				fixedAt := l.GetFixedAt()
				if ok && (fixedAt == nil || fixedAt.Before(fixingAnalysisCreatedAt.Time)) {
					l.LastObservedFixAt = &fixingAnalysisCreatedAt
				}
			}
		}
	}

	// Autofix metadata
	numbers := transforms.Map(logicalAlerts, func(la *ts.LogicalAlert) uint32 { return la.Number })
	refs := [][]byte{l.repo.DefaultRef}
	metricTime = time.Now()
	sfas, err := l.sfDBService.GetSuggestedFixAlerts(ctx, l.repo.RepositoryID, numbers, refs)
	if err != nil {
		return nil, err
	}
	appctx.Stats(ctx).DistributionMs("alert_loader.next_batch", stats.Tags{"kind": "suggested_fix_alerts"}, time.Since(metricTime))
	sfaByNumber := transforms.IndexBy(sfas, func(sfa ts.SuggestedFixAlert) uint32 { return sfa.LogicalAlertNumber })
	for _, l := range logicalAlerts {
		l.AutofixEligible = cocofix.IsEligibleForAutoFix(ctx, l.RepositoryID, l)
		if sfa, ok := sfaByNumber[l.Number]; ok {
			l.SuggestedFixAlert = &sfa
		}
	}

	l.alertCount += len(logicalAlerts)
	l.lastNumber = int(logicalAlerts[len(logicalAlerts)-1].Number)
	return logicalAlerts, nil
}

func (l *Loader) maxExceeded(ctx context.Context) bool {
	duration := time.Since(l.startTime)
	// If we have already loaded the maximum number of alerts, stop loading more.
	if l.maxLoad > 0 && l.alertCount >= l.maxLoad {
		appctx.Logger(ctx).Warn("Reached indexing maximum, stopping load",
			l.repo.RepositoryID.AsKVP(),
			kvp.String("gh.turboscan.index_limit", "alerts"),
			kvp.Int("gh.turboscan.alerts", l.alertCount),
			kvp.Duration("gh.turboscan.load_duration", duration),
			kvp.Duration("gh.turboscan.max_time", l.maxTime),
			kvp.Int("gh.turboscan.max_load", l.maxLoad),
		)
		appctx.Stats(ctx).Counter("alert_loader.max_reached", stats.Tags{"limit": "alerts"}, 1)
		return true
	}
	// If we have already spent the maximum time, stop loading more.
	if l.maxTime > 0 && duration > l.maxTime {
		appctx.Logger(ctx).Warn("Reached indexing maximum, stopping load",
			l.repo.RepositoryID.AsKVP(),
			kvp.String("gh.turboscan.index_limit", "time"),
			kvp.Int("gh.turboscan.alerts", l.alertCount),
			kvp.Duration("gh.turboscan.load_duration", duration),
			kvp.Duration("gh.turboscan.max_time", l.maxTime),
			kvp.Int("gh.turboscan.max_load", l.maxLoad),
		)
		appctx.Stats(ctx).Counter("alert_loader.max_reached", stats.Tags{"limit": "time"}, 1)
		return true
	}
	return false
}

func preloadRules(query *gorm.DB) *gorm.DB {
	return query.
		Preload("Rule").
		Preload("Rule.Tags", func(tx *gorm.DB) *gorm.DB {
			return tx.Select("id, tag, rule_id")
		}).
		Preload("Rule.Tool", func(tx *gorm.DB) *gorm.DB {
			return tx.Select("id, canonical_name, guid, is_internal_guid")
		})
}

func preloadLinks(query *gorm.DB) *gorm.DB {
	return query.Preload("Links")
}

func preloadSecurityCampaignAlerts(query *gorm.DB) *gorm.DB {
	return query.Preload("SecurityCampaignAlerts")
}

// batchPreloadPhysicalAlerts preloads the physical alerts for the given logical alerts
// in batches. GORM does not support preloading in batches, so we have to do it manually.
// This resolves performance problems when many logical alert IDs are provided which leads
// to loading too many physical alerts.
func batchPreloadPhysicalAlerts(ctx context.Context, db *gorm.DB, logicalAlerts []*ts.LogicalAlert, repo *ts.Repository) error {
	_, span := o11y.StartSpan(ctx)
	defer span.End()

	logicalAlertIDs := transforms.Map(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	logicalAlertsByID := transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	const batchSize = 100
	for i := 0; i < len(logicalAlertIDs); i += batchSize {
		start := i
		end := i + batchSize
		if end > len(logicalAlertIDs) {
			end = len(logicalAlertIDs)
		}

		logicalAlertIDsBatch := logicalAlertIDs[start:end]

		var physicalAlerts []*ts.PhysicalAlert
		err := db.
			Table("ts_physical_alerts").
			Select("ts_physical_alerts.*").
			Joins("JOIN ts_analyses ON ts_analyses.id = ts_physical_alerts.analysis_id AND ts_analyses.repository_id = ts_physical_alerts.repository_id").
			Where("ts_physical_alerts.repository_id = ?", repo.RepositoryID).
			Where("ts_analyses.soft_deleted_at IS NULL").
			Where("ts_analyses.most_recent = TRUE").
			Where("ts_analyses.ref_bytes = ?", repo.DefaultRef).
			Where("ts_physical_alerts.logical_alert_id IN (?)", logicalAlertIDsBatch).
			Find(&physicalAlerts).Error
		if err != nil {
			return err
		}

		for _, physicalAlert := range physicalAlerts {
			logicalAlert := logicalAlertsByID[physicalAlert.LogicalAlertID]
			logicalAlert.PhysicalAlerts = append(logicalAlert.PhysicalAlerts, physicalAlert)
		}
	}

	return nil
}

// AlertCount returns the number of alerts loaded so far.
func (l *Loader) AlertCount() int {
	return l.alertCount
}
