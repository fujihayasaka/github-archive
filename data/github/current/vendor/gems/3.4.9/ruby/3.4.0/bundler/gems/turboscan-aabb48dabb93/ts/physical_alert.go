package ts

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts/proto"
	"golang.org/x/exp/maps"

	"github.com/pkg/errors"
)

type PhysicalAlertID uint64

type FileClassification []string

func (e *FileClassification) Scan(val interface{}) error {
	switch v := val.(type) {
	case []byte:
		return json.Unmarshal(v, &e)
	case string:
		return json.Unmarshal([]byte(v), &e)
	default:
		return errors.Errorf("Unsupported type: %T", v)
	}
}

func (e FileClassification) string() (string, error) {
	if e == nil {
		e = FileClassification{}
	}
	v, err := json.Marshal(e)
	if err != nil {
		return "<invalid JSON>", err
	}
	return string(v), nil
}

func (e FileClassification) Value() (driver.Value, error) {
	return e.string()
}

func (e FileClassification) Valid() error {
	_, err := e.string()
	return err
}

func (e FileClassification) String() string {
	s, err := e.string()
	if err != nil {
		return "<invalid JSON>"
	}
	return s
}

type BaselineAlerts []*PhysicalAlert

// A PhysicalAlert represents one instance of an alert in
// a single analysis run. These are grouped into logical alerts,
// where the same logical alert might correspond to multiple physical
// across several refes/build configurations/commits etc.
// A collection of physical alerts for the same analysis ID, corresponds
// to a snapshot of the state of the repo at that analysis ID.
// This state consists of two kinds of alerts:
//   - the alerts that were part of the analysis, these have LastSeenAnalysisID = nil
//   - alerts from previous analyses that are not present in the analysis (these are considered fixed),
//     these will have LastSeenAnalysisID = the last analysis that had those alerts.
type PhysicalAlert struct {
	BaseModel
	ID                    PhysicalAlertID `verify:"ignore"`
	RepositoryID          RepositoryEID
	LogicalAlertID        LogicalAlertID `verify:"ignore"` // TODO: Should handle NULL
	RuleID                RuleID         `verify:"ignore"`
	Fingerprint           string         `gormbulk:"omitzero"`
	FilePath              string         `gormbulk:"omitzero"`
	Region                Region         `gorm:"EMBEDDED"`
	StableAlertIdentifier []byte
	Suppressed            bool
	Message               string     `gormbulk:"omitzero"`
	MessageMarkdown       string     `gormbulk:"omitzero"`
	AnalysisID            AnalysisID `verify:"ignore"`
	SeverityLevel         SeverityLevel
	SecuritySeverity      *float64           `verify:"ignore"`
	LastSeenAnalysisID    *AnalysisID        `verify:"ignore"`
	FileClassification    FileClassification `verify:"ignore" gormbulk:"omitzero"` // JSON
	SnippetID             *SnippetID         `verify:"ignore"`
	GUID                  *string
	CodeFlowsDocumentID   *CodeFlowsDocumentID `verify:"ignore"`
	LastStateChangeAt     sqltime.Time         `verify:"ignore"`

	// Associations
	CodeFlowsDocument *CodeFlowsDocument `verify:"ignore"`
	RelatedLocations  []*RelatedLocation `verify:"ignore"`
	Analysis          *Analysis          `verify:"ignore"`
	LastSeenAnalysis  *Analysis          `verify:"ignore"`
	LogicalAlert      *LogicalAlert
	Snippet           *Snippet
	Rule              *Rule

	// Other
	RuleSarifIdentifier string `gorm:"-" verify:"ignore"`
	// weight is not stored in the database
	Weight uint16 `gorm:"-" verify:"ignore"`

	// Computed
	IsFixed bool `gorm:"-"`
}

func (p *PhysicalAlert) beforeVerify() *PhysicalAlert {
	if p == nil {
		return p
	}
	out := *p
	// There are old inconsistent value for security severity in the DB.
	// See https://github.com/github/code-scanning/issues/7103.
	out.SecuritySeverity = nil
	// LastSeenAnalysisID contains nil for alerts that are present in the analysis,
	// or an ID for the last analysis where the alert was present.
	out.LastSeenAnalysisID = nil
	// classification is populated on SARIF read, so an old value is stored in the DB
	out.FileClassification = nil
	// We have old alerts without a message, for those we use a placeholder
	if out.Message == "" {
		out.Message = "Empty message"
	}
	return &out
}

// SecuritySeverityLevel returns the securitySeverity mapped into
// a SecuritySeverityLevel enum value
func (p PhysicalAlert) SecuritySeverityLevel() proto.SecuritySeverity {
	return getSecuritySeverityLevel(p.SecuritySeverity)
}

func (p *PhysicalAlert) HasCodePaths() bool {
	return p.CodeFlowsDocumentID != nil
}

func (p *PhysicalAlert) ExtractFilePaths() ([]string, error) {
	filePaths := make(map[string]bool)

	if !p.HasCodePaths() {
		if p.LogicalAlert != nil {
			return []string{p.LogicalAlert.FilePath}, nil
		}
		return nil, errors.New("logical alert not loaded")
	}

	if p.CodeFlowsDocument == nil {
		return nil, errors.New("CodeFlowsDocument not loaded")
	}
	codeFlows := p.CodeFlowsDocument.Document
	groups := make([][][]CodeFlow, 0)
	for _, byCodeFlow := range GroupByCodeFlowIndex(codeFlows) {
		indexed := make([][]CodeFlow, 0, len(byCodeFlow))

		for _, byThreadFlow := range GroupByThreadFlowIndex(byCodeFlow) {
			indexed = append(indexed, byThreadFlow)
		}

		groups = append(groups, indexed)
		for _, byCodeFlow := range groups {
			for _, byThreadFlow := range byCodeFlow {
				for _, step := range byThreadFlow {
					filePaths[step.FilePath] = true
				}
			}
		}
	}

	return maps.Keys(filePaths), nil
}
