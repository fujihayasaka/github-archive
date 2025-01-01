package ts

import (
	"context"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts/proto"

	insightshydroentities "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0/entities"
	"github.com/pkg/errors"
)

var (
	ErrAnalysisNotFound            = errors.New("analysis not found")
	ErrAnalysisIsNotDeletable      = errors.New("analysis targeted for deletion is not deletable")
	ErrMissingDeletionConfirmation = errors.New("deleting analysis would remove configuration and flag was not set")
	ErrAlertNotFound               = errors.New("alert not found")
	ErrRepoNotFound                = errors.New("repository not found")
)

type InsightsHydroAlertEventHandler interface {
	EmitInsightsEvents(ctx context.Context, docs []*SearchDocument, changedLogicalAlertIds map[LogicalAlertID]struct{}) error
	NewInsightsEntityBatchEvent(ctx context.Context, docs []*SearchDocument, event_time time.Time) error
	GetAlertFieldsHash(ctx context.Context, doc *SearchDocument, event_time time.Time) *insightshydroentities.InsightsData
}

// AlertFilter defines the filtering conditions to apply to an Alerts query
type AlertFilter struct {
	IDs                      []LogicalAlertID
	SarifIdentifiers         []string
	ExcludedSarifIdentifiers []string
	SeverityLevels           []proto.Severity
	ExcludedSeverityLevels   []proto.Severity
	State                    proto.AlertStateFilter
	Numbers                  []uint32
	Resolutions              []*AlertResolution
	Classification           proto.AlertClassificationFilter
	ExcludedResolutions      []*AlertResolution
	FilePaths                []string
	LanguageFilePaths        []string
	Cursor                   []SQLCursorFilter
}

func (f *AlertFilter) SetCursorFilter(filter []SQLCursorFilter) {
	f.Cursor = filter
}

var statusSortOrder = map[proto.AnalysisStatus]uint8{
	proto.AnalysisStatus_UNKNOWN:  0,
	proto.AnalysisStatus_MISSING:  1,
	proto.AnalysisStatus_PENDING:  2,
	proto.AnalysisStatus_COMPLETE: 3,
	proto.AnalysisStatus_FAILED:   4,
}

// AlertIDSet is an alias for sets of logical alert ids
type AlertIDSet map[LogicalAlertID]bool

// PhysicalAlertKey represents the parts of a physical alert that is needed for diffing.
// PhysicalAlertID will be zero if the analysis has been archived.
// PhysicalAlert is used to store a reference to the alert once it has been unarchived or loaded in bulk from the database.
type PhysicalAlertKey struct {
	PhysicalAlertID PhysicalAlertID
	PhysicalAlert   *PhysicalAlert
	LogicalAlertID  LogicalAlertID
	AnalysisID      AnalysisID
}

// ESAlertKey represents a logical alert together with its canonical physical alert.
// This is returned by the ES index.
type ESAlertKey struct {
	RepositoryID      RepositoryEID
	LogicalAlertID    LogicalAlertID
	PhysicalAlertID   PhysicalAlertID
	IsFixed           *bool // The fix status is not derivable from the canonical
	LastObservedFixAt *sqltime.Time
	// LastStateChangeAt is a property of the logical alert, and it is used for sorting,
	// so we pass it along instead of rely on the canonical physical alert.
	// Note that it comes from the `updated_at` field in ElasticSearch.
	LastStateChangeAt *sqltime.Time
}

type AlertResolution uint8

// If you add a new resolution here, be sure to update String()
// and IsValid() below
const (
	AlertResolutionNone          AlertResolution = 0
	AlertResolutionFalsePositive AlertResolution = 10
	AlertResolutionWontFix       AlertResolution = 20
	AlertResolutionUsedInTests   AlertResolution = 30
)

func (ar AlertResolution) String() string {
	switch ar {
	case AlertResolutionNone:
		return "AlertResolutionNone"
	case AlertResolutionFalsePositive:
		return "AlertResolutionFalsePositive"
	case AlertResolutionWontFix:
		return "AlertResolutionWontFix"
	case AlertResolutionUsedInTests:
		return "AlertResolutionUsedInTests"
	default:
		panic("Invalid AlertResolution value")
	}
}

func (ar AlertResolution) IsValid() bool {
	switch ar {
	case AlertResolutionNone, AlertResolutionFalsePositive,
		AlertResolutionWontFix, AlertResolutionUsedInTests:
		return true
	default:
		return false
	}
}

// NewAlertResolution returns the AlertResolution object corresponding to the given string value
func NewAlertResolution(s string) (AlertResolution, error) {
	switch s {
	case "AlertResolutionNone":
		return AlertResolutionNone, nil
	case "AlertResolutionFalsePositive":
		return AlertResolutionFalsePositive, nil
	case "AlertResolutionWontFix":
		return AlertResolutionWontFix, nil
	case "AlertResolutionUsedInTests":
		return AlertResolutionUsedInTests, nil
	default:
		return AlertResolutionNone, errors.Errorf("invalid alert resolution value: %s", s)
	}
}

func AlertIDSetFromSlice(ls []LogicalAlertID) AlertIDSet {
	out := AlertIDSet{}
	for i := range ls {
		out[ls[i]] = true
	}
	return out
}

var securitySeverityWeight = map[proto.SecuritySeverity]uint16{
	proto.SecuritySeverity_NO_SECURITY_SEVERITY: 0,
	proto.SecuritySeverity_LOW:                  40,
	proto.SecuritySeverity_MEDIUM:               50,
	proto.SecuritySeverity_HIGH:                 60,
	proto.SecuritySeverity_CRITICAL:             70,
}

// MagicWeight returns the weight assigned to a logical alert
func MagicWeight(severity SeverityLevel, securitySeverity proto.SecuritySeverity, precision PrecisionLevel) uint16 {
	s := uint16(severity)
	// Override severity if securitySeverity is present
	if securitySeverity != proto.SecuritySeverity_NO_SECURITY_SEVERITY {
		s = securitySeverityWeight[securitySeverity]
	}

	return s*5 + uint16(precision)*3
}
