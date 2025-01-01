// Package tool contains a service that stores the driver (and its extensions) used during a code scanning analysis.
package tool

import (
	"context"
	"encoding/json"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/turboscan/ts/gormext"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	tssarif "github.com/github/turboscan/ts/sarif"
	v210 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"

	"github.com/github/turboscan/ts/transforms"

	"github.com/pkg/errors"

	"golang.org/x/exp/maps"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/mysql/gormbulk"
	"github.com/github/turboscan/ts/mysql/scopes"

	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/jinzhu/gorm"
)

var ErrCodeQLNotInUse = errors.New("CodeQL is not in use in this environment")

// Service handles interactions with Tools.
type Service struct {
	db *gorm.DB
	ls *limits.LimitSelector
}

// NewService returns a service to store the tools that have submitted code scanning results.
func NewService(db *gorm.DB, ls *limits.LimitSelector) *Service {
	return &Service{
		db: db,
		ls: ls,
	}
}

func (t *Service) ToolsIDsWithRenames(ctx context.Context, name ts.ToolName) ([]ts.ToolID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	names := []ts.ToolName{name}
	if altName, ok := ts.ToolRenames[name]; ok {
		names = append(names, altName)
	}
	return t.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: names})
}

func (t *Service) ToolIDs(ctx context.Context, filter *ts.ToolsFilter) ([]ts.ToolID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, t.db))

	var out []ts.ToolID
	query := db.Model(&ts.Tool{}).Select("id")

	switch {
	case len(filter.CanonicalNames) > 0:
		query = query.Where("canonical_name IN (?)", filter.CanonicalNames)
	case len(filter.GUIDs) > 0:
		query = query.Where("guid IN (?)", filter.GUIDs)
	default:
		return out, nil
	}

	err := query.Pluck("id", &out).Error
	if err != nil {
		return nil, errors.Wrap(err, "unable to query tool ids")
	}

	return out, nil
}

// CodeQLToolID gets the ToolID for the CodeQL tool.
// This method does not account for renaming to ensure a single ID is returned
func (t *Service) CodeQLToolID(ctx context.Context) (ts.ToolID, error) {
	ids, err := t.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: []ts.ToolName{ts.CodeQLCanonicalName}})
	if err != nil {
		return 0, errors.Wrap(err, "unable to get CodeQL tool ID")
	}
	if len(ids) == 0 {
		return 0, ErrCodeQLNotInUse
	}
	if len(ids) != 1 {
		return 0, errors.Errorf("expected only 1 id for CodeQL but found %d", len(ids))
	}
	return ids[0], nil
}

