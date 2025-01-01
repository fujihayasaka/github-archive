package ts

import (
	"time"
)

type AnalysisStateFilter uint8

const (
	// AnalysisStateFilterAll returns all analyses
	AnalysisStateFilterAll AnalysisStateFilter = iota
	// AnalysisStateFilterSuccessful returns complete analyses that did not fail
	AnalysisStateFilterSuccessful
	// AnalysisStateFilterMostRecent returns only the `MostRecent` analyses
	AnalysisStateFilterMostRecent
	// AnalysisStateFilterComplete returns only complete analyses (even if they failed)
	AnalysisStateFilterComplete
)

type AnalysisFilter struct {
	RepositoryID RepositoryEID
	AnalysisIDs  []AnalysisID
	Refs         [][]byte
	ExcludeFork  bool
	BranchesOnly bool // Restrict the ref to match 'refs/heads/*'
	// In order to handle tools which have been renamed we must be able to search
	// for analyses across multiple tools.
	// TODO: merge renamed tools in the database so we can look in one canonical place.
	ToolIDs          []ToolID
	ExcludedToolIDs  []ToolID
	AnalysisCategory *Category
	State            AnalysisStateFilter
	SarifID          *SarifID
	CreatedAfter     *time.Time
	// The selected analysis must have an ID smaller than BeforeID
	BeforeID *AnalysisID
	// Allow deleted analyses to be returned
	IncludeDeleted bool
	// Allow outdated analyses to be returned.
	IncludeOutdated bool
	DeliveryOrigin  *DeliveryOrigin
}
