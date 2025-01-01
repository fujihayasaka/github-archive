package ts

import (
	"crypto/sha256"
	"database/sql/driver"
	"encoding/binary"
	"encoding/json"
	"regexp"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/proto"
	"github.com/pkg/errors"
	"go.uber.org/zap/zapcore"
)

type AnalysisID uint64

func (s AnalysisID) AsKVP() zapcore.Field {
	return kvp.Uint64("gh.turboscan.analysis_id", uint64(s))
}

type ArchivalState uint8

const (
	// ArchivalState_LIVE represents live analysis, this is the default archival state, it means data exists in DB and SARIF may exist
	ArchivalState_LIVE ArchivalState = iota
	// ArchivalState_SARIF_CREATED represents processed SARIF exists and data may exist in DB
	ArchivalState_SARIF_CREATED
	// ArchivalState_ARCHIVED represents processed SARIF exists and data does not exist in DB
	ArchivalState_ARCHIVED
)

func (a ArchivalState) String() string {
	var state string
	switch a {
	case ArchivalState_LIVE:
		state = "LIVE"
	case ArchivalState_SARIF_CREATED:
		state = "SARIF_CREATED"
	case ArchivalState_ARCHIVED:
		state = "ARCHIVED"
	}

	return state
}

// AnalysisEnv is a JSON representation.
type AnalysisEnv map[string]string

func (e *AnalysisEnv) Scan(val interface{}) error {
	switch v := val.(type) {
	case []byte:
		return json.Unmarshal(v, &e)
	case string:
		return json.Unmarshal([]byte(v), &e)
	default:
		return errors.Errorf("Unsupported type: %T", v)
	}
}

func (e AnalysisEnv) string() (string, error) {
	if e == nil {
		// encoding of empty map[string]string to JSON
		return "{}", nil
	}

	v, err := json.Marshal(e)
	if err != nil {
		return "<invalid JSON>", err
	}
	return string(v), nil
}

func (e AnalysisEnv) Value() (driver.Value, error) {
	return e.string()
}

func (e AnalysisEnv) Valid() error {
	_, err := e.string()
	return err
}

// String converts the analysis environment to a string
// Note: this needs to be deterministic, so it needs
// to make sure it does not rely on the
// non-deterministic map iteration order.
func (e AnalysisEnv) String() string {
	s, err := e.string()
	if err != nil {
		return "<invalid JSON>"
	}
	return s
}

var ErrAnalysisProcessWarningOverflow = errors.New("process_warning too long")

// An Analysis represents the result of running some tool against part
// of (or the whole of) a particular commit in a specific build
// configuration. This may be a single or multiple SARIF files,
// depending on how the Action is configured. The analysis of a commit
// may have multiple Analysis entities, which are grouped under a
// single AnalysisCommit.
type Analysis struct {
	BaseModel
	ID AnalysisID `verify:"ignore"`

	RepositoryID           RepositoryEID
	Ref                    []byte `gorm:"column:ref_bytes"`
	CommitOid              Sha
	HeadCommitOid          *Sha
	AnalysisKey            AnalysisKey
	ToolID                 ToolID        `verify:"ignore"`
	ToolVersionID          ToolVersionID `verify:"ignore"`
	Category               Category      `gorm:"column:analysis_category"`
	RunID                  string        `gorm:"column:analysis_run_id"`
	Environment            AnalysisEnv
	MostRecent             bool // If true, implies AnalysisComplete and !Failed
	AnalysisComplete       bool
	Failed                 bool // If true, implies AnalysisComplete
	BuildStartedAt         *sqltime.Time
	WorkflowRunID          WorkflowRunEID
	WorkflowRunAttempt     WorkflowRunAttempt
	DeliveryID             DeliveryID `verify:"ignore"`
	SarifURL               string
	SarifID                SarifID
	Cleaned                bool `verify:"ignore"`
	UploadStartedAt        *sqltime.Time
	UploadFinishedAt       *sqltime.Time
	SourceRepositoryID     RepositoryEID
	BaselineID             *AnalysisID `verify:"ignore"`
	RulesCount             uint
	ResultsCount           uint
	SoftDeletedAt          *sqltime.Time
	ProcessWarning         *string
	IsOutdated             bool
	ConfigurationID        ConfigurationID `verify:"ignore"`
	WorkflowPath           WorkflowPath
	DeliveryOrigin         DeliveryOrigin
	DefaultQueriesDisabled *bool

	// Archiver Book keeping
	ArchivalState   ArchivalState
	ArchivalFailed  bool // If true the archival failed permanently, and needs a manual reset before being retried.
	ArchivalDataUrl string

	// Associations
	Tool                *Tool
	ToolVersion         *ToolVersion
	ToolVersions        []*ToolVersion        `gorm:"-"`
	AnalysisQuerySuites []*AnalysisQuerySuite `gorm:"->"`
	Configuration       *Configuration

	PhysicalAlerts         []*PhysicalAlert
	Rules                  map[string]*Rule        `gorm:"-"`
	AnalysisExtractedFiles *AnalysisExtractedFiles `verify:"ignore"`

	AnalysisMessages []*AnalysisMessage `verify:"ignore"`

	AnalysisToolVersions []*AnalysisToolVersion `gorm:"->"`
	AnalysisRules        []*AnalysisRule        `gorm:"->"`
	BaselineAlerts       []*PhysicalAlert       `verify:"ignore"`

	NewLogicalAlerts      []*LogicalAlert `gorm:"-"`
	ExistingLogicalAlerts []*LogicalAlert `gorm:"-"`
	FixedLogicalAlerts    []*LogicalAlert `gorm:"-"`
}

