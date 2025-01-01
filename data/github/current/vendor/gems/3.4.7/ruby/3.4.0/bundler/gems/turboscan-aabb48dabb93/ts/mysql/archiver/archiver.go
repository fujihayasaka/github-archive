// Package archiver contains a service for moving SARIF to and from cold storage.
package archiver

import (
	"compress/gzip"
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/github/turboscan/ts/proto"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/turboscan/ts/archivalstore"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/mysql"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"

	"github.com/github/turboscan/ts/transforms"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/alerts"
	"github.com/github/turboscan/ts/limits"
	"github.com/google/uuid"
	"github.com/jinzhu/gorm"
	"golang.org/x/exp/maps"
	"golang.org/x/sync/errgroup"

	"github.com/SamuelTissot/sqltime"
	tssarif "github.com/github/turboscan/ts/sarif"
	"github.com/simon-engledew/pipereader"

	"github.com/pkg/errors"
)

type Service struct {
	db          *gorm.DB
	concurrency int
	sarifStore  archivalstore.ArchivalStore
	batchSize   int
}

const defaultConcurrency = 1
const defaultBatchSize = 10000

var ErrVerificationFailed = errors.New("SARIF verification failed")

// FetchPartition specifies a subset of analyses to archive
// it only fetches the analyses that has:
// ID % size = bucket
type FetchPartition struct {
	size   int
	bucket int
}

type BadArchivalState struct {
	msg string
}

func (e BadArchivalState) Error() string {
	return e.msg
}

// ArchiveOpts allows the archive process to run partially, allowing targeted manual testing.
type ArchiveOpts struct {
	// StrictVerify if true specifies that the verification should stop the archival process
	// with a failure, if false then the analysis is marked as archival_failed and the archival
	// process continues.
	StrictVerify bool
	// UploadOnly specifies that the archival will stop after uploading the SARIF file,
	// and not change the state to SARIF_CREATED.
	UploadOnly bool
	// Delete specifies that archival will actually delete the results.
	Delete bool
	// SkipVerification continues the archival, even if verification fails.
	SkipVerification bool
	// Rearchive specifies that the processed SARIF file should be recreated, even if it already exists.
	Rearchive bool
}

// WithConcurrency sets the number of analyses that will be downloaded at the same time during Unarchive.
func WithConcurrency(concurrency int) ArchiveServiceOption {
	return func(s *Service) {
		if concurrency > 0 {
			s.concurrency = concurrency
		}
	}
}

// WithBatchSize sets the number of records that will bulk deleted at a time during archival.
func WithBatchSize(batchSize int) ArchiveServiceOption {
	return func(s *Service) {
		if batchSize > 0 {
			s.batchSize = batchSize
		}
	}
}

type ArchiveServiceOption func(s *Service)

// NewService constructs a service for moving SARIF to and from cold storage.
// Setting a concurrency of zero or less will use one worker.
func NewService(db *gorm.DB, sarifStore archivalstore.ArchivalStore, opts ...ArchiveServiceOption) *Service {
	as := &Service{
		db:          db,
		sarifStore:  sarifStore,
		concurrency: defaultConcurrency,
		batchSize:   defaultBatchSize,
	}
	for _, opt := range opts {
		opt(as)
	}
	return as
}

func archiveWithTiming(fn func() (string, error)) (string, time.Duration, error) {
	startTime := time.Now()
	path, err := fn()
	return path, time.Since(startTime), err
}

func withTiming(fn func() error) (time.Duration, error) {
	startTime := time.Now()
	err := fn()
	return time.Since(startTime), err
}

func getUploadPath(repositoryId ts.RepositoryEID) string {
	return fmt.Sprintf("archive/%d/%s.sarif.gz", repositoryId, uuid.NewString())
}

// MakePartitions creates `number` partitions that cover the full interval of analyses.
func MakePartitions(number int) []FetchPartition {
	if number < 2 {
		return []FetchPartition{{}}
	}
	partitions := []FetchPartition{}
	for i := 0; i < number; i++ {
		partitions = append(partitions, FetchPartition{size: number, bucket: i})
	}
	return partitions
}

