package ts

import (
	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts/proto"
)

type PRAlertsOpts struct {
	HeadCommit  *Sha
	MergeCommit *Sha
	BaseRef     string
	// While we temporarily support both global and local tools, take both IDs
	// Once we transition to fully global rules this can become a single ID again.
	ToolIDs     []ToolID
	FileChanges []*proto.FileChange

	PRNumber           uint32
	MatchMergeAnalyses bool // consider any analysis that matches the head commit acceptable and return alerts for it
}

type PRAlerts struct {
	NewAlerts         []*LogicalAlert
	FixedAlerts       []*LogicalAlert
	MissingCategories map[Category]Analysis
	NewCategories     map[Category]uint64
	LatestUploadTime  *sqltime.Time
}

type AlertCounts struct {
	Total              int
	BySeverity         map[SeverityLevel]int
	BySecuritySeverity map[proto.SecuritySeverity]int
}

type ToolAlertCounts map[ToolID]AlertCounts
