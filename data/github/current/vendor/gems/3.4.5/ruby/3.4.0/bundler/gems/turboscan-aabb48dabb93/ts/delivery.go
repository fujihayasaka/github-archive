package ts

import (
	"database/sql/driver"
	"encoding/json"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts/auditlog"
	"github.com/pkg/errors"
	"go.uber.org/zap/zapcore"
)

type DeliveryID uint64

// CheckRunIds is a JSON representation.
type CheckRunIds []uint64

func (e *CheckRunIds) Scan(val interface{}) error {
	switch v := val.(type) {
	case []byte:
		return json.Unmarshal(v, &e)
	case string:
		return json.Unmarshal([]byte(v), &e)
	default:
		return errors.Errorf("Unsupported type: %T", v)
	}
}

func (e CheckRunIds) Value() (driver.Value, error) {
	if e == nil {
		// encoding of empty []uint64 to JSON
		return "[]", nil
	}

	v, err := json.Marshal(e)
	if err != nil {
		return "<invalid JSON>", err
	}
	return string(v), nil
}

// AsKVP returns the repository id as a KVP field to use with the telemetry library
func (id DeliveryID) AsKVP() zapcore.Field {
	return kvp.Uint64("gh.turboscan.delivery_id", uint64(id))
}

// Delivery collects all data from a SARIF upload
type Delivery struct {
	BaseModel
	ID                    DeliveryID
	CommitOid             Sha
	HeadCommitOid         *Sha
	Ref                   []byte
	RepositoryID          RepositoryEID
	RepositoryNWO         RepositoryNWO
	OwnerID               OwnerEID
	RequestID             RequestID
	AnalysisKey           AnalysisKey
	Environment           AnalysisEnv
	CheckoutURI           CheckoutURI
	BuildStartedAt        *time.Time
	WorkflowRunID         WorkflowRunEID
	WorkflowRunAttempt    WorkflowRunAttempt
	UploadStartedAt       *time.Time
	UploadFinishedAt      *time.Time
	HydroEnqueuedAt       *time.Time
	ProcessingLock        *string
	ProcessingStartedAt   *time.Time
	ProcessingCompletedAt *time.Time
	SarifPath             string
	SarifID               SarifID
	SourceRepositoryID    RepositoryEID
	Complete              bool
	Failed                bool
	TrackStatus           bool
	Origin                DeliveryOrigin
	WorkflowPath          WorkflowPath
	OutdatedConfiguration OutdatedConfiguration `gorm:"embedded;embedded_prefix:outdated_config_"`
	CheckRunIds           CheckRunIds
	AuditLogContext       *auditlog.AuditLogContext
	JobID                 *string

	AnalysisMessages []*AnalysisMessage
}

// OutdatedConfiguration is used in place of SARIF for outdated/tombstone deliveries
type OutdatedConfiguration struct {
	ToolName ToolName
	Category Category
}

type DeliveryOrigin uint8

const (
	DeliveryOrigin_YML DeliveryOrigin = iota
	DeliveryOrigin_MANAGED
	DeliveryOrigin_DYNAMIC
	DeliveryOrigin_API
)

// OriginFromAnalysisKey computes a DeliveryOrigin from an AnalysisKey.
// This is a transitional method while we migrate this data.
func (d *Delivery) OriginFromAnalysisKey() DeliveryOrigin {
	if strings.HasPrefix(d.AnalysisKey.String(), ".github/workflows") {
		return DeliveryOrigin_YML
	}
	if strings.HasPrefix(d.AnalysisKey.String(), ManagedAnalysisWorkflowPath) {
		return DeliveryOrigin_MANAGED
	}
	if strings.HasPrefix(d.AnalysisKey.String(), "dynamic/") {
		return DeliveryOrigin_DYNAMIC
	}
	// Everything else should be API
	return DeliveryOrigin_API
}

// WorkflowPathFromAnalysisKey computes the WorkflowPath from the AnalysisKey
// This is a transitional method while we migrate this data.
func (d *Delivery) WorkflowPathFromAnalysisKey() WorkflowPath {
	if d.OriginFromAnalysisKey() == DeliveryOrigin_YML {
		path := strings.Split(d.AnalysisKey.String(), ":")[0]
		return ToWorkflowPath([]byte(path))
	}
	return EmptyWorkflowPath()
}

// MarksAsOutdated returns true if the delivery should mark a configuration as outdated
func (d *Delivery) MarksAsOutdated() bool {
	return d.OutdatedConfiguration != OutdatedConfiguration{}
}