// FetchEligibleAnalyses returns analyses which are older than `age` days, in the 'live' or 'sarif_created' state and not most_recent or failed.
// It will prefer to return analyses in the 'sarif_created' state first. This will mean that if there is an issue
// archiving analyses we will need to fix it and clear the backlog rather than putting many analyses into a half archived state.
func (s *Service) FetchEligibleAnalyses(ctx context.Context, age, limit int, partition FetchPartition,
	repoID ts.RepositoryEID, id ts.AnalysisID, retryFailed bool) ([]*ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	var analyses []*ts.Analysis
	query := db.Select("ts_analyses.updated_at, ts_analyses.*")

	if repoID > 0 {
		/// When a single repo is in scope, the MySQL query optimizer will pick the `idx_analyses_on_archival_updated_at` index.
		// However, it is much faster to force MySQL to pick a repository specific index.
		// See https://github.com/github/code-scanning/issues/6939.
		query = query.Table("ts_analyses USE INDEX (idx_analyses_on_repo_id_sarif_id)")
		query = query.Where("ts_analyses.repository_id = ?", repoID)
	}

	if id > 0 {
		query = query.Where("ts_analyses.id = ?", id)
	}

	if partition.size > 0 {
		query = query.Where("ts_analyses.id % ? = ?", partition.size, partition.bucket)
	}

	query = query.Where("ts_analyses.most_recent = 0").
		Where("ts_analyses.archival_failed = ?", retryFailed).
		Where("ts_analyses.updated_at <= NOW() - INTERVAL ? DAY", age).
		Where("ts_analyses.failed = 0").
		Order("ts_analyses.updated_at ASC")

	// We cannot use an IN clause here because it will not use the index. A union wont work either.
	// This prioritises analyses that are in the ArchivalState_SARIF_CREATED state first, then
	// analyses that are in the ArchivalState_LIVE state.
	// TODO: mysql8
	// change KEY `idx_analyses_on_archival_updated_at` (`most_recent`,  `archival_state`, `updated_at`),
	// to
	// KEY `idx_analyses_on_archival_updated_at` (`most_recent`,  `archival_state` DESC, `updated_at`),
	// so we can use an IN clause and order by `archival_state` DESC, `updated_at` ASC
	for _, archivalState := range []ts.ArchivalState{ts.ArchivalState_SARIF_CREATED, ts.ArchivalState_LIVE} {
		if len(analyses) == limit {
			break
		}
		var found []*ts.Analysis
		err := query.
			Where("ts_analyses.archival_state = ?", archivalState).
			Limit(limit - len(analyses)).
			Find(&found).
			Error
		if err != nil {
			return nil, errors.Wrap(err, "Finding analyses to clean failed.")
		}

		analyses = append(analyses, found...)
	}

	return analyses, nil
}

// getAnalysisWithAlerts gets the analysis with the specified id,
// with all the alerts preloaded. If the analysis does not exist,
// it returns an error.
// If includeNonSucceeded is true then all analyses can be returned, if false
// then only analyses that have succeeded and havent been (soft) deleted are returned
func (s *Service) getAnalysisWithAlerts(ctx context.Context, repoID ts.RepositoryEID,
	analysisID ts.AnalysisID, includeNonSucceeded bool) (*ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	analysis := &ts.Analysis{}

	filter := ts.AnalysisFilter{
		RepositoryID:    repoID,
		AnalysisIDs:     []ts.AnalysisID{analysisID},
		IncludeOutdated: true,
	}

	if includeNonSucceeded {
		filter.State = ts.AnalysisStateFilterAll
		filter.IncludeDeleted = true
	} else {
		filter.State = ts.AnalysisStateFilterSuccessful
		filter.IncludeDeleted = false // This is the default, but setting it for clarity
	}

	query := mysql.ApplyAnalysisFilter(filter, db)

	err := query.
		Preload("Tool").
		Preload("ToolVersion").
		Preload("PhysicalAlerts", func(db *gorm.DB) *gorm.DB {
			// The physical alerts are ordered ascendingly according to key.
			// This preserves the order from the original SARIF.
			// This in turn makes sure that duplicated stable alert identifiers
			// will get the same offset if we reimport this as a new SARIF file.
			// See builder.go#Builder.locIndexesCache
			return db.
				Set("gorm:order_by_primary_key", "ASC").
				Where("repository_id = ? AND NOT is_fixed", repoID)
		}).
		Preload("PhysicalAlerts.Analysis").
		Preload("PhysicalAlerts.LogicalAlert").
		Preload("PhysicalAlerts.LogicalAlert.Rule").
		Preload("PhysicalAlerts.LogicalAlert.Rule.Tags").
		Preload("PhysicalAlerts.CodeFlowsDocument").
		Preload("PhysicalAlerts.RelatedLocations").
		First(analysis).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ts.ErrAnalysisNotFound
		}
		return nil, errors.Wrap(err, "get analysis with alerts has failed")
	}

	var toolVersionIDs []uint64

	err = db.
		Table("ts_analysis_tool_versions").
		Where("`ts_analysis_tool_versions`.`repository_id` = ? AND `ts_analysis_tool_versions`.`analysis_id` = ?", repoID, analysisID).
		Pluck("tool_version_id", &toolVersionIDs).Error

	if err != nil {
		return nil, err
	}

	err = db.Model(&ts.ToolVersion{}).Where(`id IN (?)`, toolVersionIDs).Find(&analysis.ToolVersions).Error
	if err != nil {
		return nil, err
	}

	return analysis, nil
}