// CreateAnalysisExtractedFiles saves an AnalysisExtractedFiles record containing the files that were extracted during this analysis.
func (t *Service) CreateAnalysisExtractedFiles(ctx context.Context, analysis *ts.Analysis, run *v210.Run, ams *analysismessage.Service) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, t.db)

	var totalExtracted int
	baselineByLanguage, err := tssarif.GetBaselineExtractedFiles(run)
	if err != nil {
		return errors.Wrap(err, "unable to parse baseline extracted files")
	}

	extractedByLanguage, err := tssarif.GetExtractedFiles(run, baselineByLanguage)
	if err != nil {
		return errors.Wrap(err, "unable to parse extracted files")
	}

	allExtractedFiles := ts.FileSetUnion(maps.Values(extractedByLanguage)...)
	totalExtracted = len(allExtractedFiles)

	notExtractedByLanguage := tssarif.GetNotExtractedFiles(baselineByLanguage, allExtractedFiles)

	var totalNotExtracted int
	for _, paths := range notExtractedByLanguage {
		totalNotExtracted += len(paths)
	}

	appctx.Stats(ctx).Distribution("processor.extracted_files", nil, float64(totalExtracted))
	appctx.Stats(ctx).Distribution("processor.not_extracted_files", nil, float64(totalNotExtracted))

	extractedData, err := json.Marshal(extractedByLanguage)
	if err != nil {
		return errors.Wrap(err, "unable to marshal extracted files")
	}
	appctx.Stats(ctx).Distribution("processor.extracted_files_storage_bytes", nil, float64(len(extractedData)))

	notExtractedData, err := json.Marshal(notExtractedByLanguage)
	if err != nil {
		return errors.Wrap(err, "unable to marshal extracted files")
	}
	appctx.Stats(ctx).Distribution("processor.extracted_files_storage_bytes", nil, float64(len(notExtractedData)))

	appctx.Logger(ctx).Info(
		"Extracted files",
		analysis.RepositoryID.AsKVP(),
		analysis.Tool.CanonicalName.AsKVP(),
		kvp.String("gh.turboscan.sarif_path", analysis.SarifURL),
		kvp.Strings("gh.turboscan.extracted_languages", maps.Keys(extractedByLanguage)),
		kvp.Strings("gh.turboscan.not_extracted_languages", maps.Keys(notExtractedByLanguage)),
		kvp.Int("gh.turboscan.extracted_files", totalExtracted),
		kvp.Int("gh.turboscan.not_extracted_files", totalNotExtracted),
		kvp.Int("gh.turboscan.extracted_files_storage_bytes", len(extractedData)),
		kvp.Int("gh.turboscan.not_extracted_files_storage_bytes", len(notExtractedData)),
	)

	extractedDataSize := len(extractedData)
	if extractedDataSize > t.ls.GetLimits(analysis.RepositoryID).ExtractedFilesLimit {
		extractedByLanguage = nil
		notExtractedByLanguage = nil
		appctx.Logger(ctx).Warn(
			"Discarded extracted files data",
			analysis.RepositoryID.AsKVP(),
			analysis.Tool.CanonicalName.AsKVP(),
			kvp.String("gh.turboscan.sarif_path", analysis.SarifURL),
		)

		_, amsError := ams.SarifProcessingSoftLimitExtractedFiles(ctx, analysis, true)
		if amsError != nil {
			appctx.Logger(ctx).WithError(amsError).Error("storing analysis error message failed")
		}
	}

	notExtractedDataSize := len(notExtractedData)
	// if any category has too much not extracted data then we will not show the percentage of files scanned
	if notExtractedDataSize > t.ls.GetLimits(analysis.RepositoryID).NotExtractedFilesLimit {
		notExtractedByLanguage = nil
		appctx.Logger(ctx).Warn(
			"Discarded not extracted files data",
			analysis.RepositoryID.AsKVP(),
			analysis.Tool.CanonicalName.AsKVP(),
			kvp.String("gh.turboscan.sarif_path", analysis.SarifURL),
		)

		_, amsError := ams.SarifProcessingSoftLimitExtractedFiles(ctx, analysis, false)
		if amsError != nil {
			appctx.Logger(ctx).WithError(amsError).Error("storing analysis error message failed")
		}
	}

	analysis.AnalysisExtractedFiles = &ts.AnalysisExtractedFiles{
		RepositoryID:      analysis.RepositoryID,
		AnalysisID:        analysis.ID,
		Analysis:          analysis,
		FilesExtracted:    extractedByLanguage,
		FilesNotExtracted: notExtractedByLanguage,
	}

	return db.Model(ts.AnalysisExtractedFiles{}).Save(&analysis.AnalysisExtractedFiles).Error
}

// CreateAnalysisExtractedFilesMessages saves the AnalysisExtractedFilesMessages records for each file not extracted.
func (t *Service) CreateAnalysisExtractedFilesMessages(ctx context.Context, analysis *ts.Analysis, toolErrors map[string]*v210.Notification, ams *analysismessage.Service) error {
	toolErrorsLimit := t.ls.GetLimits(analysis.RepositoryID).NotExtractedFilesMessagesLimit
	count := len(toolErrors)

	if count > toolErrorsLimit {
		_, err := ams.SarifSoftLimitNotExtractedFilesMessagesArgs(ctx, analysis, toolErrorsLimit, count)
		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("storing soft limit not extracted file messages failed")
		}

		appctx.Logger(ctx).Info("Soft limit applied to tool errors diagnostic messages", kvp.Int("gh.turboscan.ignored", count-toolErrorsLimit))
	}

	records := make([]*ts.AnalysisExtractedFilesMessages, 0, min(len(toolErrors), toolErrorsLimit))

	for path, notification := range toolErrors {
		records = append(records, &ts.AnalysisExtractedFilesMessages{
			AnalysisID:   analysis.ID,
			RepositoryID: analysis.RepositoryID,
			Path:         path,
			Message:      notification.Message.Text,
		})

		if len(records) == toolErrorsLimit {
			break
		}
	}

	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, t.db)

	err := gormbulk.Insert(ctx, &gormbulk.InsertOptions[ts.AnalysisExtractedFilesMessages]{
		DB:        db,
		Objects:   records,
		ChunkSize: 100,
	})
	if err != nil {
		return errors.Wrap(err, "unable save files extracted errors associated with analysis")
	}
	return nil
}

