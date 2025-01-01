package scopes

import (
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/mysql"
	"github.com/jinzhu/gorm"
)

// ToolsUsed restricts ts_tools.id to the set of tools used by the most recent analyses in repoID.
func ToolsUsed(repoID ts.RepositoryEID) func(*gorm.DB) *gorm.DB {
	filter := ts.AnalysisFilter{
		RepositoryID:    repoID,
		ExcludeFork:     true,
		State:           ts.AnalysisStateFilterMostRecent,
		IncludeOutdated: true,
	}

	return func(db *gorm.DB) *gorm.DB {
		query := mysql.ApplyAnalysisFilter(filter, db.Table("ts_analyses")).Select("DISTINCT tool_id")

		return db.Where("ts_tools.id IN (?)", query.SubQuery())
	}
}