// LoadAnalysis returns an analysis with the specified ID, and all related data
// If includeNonSucceeded is true then all analyses can be returned, if false
// then only analyses that have succeeded and havent been (soft) deleted are returned
func (s *Service) LoadAnalysis(ctx context.Context, repositoryID ts.RepositoryEID,
	analysisID ts.AnalysisID, includeNonSucceeded bool) (*ts.Analysis, error) {
	analysis, err := s.getAnalysisWithAlerts(ctx, repositoryID, analysisID, includeNonSucceeded)
	if err != nil {
		return nil, err
	}

	err = s.loadAnalysisRules(ctx, analysis.RepositoryID, analysis)
	if err != nil {
		return nil, err
	}
	return analysis, nil
}

// loadAnalysisRules returns the set of rules used in an analysis
func (s *Service) loadAnalysisRules(ctx context.Context, repoID ts.RepositoryEID, analysis *ts.Analysis) error {
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	var analysisRules []*ts.AnalysisRule

	// TODO: This should join with `ts_analyses` to check for deletion (and in general reuse the AnalysisFilter.Apply)
	err := db.Select("rule_id, defining_tool_version_id").Where("repository_id = ? AND analysis_id = ?", repoID, analysis.ID).Find(&analysisRules).Error
	if err != nil {
		return err
	}

	mapping := make(map[ts.RuleID]ts.ToolVersionID)

	for _, ar := range analysisRules {
		mapping[ar.RuleID] = ar.DefiningToolVersionID
	}

	ruleIDs := maps.Keys(mapping)

	var rules []*ts.Rule
	err = db.Model(&ts.Rule{}).
		Where("ts_rules.id IN (?)", ruleIDs).
		Preload("Tags").
		Find(&rules).Error

	if err != nil {
		return err
	}

	// Convert to map and store in Analysis
	analysis.Rules = transforms.IndexBy(rules, func(r *ts.Rule) string {
		// this field is not saved in the database
		r.DefiningToolVersionID = mapping[r.ID]
		return r.SarifIdentifier
	})

	return nil
}

// FullArchive perfoms full archival of a single analysis with optionals specifying when to run a subset of the behaviours.
func (s *Service) FullArchive(ctx context.Context, repositoryID ts.RepositoryEID, analysisID ts.AnalysisID, opts ArchiveOpts) error {
	analysis, err := s.LoadAnalysis(ctx, repositoryID, analysisID, true)
	if err != nil {
		return err
	}

	if analysis.MostRecent && !opts.UploadOnly {
		return errors.New("Cannot archive most recent analysis")
	}

	// If the analysis is live we need to extract the SARIF, verify it and progress the state.
	if analysis.ArchivalState == ts.ArchivalState_LIVE {
		path := analysis.ArchivalDataUrl
		rearchived := false
		// If the processed SARIF is already present, we shouldn't recreate it.
		if path == "" || opts.Rearchive {
			rearchived = true
			path, err = s.archive(ctx, analysis)
			if err != nil {
				return err
			}
			// Update the path
			err = s.updateArchivalState(ctx, analysis, analysis.ArchivalState, &path, false)
			if err != nil {
				return err
			}
		}

		if !opts.SkipVerification && rearchived {
			err = s.verify(ctx, repositoryID, analysis)
			if err != nil {
				if errors.Is(err, ErrVerificationFailed) {
					appctx.Logger(ctx).Info("Analysis failed verification", analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP(), kvp.Bool("rearchived", rearchived))
					if !opts.StrictVerify {
						// This is considered a permanent error until the code is changed, we mark the analysis as
						// archive failed to allow us to proceed.
						appctx.Stats(ctx).Counter("archival.failed", nil, 1)
						return s.updateArchivalState(ctx, analysis, analysis.ArchivalState, &path, true)
					}
				} else {
					return err
				}
			}
		}
		if opts.UploadOnly {
			appctx.Logger(ctx).Info("Upload only requested, stopping", analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP())
			return nil
		}

		// Now update the state, this means that the analysis is now considered historic and
		// all endpoints should use SARIF when needed.
		err = s.updateArchivalState(ctx, analysis, ts.ArchivalState_SARIF_CREATED, &path, false)
		if err != nil {
			return err
		}
		appctx.Logger(ctx).Info("Analysis now historic", analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP())
	}

	// If the state is created then we need to delete and progress the state

	if analysis.ArchivalState == ts.ArchivalState_SARIF_CREATED && opts.Delete {
		err := s.deleteAnalysisAssociations(ctx, analysis)
		if err != nil {
			return err
		}

		err = s.updateArchivalState(ctx, analysis, ts.ArchivalState_ARCHIVED, nil, false)
		if err != nil {
			return err
		}
		appctx.Logger(ctx).Info("Analysis now completly archived", analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP())
	}

	return nil
}