// FindAnalysisExtractedFilesMessages returns a map of paths for not extracted files to error or warning messages for a given repository's analyses.
func (t *Service) FindAnalysisExtractedFilesMessages(ctx context.Context, repoID ts.RepositoryEID, analysisIDs []ts.AnalysisID) (map[string]string, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, t.db))

	// these records have a limit, see: NotExtractedFilesMessagesLimit
	messages, err := gormext.FindInBatchesOf[*ts.AnalysisExtractedFilesMessages](ctx, 10, analysisIDs, func(start, end int) *gorm.DB {
		return db.
			Model(ts.AnalysisExtractedFilesMessages{}).
			Where("repository_id = ? AND analysis_id IN (?)", repoID, analysisIDs[start:end])
	})
	if err != nil {
		return nil, err
	}

	toolErrors := make(map[string]string)

	for _, message := range messages {
		toolErrors[message.Path] = message.Message
	}

	return toolErrors, nil
}

// DeleteAnalysisExtractedFilesMessages removes the AnalysisExtractedFilesMessages record for an analysis.
func (t *Service) DeleteAnalysisExtractedFilesMessages(ctx context.Context, repoID ts.RepositoryEID, analysisID ts.AnalysisID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, t.db)

	return db.Delete(ts.AnalysisExtractedFilesMessages{}, "repository_id = ? AND analysis_id = ?", repoID, analysisID).Error
}

// DeleteAnalysisExtractedFiles removes the AnalysisExtractedFiles record for an analysis.
func (t *Service) DeleteAnalysisExtractedFiles(ctx context.Context, repoID ts.RepositoryEID, analysisID ts.AnalysisID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, t.db)

	return db.Delete(ts.AnalysisExtractedFiles{}, "repository_id = ? AND analysis_id = ?", repoID, analysisID).Error
}

func (t *Service) ToolsUsed(ctx context.Context, repo ts.RepositoryEID) (tools []ts.Tool, err error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, t.db))

	return tools, db.Scopes(scopes.ToolsUsed(repo)).Find(&tools).Error
}

func toolVersionScope(db *gorm.DB, tv *ts.ToolVersion) *gorm.DB {
	// TODO: add unique constraints to ts_tool_versions so that this is safe
	return db.
		Where("tool_id = ?", tv.ToolID).
		Where("name = ?", tv.Name).
		Where("full_name = ?", tv.FullName).
		Where("version = ?", tv.Version).
		Where("semantic_version = ?", tv.SemanticVersion).
		Where("is_codeql_model_pack = ?", tv.IsCodeQLModelPack).
		Limit(1) // this scope can potentially return multiple rows due to a lack of unique constraints
}

func FindScope(db *gorm.DB, tool *ts.Tool) *gorm.DB {
	// support old behavior where we would also consider the tool canonical name
	// TODO: drop support for this and only use guid
	subquery := db.
		Where("canonical_name = ?", tool.CanonicalName).
		// prefer tools without an internal guid
		Order("is_internal_guid, id ASC").
		Limit(1).
		Select("id").
		SubQuery()

	// prefer guid match, only fallback to fuzzy match if not available
	return db.Where("id = IFNULL((SELECT id FROM ts_tools WHERE guid = ?), ?)", tool.GUID, subquery)
}

func reloadTools(db *gorm.DB, tools []*ts.Tool) error {
	mapped := transforms.IndexBy(tools, func(v *ts.Tool) ts.ToolID {
		return v.ID
	})
	var reloaded []ts.Tool
	err := db.Where("id IN (?)", maps.Keys(mapped)).Find(&reloaded).Error
	if err != nil {
		return err
	}
	for _, tool := range reloaded {
		*mapped[tool.ID] = tool
	}
	return nil
}

func (t *Service) FindOrCreate(ctx context.Context, versions []*ts.ToolVersion) error {
	db := otelgorm.SetSpanToGorm(ctx, t.db)

	tools := transforms.Unique(transforms.Map(versions, func(tv *ts.ToolVersion) *ts.Tool {
		return tv.Tool
	}))

	for _, tool := range tools {
		if tool.GUID == "" {
			return errors.Errorf("cannot create tool %q without guid", tool.CanonicalName)
		}
	}

	err := gormbulk.InsertIgnore(ctx, FindScope, &gormbulk.InsertOptions[ts.Tool]{
		DB:        db,
		Objects:   tools,
		ChunkSize: 100,
	})

	if err != nil {
		return err
	}

	// Reload tools from database as the unique key does not cover all the columns. The guid or canonical name may
	// be different to the ones provided.
	if err := reloadTools(db, tools); err != nil {
		return err
	}

	for _, tv := range versions {
		tv.ToolID = tv.Tool.ID
	}

	return gormbulk.InsertIgnore(ctx, toolVersionScope, &gormbulk.InsertOptions[ts.ToolVersion]{
		DB:        db,
		Objects:   transforms.Unique(versions),
		ChunkSize: 100,
	})
}