func (a *Analysis) SetNewLogicalAlerts(alerts []*LogicalAlert) {
	a.NewLogicalAlerts = alerts
}

func (a *Analysis) SetExistingLogicalAlerts(alerts []*LogicalAlert) {
	a.ExistingLogicalAlerts = alerts
}

func (a *Analysis) SetFixedLogicalAlerts(alerts []*LogicalAlert) {
	a.FixedLogicalAlerts = alerts
}

func (a *Analysis) beforeVerify() *Analysis {
	if a == nil {
		return a
	}
	out := *a
	// handle analyses which never migrated their tool versions table
	if len(out.ToolVersions) == 0 {
		out.ToolVersions = []*ToolVersion{out.ToolVersion}
	} else {
		out.ToolVersions = sorted(out.ToolVersions)
	}
	return &out
}

// UniqueAlerts returns the alerts that were newly created in this analysis
func (a *Analysis) UniqueAlerts() []*PhysicalAlert {
	alerts := []*PhysicalAlert{}
	for _, p := range a.PhysicalAlerts {
		if p.LogicalAlert != nil && p.LogicalAlert.FirstSeenAnalysisID == a.ID {
			alerts = append(alerts, p)
		}
	}
	return alerts
}

// PresentAlerts returns the alerts that are present in the analysis, not including copied fixes
func (a *Analysis) PresentAlerts() []*PhysicalAlert {
	alerts := []*PhysicalAlert{}
	for _, p := range a.PhysicalAlerts {
		if !p.IsFixed {
			alerts = append(alerts, p)
		}
	}
	return alerts
}

// FixedAlerts returns the fixed alerts that were copied from the baseline
func (a *Analysis) FixedAlerts() []*PhysicalAlert {
	alerts := []*PhysicalAlert{}
	for _, p := range a.PhysicalAlerts {
		if p.IsFixed {
			alerts = append(alerts, p)
		}
	}
	return alerts
}

// SetPresentAlerts sets the alerts that were present in the analysis
func (a *Analysis) SetPresentAlerts(alerts []*PhysicalAlert) {
	if a.PhysicalAlerts == nil {
		a.PhysicalAlerts = []*PhysicalAlert{}
	}
	a.ResultsCount = uint(len(alerts))
	a.PhysicalAlerts = append(a.PhysicalAlerts, alerts...)
}

// SetFixedAlerts sets the fixed alerts that were copied from the baseline
func (a *Analysis) SetFixedAlerts(alerts []*PhysicalAlert) {
	if a.PhysicalAlerts == nil {
		a.PhysicalAlerts = []*PhysicalAlert{}
	}
	a.PhysicalAlerts = append(a.PhysicalAlerts, alerts...)
}