// updateArchivalState tries to update ArchivalState, ArchivalDataUrl fields for given analysis,
// it looks for specific most_recent state to guard against race condition
// returns BadArchivalState if update stmt returns empty or more than 1 rows
func (s *Service) updateArchivalState(ctx context.Context, analysis *ts.Analysis,
	state ts.ArchivalState, url *string, archivalFailed bool) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	updatedAt := sqltime.Now()
	updateFields := map[string]interface{}{
		"updated_at": updatedAt,
	}
	if state != analysis.ArchivalState {
		updateFields["archival_state"] = state
	}
	if url != nil {
		updateFields["archival_data_url"] = *url
	}
	if archivalFailed != analysis.ArchivalFailed {
		updateFields["archival_failed"] = archivalFailed
	}

	// We use UpdateColumns to prevent gorm from setting updated_at as well
	result := db.Model(&ts.Analysis{}).Where("id = ? AND most_recent = ? AND archival_state = ?", analysis.ID, analysis.MostRecent, analysis.ArchivalState).UpdateColumn(updateFields)
	if result.Error != nil {
		return errors.Wrap(result.Error, "Updating analysis failed.")
	}
	if result.RowsAffected != 1 {
		// it should get exactly one to make sure no other process changes the analysis state, returns a BadArchivalState
		return errors.Wrap(BadArchivalState{
			msg: "Bad archival state",
		}, "Updating analysis failed.")
	}
	analysis.UpdatedAt = updatedAt
	analysis.ArchivalState = state
	if url != nil {
		analysis.ArchivalDataUrl = *url
	}
	analysis.ArchivalFailed = archivalFailed
	appctx.Logger(ctx).Info("Archive state updated",
		analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP(),
		kvp.Stringer("gh.turboscan.state", state),
		kvp.Bool("gh.turboscan.archival_failed", archivalFailed),
		kvp.Any("gh.turboscan.archival_data_url", url),
	)
	return nil
}

// deleteAnalysisAssociations hard deletes AnalysisRules, ToolVersions, Metrics and PhysicalAlerts for given analysis
func (s *Service) deleteAnalysisAssociations(ctx context.Context, analysis *ts.Analysis) error {
	appctx.Logger(ctx).Info("deleting analysis associations from db", analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP())
	appctx.Stats(ctx).Counter("delete.started", nil, 1)

	duration, err := withTiming(func() error {
		err := s.HardDeleteAnalysisRules(ctx, analysis)
		if err != nil {
			return err
		}

		err = s.HardDeleteToolVersions(ctx, analysis)
		if err != nil {
			return err
		}

		err = s.HardDeleteAlerts(ctx, analysis)
		if err != nil {
			return err
		}

		return nil
	})

	appctx.Stats(ctx).DistributionMs("delete.complete", resultTags(err), duration)
	appctx.Logger(ctx).WithError(err).Info("delete analysis associations completed",
		kvp.String("gh.operation.name", "delete analysis associations completed"),
		kvp.Float64("gh.operation.duration", float64(duration)),
		analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP(),
	)

	return err
}

// archive re-builds the analysis data into a SARIF file and uploads it to the SarifStore.
// it shouldn't do any state change in DB!
func (s *Service) archive(ctx context.Context, analysis *ts.Analysis) (string, error) {
	appctx.Logger(ctx).Info("archiving analysis", analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP())
	appctx.Stats(ctx).Counter("archive.started", nil, 1)

	archiveDataUrl, duration, err := archiveWithTiming(func() (string, error) {
		opts := tssarif.BuildSarifOpts{
			RepoHTMLURL: "$repoHtmlUrl",
			AlertAPIURL: "$alertApiUrl",
		}

		sarif, err := tssarif.BuildSarif(analysis, opts)
		if err != nil {
			return "", err
		}

		// use pipeline to compress sarif and stream it into store.Upload method
		pr := pipereader.New(strings.NewReader(sarif), gzip.NewWriter)

		// If the path is already set then re-use it
		path := analysis.ArchivalDataUrl
		if path == "" {
			path = getUploadPath(analysis.RepositoryID)
		}

		archiveDataUrl, err := s.sarifStore.Archive(ctx, pr, path)
		if err != nil {
			return "", err
		}

		return archiveDataUrl, nil
	})

	appctx.Stats(ctx).DistributionMs("archive.complete", resultTags(err), duration)
	appctx.Logger(ctx).WithError(err).Info("archive analysis completed",
		kvp.Float64("gh.operation.duration", float64(duration)),
		analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP(),
	)

	return archiveDataUrl, nil
}

func resultTags(err error) stats.Tags {
	if err == nil {
		return stats.Tags{"result": "success"}
	}
	return stats.Tags{"result": "failure"}
}

