package mysql

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

// ApplyAnalysisFilter transforms the given query with additional
// constraints from the given analysis filter, and it returns the resulting
// query. Do not alias the 'ts_analyses' table when joining with it if you are
// using this function.
func ApplyAnalysisFilter(filter ts.AnalysisFilter, query *gorm.DB) *gorm.DB {
	// This function is sometimes used to construct queries that join ts_analyses
	// with other tables. It is safe to add additional Where calls in this
	// function, but aggregation or limits should not be added (because they do
	// not make sense or have the desired meaning when joining with other
	// tables).

	// RepositoryID is a required filter
	query = query.Where("ts_analyses.repository_id = ?", filter.RepositoryID)

	// Consider only analyses that have not been deleted
	if !filter.IncludeDeleted {
		query = query.Where("ts_analyses.soft_deleted_at IS NULL")
	}

	if !filter.IncludeOutdated {
		query = query.Where("ts_analyses.is_outdated = FALSE")
	}

	switch filter.State {
	case ts.AnalysisStateFilterAll:
		// No additional filtering needed
	case ts.AnalysisStateFilterComplete:
		query = query.Where("ts_analyses.analysis_complete = TRUE")
	case ts.AnalysisStateFilterSuccessful:
		query = query.Where("ts_analyses.analysis_complete = TRUE AND ts_analyses.failed = FALSE")
	case ts.AnalysisStateFilterMostRecent:
		query = query.Where("ts_analyses.most_recent = TRUE")
	}

	if filter.State != ts.AnalysisStateFilterMostRecent {
		// If we haven't added a filter on most_recent, we still have to enforce
		// the value of most_recent (which is a boolean stored as a tinyint).
		// This makes it possible to leverage indices that include most_recent.
		query = query.Where("ts_analyses.most_recent in (0,1)")
	}

	if filter.ExcludeFork {
		query = query.Where("ts_analyses.source_repository_id = ?", filter.RepositoryID)
	}

	if filter.BranchesOnly {
		query = query.Where("ts_analyses.ref_bytes LIKE 'refs/heads/%'")
	}

	if filter.Refs != nil {
		query = query.Where("ts_analyses.ref_bytes IN (?)", filter.Refs)
	}

	if len(filter.ToolIDs) > 0 {
		query = query.Where("ts_analyses.tool_id IN (?)", filter.ToolIDs)
	}
	if len(filter.ExcludedToolIDs) > 0 {
		query = query.Not("ts_analyses.tool_id IN (?)", filter.ExcludedToolIDs)
	}
	if filter.AnalysisCategory != nil {
		query = query.Where("ts_analyses.analysis_category = ?", *filter.AnalysisCategory)
	}
	if len(filter.AnalysisIDs) > 0 {
		query = query.Where("ts_analyses.id IN (?)", filter.AnalysisIDs)
	}
	if filter.SarifID != nil {
		query = query.Where("ts_analyses.sarif_id = ?", filter.SarifID)
	}

	if filter.CreatedAfter != nil {
		query = query.Where("ts_analyses.created_at > ?", filter.CreatedAfter)
	}

	if filter.BeforeID != nil {
		query = query.Where("ts_analyses.id < ?", filter.BeforeID)
	}

	if filter.DeliveryOrigin != nil {
		query = query.Where("ts_analyses.delivery_origin = ?", filter.DeliveryOrigin)
	}

	return query
}

// FindWithAnalysisFilter returns the analyses for the specified arguments.
func FindWithAnalysisFilter(ctx context.Context, filter ts.AnalysisFilter, db *gorm.DB, opt *ts.FindOptions) ([]ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db = otelgorm.SetSpanToGorm(ctx, db)

	// Because we allow deep offset based pagination, we use a technique called "deferred joins"
	// to make the queries perform better. See e.g. https://hackmysql.com/deferred-join-deep-dive/ for more info.

	// In short we make a subquery that only selects the ids of the rows we are interested in, and then
	// we join that with the main table to get the full rows. This is much faster than doing the join
	// directly, because the join is done on a much smaller table.

	// The inner query is very similar to the original query, except that it only selects the id column,
	// and does no preloading.
	innerQuery := ApplyAnalysisFilter(filter, db.Table("ts_analyses")).Select("id")
	if opt != nil {
		if opt.Pagination != nil {
			innerQuery = opt.Pagination.Apply(innerQuery)
		}
		if opt.SortBy != "" {
			innerQuery = innerQuery.Order(opt.SortBy)
		}
	}

	// This is used to join with the outer query, that fetches all the columns of the analyses table, and the preloads.
	subQuery := innerQuery.SubQuery()

	// The main query joins the subquery with the ts_analyses table, and then applies the preloads.
	query := db.Table("ts_analyses").Joins("INNER JOIN ? AS tmp USING (id)", subQuery)
	if opt != nil {
		if opt.SortBy != "" {
			query = query.Order(opt.SortBy)
		}
		for _, preload := range opt.Preloads {
			query = query.Preload(preload)
		}
	}

	var analyses []ts.Analysis
	err := query.Find(&analyses).Error
	if err != nil {
		return nil, errors.Wrap(err, "find analyses has failed")
	}

	return analyses, nil
}