// MatchingParameters contains the subset of the analysis parameters that
// are relevant for matching.
// Note: as an optimization we also do some of this matching in the database
// queries. So any change here should be reflected in ts/mysql/analysis.go#findDiffAnalyses
type MatchingParameters struct {
	RepositoryID RepositoryEID
	Tool         ToolName
	Category     Category
}

// MatchingParams builds a MatchingParameters struct, accounting for tool renames.
func MatchingParams(tool ToolName, repoID RepositoryEID, category Category) MatchingParameters {
	if rename, ok := CanonicalToolRenames[tool]; ok {
		tool = rename
	}
	return MatchingParameters{
		RepositoryID: repoID,
		Tool:         tool,
		Category:     category,
	}
}

// MatchingParams return the matching parameters for the analysis
func (a Analysis) MatchingParams() MatchingParameters {
	return MatchingParams(a.Tool.CanonicalName, a.RepositoryID, a.Category)
}

// MP2Analysis is a map from MatchingParameters to Analysis
type MP2Analysis map[MatchingParameters]Analysis

// CleaningType determines the type of cleaning that is being done
type CleaningType uint8

const (
	CleaningTypeSARIF CleaningType = iota
	CleaningTypeAnalysisAssociations
	CleaningTypeIncomplete
)

// MarkAsDeleted sets necessary properties to delete analysis
func (a *Analysis) MarkAsDeleted() {
	now := sqltime.Now()
	a.SoftDeletedAt = &now
	a.MostRecent = false
}

// AddWarning appends a warning message to the Analysis
func (a *Analysis) AddWarning(s string) {
	if a.ProcessWarning == nil {
		a.ProcessWarning = &s
	} else {
		n := *a.ProcessWarning + "\n" + s
		a.ProcessWarning = &n
	}
}

// Status returns the AnalysisStatus of the analysis
func (a *Analysis) Status() proto.AnalysisStatus {
	switch {
	case a.Failed:
		return proto.AnalysisStatus_FAILED
	case a.AnalysisComplete:
		return proto.AnalysisStatus_COMPLETE
	default:
		return proto.AnalysisStatus_PENDING
	}
}

// AnalysisSummary contains statistics relating to an Analysis
type AnalysisSummary struct {
	// How many physical alerts are associated with this analysis
	ResultsCount uint32
	// How many distinct rules are referenced in physical alerts
	// associated with this analysis
	RulesCount uint32
}

// AutomationID represents the ID of the run, it is read from the SARIF file
// Given the automation ID x/y/z the category is x/y and the RunId is z.
type AutomationID struct {
	Category Category
	RunID    string
}

// NewAnalysis returns a new Analysis object from the given Delivery, ToolVersion and AutomationID
func NewAnalysis(info *Delivery, configuration *Configuration, toolVersion *ToolVersion, automationID AutomationID, rules map[string]*Rule) *Analysis {
	return &Analysis{
		// Delivery Derived Data
		BaseModel: BaseModel{
			CreatedAt: info.CreatedAt,
		},
		RepositoryID:       info.RepositoryID,
		CommitOid:          info.CommitOid,
		HeadCommitOid:      info.HeadCommitOid,
		Ref:                info.Ref,
		AnalysisKey:        info.AnalysisKey,
		Environment:        info.Environment,
		BuildStartedAt:     gormext.ConvertTime(info.BuildStartedAt),
		WorkflowRunID:      info.WorkflowRunID,
		WorkflowRunAttempt: info.WorkflowRunAttempt,
		UploadStartedAt:    gormext.ConvertTime(info.UploadStartedAt),
		UploadFinishedAt:   gormext.ConvertTime(info.UploadFinishedAt),
		DeliveryID:         info.ID,
		SarifURL:           info.SarifPath,
		SarifID:            info.SarifID,
		SourceRepositoryID: info.SourceRepositoryID,
		IsOutdated:         info.MarksAsOutdated(),
		DeliveryOrigin:     info.Origin,
		WorkflowPath:       info.WorkflowPath,
		// End Delivery Derived Data

		ToolVersion:     toolVersion,
		ToolVersionID:   toolVersion.ID,
		Tool:            toolVersion.Tool,
		ToolID:          toolVersion.ToolID,
		Category:        automationID.Category,
		RunID:           automationID.RunID,
		Configuration:   configuration,
		ConfigurationID: configuration.ID,

		Rules: rules,
	}
}