func fetchLogicalAlertsForNumbers(ctx context.Context, db *gorm.DB, repoID ts.RepositoryEID,
	numbers []uint32) ([]*ts.LogicalAlert, error) {

	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db = otelgorm.SetSpanToGorm(ctx, db)

	// Fetch logical alerts in batches of 1000
	chunkSize := 1000
	result := make([]*ts.LogicalAlert, 0, len(numbers))
	for i := 0; i < len(numbers); i += chunkSize {
		end := i + chunkSize
		if end > len(numbers) {
			end = len(numbers)
		}
		chunk := numbers[i:end]
		var logicalAlerts []*ts.LogicalAlert
		query := db.Where("repository_id = ? AND number IN (?)", repoID, chunk)
		err := query.Find(&logicalAlerts).Error
		if err != nil {
			return nil, errors.Wrap(err, "fetching logical alerts has failed")
		}
		result = append(result, logicalAlerts...)
	}
	return result, nil
}

// Unarchive takes archived analyses and populates them based on the data in their archived SARIF files.
// Since the bulk of the data is not backed by the DB, most IDs and timestamps are not set.
func (s *Service) Unarchive(ctx context.Context, repoID ts.RepositoryEID, analyses ...*ts.Analysis) error {
	err := s.unarchiveSarif(ctx, analyses)
	if err != nil {
		return err
	}

	err = s.loadLogicalAlerts(ctx, repoID, analyses)
	if err != nil {
		return err
	}

	return nil
}

func (s *Service) fetchSarif(ctx context.Context, url string, out *v2_1_0.SARIF) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	buf, err := s.sarifStore.Download(ctx, url)
	if err != nil {
		return errors.Wrap(err, "failed to download sarif")
	}

	return errors.Wrap(tssarif.Unmarshal(buf.Bytes(), out), "failed to unmarshal sarif")
}

// unarchiveSarif unarchives the analysis. It only reads from the sarif and not from the database.
func (s *Service) unarchiveSarif(ctx context.Context, analyses []*ts.Analysis) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	logger := appctx.Logger(ctx).WithFields(
		kvp.Uint64s("gh.turboscan.analysis_ids", transforms.Map(analyses, func(a *ts.Analysis) uint64 {
			return uint64(a.ID)
		})),
		kvp.Uint64s("gh.repo.ids", transforms.MapUnique(analyses, func(a *ts.Analysis) uint64 {
			return uint64(a.RepositoryID)
		})),
	)
	logger.Info("unarchiving analysis")
	appctx.Stats(ctx).Counter("unarchive.started", nil, 1)

	duration, err := withTiming(func() error {
		var group *errgroup.Group
		group, ctx = errgroup.WithContext(ctx)
		group.SetLimit(s.concurrency)

		// pre-flight check
		for _, analysis := range analyses {
			// We want to allow validation before we actually update the state, so we only require
			// that the analyses have an archival URL.
			if analysis.ArchivalDataUrl == "" {
				return errors.New("analysis is not archived")
			}
		}

		for _, analysis := range analyses {
			// if any analysis cannot be unarchived the function will return an error
			group.Go(func() error {
				var sarif v2_1_0.SARIF

				// Parse SARIF
				if err := s.fetchSarif(ctx, analysis.ArchivalDataUrl, &sarif); err != nil {
					return err
				}

				// Archived SARIF should only contain a single run.
				if len(sarif.Runs) != 1 {
					return errors.Errorf("Archived SARIF contained %d runs, expected exactly 1", len(sarif.Runs))
				}
				run := sarif.Runs[0]

				analysis.DefaultQueriesDisabled, analysis.AnalysisQuerySuites = tssarif.GetCodeQLConfig(run)

				// Extract tools
				driver, extensions, err := tssarif.ToolVersionsFromSarifRun(run)
				if err != nil {
					return err
				}

				analysis.Tool = driver.Tool
				analysis.ToolVersion = driver
				analysis.ToolVersions = append(analysis.ToolVersions, driver)
				analysis.ToolVersions = append(analysis.ToolVersions, extensions...)

				sarifRules, err := tssarif.GetRules(run)
				if err != nil {
					return err
				}

				// Extract rules
				limits := limits.LimitsInternal() // Limits were already applied during initially processing

				// The second return value, the rule limit errors, is ignored as those should already be present
				// in the analysis from the initial processing.
				rules, _, err := tssarif.ConvertRules(ctx, sarifRules, driver, extensions, limits.TagsPerRuleLimit)
				if err != nil {
					return err
				}
				analysis.Rules = rules

				// Extract alerts
				builder := alerts.NewAlertsBuilder(analysis, &limits)
				// The checkout URI was already used for resolving the filepaths during initial processing,
				// so we can leave it blank here.
				physicalAlerts, err := builder.Build(ctx, run, ts.EmptyCheckoutURI)
				// Only unrecoverable and unexpected errors should fail archival.
				// If we see warnings like truncated results, they will
				// result in validation errors later. This is ok as we can
				// then decide to permanently fail those.
				if uerr := alerts.UnrecoverableArchivalError(err); uerr != nil {
					return uerr
				}
				analysis.SetPresentAlerts(physicalAlerts)

				return nil
			})
		}

		return group.Wait()
	})

	appctx.Stats(ctx).DistributionMs("unarchive.complete", resultTags(err), duration)
	logger.WithError(err).Info("unarchive analysis complete", kvp.Float64("gh.operation.duration", float64(duration)))

	return err
}