// BeforeCreate is used by GORM before trying to create a new row. We need this
// method separately from BeforeSave to check any zero values, because otherwise
// a call to GORM's Update() method that doesn't set RepositoryID (indicating to
// GORM that it shouldn't be changed) would fail this check.
func (a *Analysis) BeforeCreate() error {
	if a.RepositoryID == 0 {
		return errors.New("RepositoryID cannot be zero")
	}

	if a.SourceRepositoryID == 0 {
		return errors.New("SourceRepositoryID cannot be zero")
	}

	if a.ConfigurationID == 0 {
		return errors.New("ConfigurationID cannot be zero")
	}

	return nil
}

// ConfigurationHash returns the original configuration hash before we added ts_configurations
// It's slightly different to the one in ts_configurations (which has 0 bytes as a separator).
// We can swap to the new one, however it will disrupt tool status links.
// We could set up redirects (or verify barely any traffic uses the links) before we do this.
func (a *Analysis) ConfigurationHash() []byte {
	hash := sha256.New()
	buf := make([]byte, 8)
	binary.BigEndian.PutUint64(buf, uint64(a.RepositoryID))
	hash.Write(buf)
	binary.BigEndian.PutUint64(buf, uint64(a.ToolID))
	hash.Write(buf)
	hash.Write(a.Ref)
	hash.Write([]byte(a.Category))
	return hash.Sum(nil)
}

// BeforeSave is used by GORM before trying to create or update the DB
func (a *Analysis) BeforeSave() error {
	if a.MostRecent && !a.AnalysisComplete {
		return errors.New("MostRecent cannot be true if AnalysisComplete is false")
	}

	if a.MostRecent && a.Failed {
		return errors.New("MostRecent cannot be true if AnalysisFailed is true")
	}

	if a.Failed && !a.AnalysisComplete {
		return errors.New("Failed cannot be true if AnalysisComplete is false")
	}

	if a.ProcessWarning != nil && len(*a.ProcessWarning) > 2048 {
		return ErrAnalysisProcessWarningOverflow
	}

	return nil
}

func (a *Analysis) SetToolVersions(versions []*ToolVersion) {
	a.ToolVersions = make([]*ToolVersion, 0, len(versions))

	tvs := make(map[ToolVersionID]struct{})
	for _, tv := range versions {
		if _, ok := tvs[tv.ID]; !ok {
			tvs[tv.ID] = struct{}{}
			a.ToolVersions = append(a.ToolVersions, tv)
		}
	}
}

// ReSarifIDFromURL is a regular expression for extracting the SARIF ID from a SARIF URL
var ReSarifIDFromURL = regexp.MustCompile(`upload/.*/(.*)\.sarif.gz`)

type AnalysisToolVersion struct {
	BaseModel
	ID            uint64
	RepositoryID  RepositoryEID
	AnalysisID    AnalysisID
	ToolVersionID ToolVersionID

	ToolVersion *ToolVersion
}

// LatestAnalysis contains an analysis enhanced with additional information for the GetToolStatus endpoint
type LatestAnalysis struct {
	Analysis
	HasMostRecent        bool
	MinCreatedAt         *sqltime.Time
	AnalysisToolVersions []*AnalysisToolVersion `gorm:"foreignkey:AnalysisID"`
	AnalysisRules        []*AnalysisRule        `gorm:"foreignkey:AnalysisID"`
}

type LatestAnalysisAnalysisRule struct {
	*AnalysisRule
	SarifIdentifier string
	Results         uint64 // Number of unfixed physical alerts for this sarif_identifier
}

type LatestAnalysisFilter struct {
	Ref            []byte
	ToolIDs        []ToolID
	AnalysisIDs    []AnalysisID
	DeliveryOrigin *DeliveryOrigin
}