func (s *Service) loadLogicalAlerts(ctx context.Context, repoID ts.RepositoryEID, analyses []*ts.Analysis) error {
	preloadDB := s.db.Preload("Rule").Preload("Rule.Tags")
	physicalAlerts := transforms.Flatten(transforms.Map(analyses, func(a *ts.Analysis) []*ts.PhysicalAlert {
		return a.PhysicalAlerts
	}))

	logicals, err := alert.FetchLogicalAlertsForPhysicalAlerts(ctx, preloadDB, repoID, physicalAlerts)
	if err != nil {
		return errors.Wrap(err, "failed to load physical alerts")
	}

	for _, pa := range physicalAlerts {
		la, ok := logicals[alerts.FromBytes(pa.StableAlertIdentifier)]
		if !ok {
			// This could mean we didnt have consistent stable IDs, so we fail.
			return errors.Wrap(errors.WithStack(ErrVerificationFailed), "Failed to find logical alert")
		}
		pa.LogicalAlertID = la.ID
		pa.LogicalAlert = la
	}

	return nil
}

func (s *Service) UnarchiveAlerts(ctx context.Context, repoID ts.RepositoryEID, numbers []uint32, analyses ...*ts.Analysis) ([]*ts.LogicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// Sort analyses by increasing creation time so that latest physical alerts will end up in the map in the end
	sort.Slice(analyses, func(i, j int) bool {
		return analyses[i].CreatedAt.Time.Before(analyses[j].CreatedAt.Time)
	})

	preloadDB := s.db.Preload("Rule").Preload("Rule.Tags")
	logicalAlerts, err := fetchLogicalAlertsForNumbers(ctx, preloadDB, repoID, numbers)
	if err != nil {
		return nil, err
	}

	err = s.unarchiveSarif(ctx, analyses)
	if err != nil {
		return nil, err
	}

	pasByStableAlertId := make(map[alerts.StableAlertIdentifier]*ts.PhysicalAlert)
	for _, analysis := range analyses {
		for _, pa := range analysis.PhysicalAlerts {
			pasByStableAlertId[alerts.FromBytes(pa.StableAlertIdentifier)] = pa

			// Also set the analysis for the alert
			pa.Analysis = analysis
		}
	}

	results := make([]*ts.LogicalAlert, 0, len(logicalAlerts))
	for _, la := range logicalAlerts {
		pa, ok := pasByStableAlertId[alerts.FromBytes(la.StableAlertIdentifier)]
		if ok {
			// Connect physical and logical alert
			pa.LogicalAlertID = la.ID
			pa.LogicalAlert = la
			// All the physical alerts should not be fixed because we do not archive fixed alerts
			// but it does not hurt to check
			if !pa.IsFixed {
				is_fixed := false
				la.IsFixed = &is_fixed
			}
			pa.LogicalAlert.PhysicalAlerts = []*ts.PhysicalAlert{pa}
			pa.LogicalAlert.Rule.Tool = pa.Analysis.Tool

			// and include in the results
			results = append(results, la)
		}
	}

	return results, nil
}

// verify checks that the specified analysis has a valid archived SARIF file associated to it.
// It makes sure the contents of the file are equivalent to the data in the analysis object and returns an error and the diff in case of mismatch.
func (s *Service) verify(ctx context.Context, repoID ts.RepositoryEID, analysis *ts.Analysis) error {
	duration, err := withTiming(func() error {
		var freshAnalysis ts.Analysis
		err := s.db.First(&freshAnalysis, "id = ?", analysis.ID).Error
		if err != nil {
			return err
		}
		unarchiveErr := s.Unarchive(ctx, repoID, &freshAnalysis)
		if unarchiveErr != nil {
			appctx.Logger(ctx).WithError(unarchiveErr).Info("SARIF unarchive failed", analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP())
			return errors.Wrap(errors.WithStack(ErrVerificationFailed), unarchiveErr.Error())
		}

		verifyErr := analysis.Verify(&freshAnalysis)
		if verifyErr == nil {
			appctx.Logger(ctx).Info("SARIF verification succeeded", analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP())
			return nil
		}

		appctx.Logger(ctx).WithError(verifyErr).Info("SARIF verification failed", analysis.ID.AsKVP(), analysis.RepositoryID.AsKVP())
		return errors.Wrap(errors.WithStack(ErrVerificationFailed), verifyErr.Error())
	})
	appctx.Stats(ctx).DistributionMs("verify.complete", resultTags(err), duration)
	return err
}

// HardDeleteAnalysisRules deletes data from ts_analysis_rules table for given analysis
func (s *Service) HardDeleteAnalysisRules(ctx context.Context, analysis *ts.Analysis) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	// Add some KVP values to the logger to distinguish various operations
	logger := appctx.Logger(ctx).WithFields(
		analysis.ID.AsKVP(),
		analysis.RepositoryID.AsKVP(),
		kvp.String("gh.turboscan.model", "AnalysisRules"),
	)

	// Defensive check
	if analysis.MostRecent {
		return errors.New("cannot delete items from most recent analysis")
	}

	// Query for all analysis rules in the analysis
	idsQuery := db.Model(&ts.AnalysisRule{}).
		Where("repository_id = ? ", analysis.RepositoryID).
		Where("analysis_id = ?", analysis.ID).
		Select("id")

	// Function for deleting metric results. Must return the number of affected rows.
	deleteFn := func(db *gorm.DB, ids []uint64) (int64, error) {
		deletes := db.Delete(&ts.AnalysisRule{},
			"repository_id = ? AND id IN (?)",
			analysis.RepositoryID, ids,
		)
		if err := deletes.Error; err != nil {
			return 0, err
		}
		appctx.Stats(ctx).Counter("archive_hard_deleted", stats.Tags{"table": "ts_analysis_rules"}, deletes.RowsAffected)
		return deletes.RowsAffected, nil
	}

	_, err := gormext.BatchDelete(logger, db, s.batchSize, idsQuery, deleteFn)
	return errors.Wrap(err, "Deleting AnalysisRules failed.")
}

// HardDeleteToolVersions deletes data from ts_analysis_tool_versions table for given analysis
func (s *Service) HardDeleteToolVersions(ctx context.Context, analysis *ts.Analysis) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	// Add some KVP values to the logger to distinguish various operations
	logger := appctx.Logger(ctx).WithFields(
		analysis.ID.AsKVP(),
		analysis.RepositoryID.AsKVP(),
		kvp.String("gh.turboscan.model", "AnalysisToolVersions"),
	)

	// Defensive check
	if analysis.MostRecent {
		return errors.New("cannot delete items from most recent analysis")
	}

	// Query for all tool versions in the analysis
	idsQuery := db.Model(&ts.AnalysisToolVersion{}).
		Where("repository_id = ? ", analysis.RepositoryID).
		Where("analysis_id = ?", analysis.ID).
		Select("id")

	// Function for deleting tool versions results. Must return the number of affected rows.
	deleteFn := func(db *gorm.DB, ids []uint64) (int64, error) {
		deletes := db.Delete(&ts.AnalysisToolVersion{},
			"repository_id = ? AND id IN (?)",
			analysis.RepositoryID, ids,
		)
		if err := deletes.Error; err != nil {
			return 0, err
		}
		appctx.Stats(ctx).Counter("archive_hard_deleted", stats.Tags{"table": "ts_analysis_tool_versions"}, deletes.RowsAffected)
		return deletes.RowsAffected, nil
	}

	_, err := gormext.BatchDelete(logger, db, s.batchSize, idsQuery, deleteFn)

	return errors.Wrap(err, "Deleting ToolVersion failed.")
}

// HardDeleteAlerts permanently deletes the physical alerts from the specified analysis.
// @todo: this is copy of garbagecollections.go#HardDeleteAlerts, we need to unified these two and move into batch_delete.go in followup PR
func (s *Service) HardDeleteAlerts(ctx context.Context, analysis *ts.Analysis) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	// Add some KVP values to the logger to distinguish various operations
	logger := appctx.Logger(ctx).WithFields(
		analysis.ID.AsKVP(),
		analysis.RepositoryID.AsKVP(),
		kvp.String("gh.turboscan.model", "PhysicalAlerts"),
	)

	// Defensive check
	if analysis.MostRecent {
		return errors.New("cannot delete items from most recent analysis")
	}

	// Query for all alerts in the analysis
	idsQuery := db.Model(&ts.PhysicalAlert{}).
		Where("repository_id = ? ", analysis.RepositoryID).
		Where("analysis_id = ?", analysis.ID)

	idsQuery = idsQuery.Select("id")

	// Function for deletion. Must return the number of deleted entries.
	deleteFn := func(db *gorm.DB, ids []uint64) (int64, error) {
		// Delete all related locations for the alerts in the batch.
		// Note: This is potentially unbounded as well, so chunking might make sense.
		//       However these do not accumulate in the same ways as fixes so we decided
		// 		 to not chunk unless we see a problem
		rlDelete := db.Delete(
			&ts.RelatedLocation{},
			"repository_id = ? AND physical_alert_id IN (?)",
			analysis.RepositoryID, ids,
		)
		if err := rlDelete.Error; err != nil {
			return 0, err
		}
		appctx.Stats(ctx).Counter("archive_hard_deleted", stats.Tags{"table": "ts_related_locations"}, rlDelete.RowsAffected)

		// Delete the alerts
		deletes := db.Delete(&ts.PhysicalAlert{},
			"repository_id = ? AND id IN (?)",
			analysis.RepositoryID, ids,
		)
		if err := deletes.Error; err != nil {
			return 0, err
		}
		appctx.Stats(ctx).Counter("archive_hard_deleted", stats.Tags{"table": "ts_physical_alerts"}, deletes.RowsAffected)

		return deletes.RowsAffected, nil
	}

	_, err := gormext.BatchDelete(logger, db, s.batchSize, idsQuery, deleteFn)
	return errors.Wrap(err, "Deleting Alerts failed.")
}

// ExtractCodePaths extracts the CodeFlows and RelatedLocations corresponding to the specified alerts from the specified analysis.
func (s *Service) ExtractCodePaths(ctx context.Context, analysis *ts.Analysis, las []*ts.LogicalAlert) (map[ts.LogicalAlertID]*ts.CodeFlowsDocument, map[ts.LogicalAlertID][]*ts.RelatedLocation, error) {
	docs := make(map[ts.LogicalAlertID]*ts.CodeFlowsDocument)
	locs := make(map[ts.LogicalAlertID][]*ts.RelatedLocation)
	if analysis.ArchivalDataUrl == "" {
		// This should only happen on GHES, where we still have unarchived analyses
		// In this case, we should fall back to MySQL
		pas := []*ts.PhysicalAlert{}
		ids := make([]uint64, 0, len(las))
		for _, a := range las {
			ids = append(ids, uint64(a.ID))
		}
		err := s.db.Table("ts_physical_alerts").
			Where("ts_physical_alerts.repository_id = ? AND ts_physical_alerts.analysis_id = ? AND logical_alert_id IN (?)", analysis.RepositoryID, analysis.ID, ids).
			Preload("CodeFlowsDocument", "RelatedLocations").
			Find(&pas).Error
		if err != nil {
			return nil, nil, err
		}
		for _, pa := range pas {
			docs[pa.LogicalAlertID] = pa.CodeFlowsDocument
			locs[pa.LogicalAlertID] = pa.RelatedLocations
		}
		for _, la := range las {
			if _, ok := docs[la.ID]; !ok {
				return nil, nil, errors.New("result not found")
			}
		}
		return docs, locs, nil
	}
	var sarif v2_1_0.SARIF
	if err := s.fetchSarif(ctx, analysis.ArchivalDataUrl, &sarif); err != nil {
		return nil, nil, err
	}
	resultMap, err := tssarif.ResultsByAlertNumber(&sarif)
	if err != nil {
		return nil, nil, err
	}
	limits := limits.LimitsInternal()
	builder := alerts.NewAlertsBuilder(analysis, &limits)

	for _, la := range las {
		result, ok := resultMap[la.Number]
		if !ok {
			return nil, nil, errors.New("result not found")
		}

		codeflows, err := builder.BuildCodeFlows(result.CodeFlows, ts.EmptyCheckoutURI)
		if err != nil {
			return nil, nil, err
		}
		var doc *ts.CodeFlowsDocument
		if len(codeflows) > 0 {
			doc = &ts.CodeFlowsDocument{
				RepositoryID: analysis.RepositoryID,
				Document:     codeflows,
			}
		}
		docs[la.ID] = doc

		relatedLocations, err := builder.BuildRelatedLocations(result.RelatedLocations, ts.EmptyCheckoutURI)
		if err != nil {
			return nil, nil, err
		}
		locs[la.ID] = relatedLocations

	}
	return docs, locs, nil
}

func (s *Service) ExtractPhysicalAlertsByLocation(ctx context.Context, analysis *ts.Analysis, fileChangesMap map[string][]*proto.Change) ([]*ts.PhysicalAlert, error) {
	if analysis.ArchivalDataUrl == "" {
		return nil, errors.New("analysis is not archived")
	}
	var sarif v2_1_0.SARIF
	if err := s.fetchSarif(ctx, analysis.ArchivalDataUrl, &sarif); err != nil {
		return nil, err
	}
	results := tssarif.ResultsByLocations(&sarif, fileChangesMap)
	if len(results) == 0 {
		return nil, nil
	}
	limits := limits.LimitsInternal()
	builder := alerts.NewAlertsBuilder(analysis, &limits)
	alerts := map[uint32]*ts.PhysicalAlert{}
	for idx, result := range results {
		alert, err := builder.BuildAlert(sarif.Runs[0], idx, result, ts.EmptyCheckoutURI)
		if err != nil {
			return nil, err
		}
		if result.Properties != nil {
			alerts[uint32(result.Properties.GithubAlertNumber)] = alert
		}
	}
	// assign the corresponding logical alerts
	logicalAlerts, err := fetchLogicalAlertsForNumbers(ctx, s.db, analysis.RepositoryID, maps.Keys(alerts))
	if err != nil {
		return nil, err
	}
	for _, la := range logicalAlerts {
		alert := alerts[la.Number]
		alert.LogicalAlertID = la.ID
	}
	return maps.Values(alerts), nil
}
