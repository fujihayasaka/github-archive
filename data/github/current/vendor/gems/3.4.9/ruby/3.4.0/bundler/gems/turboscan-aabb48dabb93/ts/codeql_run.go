package ts

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"

	"go.uber.org/zap/zapcore"
	"google.golang.org/protobuf/types/known/timestamppb"

	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
)

var (
	ErrCodeqlRunNotFound           = errors.New("codeqlrun not found")
	ErrWorkflowRunAlreadyCompleted = errors.New("workflow run already completed")
)

// CodeqlRun represents an Actions run of CodeQL
type CodeqlRun struct {
	BaseModel
	ID CodeqlRunID

	RepositoryID RepositoryEID

	// RepositoryGRID is required by Action's Dynamic Workflow Run.
	// This data is available in the associated CodeqlConfig, so we do not store
	// it in the database for the run.
	RepositoryGRID RepositoryGRID `gorm:"-"`

	// The actor that triggered the run.
	ActorLogin      string
	ActorGRID       ActorGRID `gorm:"column:actor_grid"`
	TriggeringEvent CodeqlRunTriggeringEvent

	// Time event was trigerred
	EventTimestamp *sqltime.Time

	// The target of the run (Ref or SHA)
	Ref Ref `gorm:"column:ref_bytes"`
	Sha Sha

	// The workflow to be executed
	Workflow string

	// These fields contain references to the run provided by Actions.
	// These are populated only after the Run has been triggered.
	ExecutionID   string
	WorkflowRunID WorkflowRunEID

	// Final status of the Run.
	// This is populated only after we received confirmation that the run completed.
	Status CodeqlRunStatus

	// The CodeqlConfiguration associated with the Run
	CodeqlConfigID CodeqlConfigID
	Config         *CodeqlConfig `gorm:"foreignKey:CodeqlConfigID"`

	RunType CodeqlRunType

	// We keep track of whether the run is for the default branch so that we can provide
	// this information to Launch, but we do not really need to store it.
	InDefaultBranch bool `gorm:"-"`

	// OwnerID is required by the Action's Dynamic Workflow Run call
	OwnerID OwnerEID `gorm:"-"`

	// CodeqlPacks is the model packs that are used in a CodeQL run
	CodeqlPacks *CodeqlPacks
}

// CodeqlRunID represents the database ID for a CodeqlRun entry
type CodeqlRunID uint64

func (id CodeqlRunID) AsKVP() zapcore.Field {
	return kvp.Uint64("gh.turboscan.codeql_run_id", uint64(id))
}

type CodeqlRunType uint8

const (
	CodeqlRunType_STEADY CodeqlRunType = iota
	CodeqlRunType_VALIDATION
)

// CodeqlPacks represents the model packs that are used in a CodeQL run
type CodeqlPacks string

// AsKVP returns the codeqlpacks as a KVP field to use with the telemetry library
func (p CodeqlPacks) AsKVP() zapcore.Field {
	// This string can be long - the most interesting is probably just whether it is empty or not, so we just truncate it
	return kvp.String("gh.turboscan.codeql_packs", Truncate(string(p), 100))
}

// AsWorkflowString returns the codeqlpacks as a string to use in a workflow as the `packs` property.
func (p *CodeqlPacks) AsWorkflowString() string {
	if p == nil {
		return ""
	}
	lines := strings.Split(string(*p), "\n")
	newlines := make([]string, 0, len(lines))
	for _, line := range lines {
		newline := strings.TrimSpace(line)
		if newline != "" {
			newlines = append(newlines, newline)
		}
	}
	return strings.Join(newlines, ",")
}

// newCodeqlRun creates a run from the given CodeqlConfig
func newCodeqlRun(c *CodeqlConfig, actor *ActorGRIDLogin, ref Ref, sha Sha, workflow string, e CodeqlRunTriggeringEvent,
	r CodeqlRunType, defaultBranch bool, ownerID OwnerEID, codeqlPacks CodeqlPacks, eventTimestamp *sqltime.Time) (*CodeqlRun, error) {
	supportedEventsForValidationRun := map[CodeqlRunTriggeringEvent]bool{
		CodeqlRunTriggeringEvent_VALIDATION:       true,
		CodeqlRunTriggeringEvent_PUSH:             true,
		CodeqlRunTriggeringEvent_LANGUAGES_CHANGE: true,
	}
	if r == CodeqlRunType_VALIDATION && !supportedEventsForValidationRun[e] {
		return nil, errors.New(fmt.Sprintf("run type and triggering event mismatch, run_type: %d, triggering_event: %d", r, e))
	}
	if r == CodeqlRunType_STEADY && e == CodeqlRunTriggeringEvent_VALIDATION {
		return nil, errors.New(fmt.Sprintf("run type and triggering event mismatch, run_type: %d, triggering_event: %d", r, e))
	}

	return &CodeqlRun{
		RepositoryID:    c.RepositoryID,
		RepositoryGRID:  c.RepositoryGRID,
		ActorLogin:      actor.Login,
		ActorGRID:       actor.GRID,
		Ref:             ref,
		Sha:             sha,
		Workflow:        workflow,
		Config:          c,
		TriggeringEvent: e,
		RunType:         r,
		InDefaultBranch: defaultBranch,
		OwnerID:         ownerID,
		CodeqlPacks:     &codeqlPacks,
		EventTimestamp:  eventTimestamp,
	}, nil
}

// Succeeded returns whether the run completed successfully
func (cr *CodeqlRun) Succeeded() bool {
	return cr.Status == CodeqlRunStatus_COMPLETED
}

// Failed returns whether the run failed or was cancelled
func (cr *CodeqlRun) Failed() bool {
	return cr.Status == CodeqlRunStatus_FAILED || cr.Status == CodeQlRunStatus_CANCELLED
}

func (cr *CodeqlRun) JITValidation() bool {
	return cr.RunType == CodeqlRunType_VALIDATION && cr.TriggeringEvent == CodeqlRunTriggeringEvent_PUSH
}

func (cr *CodeqlRun) LanguageUpdateValidation() bool {
	return cr.RunType == CodeqlRunType_VALIDATION && cr.TriggeringEvent == CodeqlRunTriggeringEvent_LANGUAGES_CHANGE
}

func (cr *CodeqlRun) Validation() bool {
	return cr.RunType == CodeqlRunType_VALIDATION
}

// WorkflowName returns the name for the workflow
func (cr *CodeqlRun) WorkflowName() string {
	return "CodeQL"
}

func (cr *CodeqlRun) CompressedWorkflow() (string, error) {
	var b bytes.Buffer
	gz := gzip.NewWriter(&b)
	if _, err := gz.Write([]byte(cr.Workflow)); err != nil {
		return "", errors.Wrap(err, "CodeqlRun.CompressedWorkflow - failed to write")
	}
	if err := gz.Close(); err != nil {
		return "", errors.Wrap(err, "CodeqlRun.CompressedWorkflow - failed to close")
	}
	str := base64.StdEncoding.EncodeToString(b.Bytes())
	return str, nil
}

func (cr *CodeqlRun) RunName() string {
	var workflowName string
	var err error
	switch cr.TriggeringEvent {
	case CodeqlRunTriggeringEvent_PULL_REQUEST:
		var PRNumber uint32
		PRNumber, err = cr.getPRNumber()
		workflowName = fmt.Sprintf("PR #%d", PRNumber)
	case CodeqlRunTriggeringEvent_PUSH:
		var branchName string
		branchName, err = cr.getBranchName()
		workflowName = fmt.Sprintf("Push on %s", branchName)
	case CodeqlRunTriggeringEvent_VALIDATION:
		workflowName = "CodeQL Setup"
	case CodeqlRunTriggeringEvent_UNKNOWN:
		workflowName = "CodeQL"
	case CodeqlRunTriggeringEvent_SCHEDULED:
		workflowName = "Scheduled"
	case CodeqlRunTriggeringEvent_LANGUAGES_CHANGE:
		workflowName = "CodeQL"
	default:
		workflowName = "CodeQL"
	}

	if err != nil {
		// Can we log the err here?
		workflowName = "CodeQL"
	}
	return workflowName
}

// BeforeCreate is called by GORM before creating the object
func (cr *CodeqlRun) BeforeCreate() error {
	if cr.RepositoryID == 0 {
		return errors.New("RepositoryID cannot be zero")
	}

	return nil
}

func (cr *CodeqlRun) getBranchName() (string, error) {
	if cr.TriggeringEvent != CodeqlRunTriggeringEvent_PUSH && cr.TriggeringEvent != CodeqlRunTriggeringEvent_VALIDATION {
		return "", errors.New("TriggeringEvent is not PUSH or VALIDATION")
	}

	var branchName string
	r := strings.NewReader(cr.Ref.String())
	_, err := fmt.Fscanf(r, "refs/heads/%s", &branchName)
	return branchName, err
}

func (cr *CodeqlRun) getPRNumber() (uint32, error) {
	if cr.TriggeringEvent != CodeqlRunTriggeringEvent_PULL_REQUEST {
		return 0, errors.New("TriggeringEvent is not PULL_REQUEST")
	}

	var prNumber uint32
	r := strings.NewReader(cr.Ref.String())
	_, err := fmt.Fscanf(r, "refs/pull/%d/head", &prNumber)
	return prNumber, err
}

func (cr *CodeqlRun) ToHydro() *oldtshydro.CodeqlRun {
	var timestamp *timestamppb.Timestamp
	if cr.EventTimestamp != nil {
		timestamp = timestamppb.New(cr.EventTimestamp.Time)
	}

	var packs string
	if cr.CodeqlPacks != nil {
		packs = string(*cr.CodeqlPacks)
	}

	return &oldtshydro.CodeqlRun{
		RepositoryId: uint64(cr.RepositoryID),
		Workflow:     cr.Workflow,

		// References to the run provided by Actions.
		ExecutionId:   cr.ExecutionID,
		WorkflowRunId: uint64(cr.WorkflowRunID),

		// The target of the run (Ref or SHA)
		Ref: cr.Ref,
		Sha: string(cr.Sha),

		Status: cr.statusForHydro(),

		// The actor that triggered the run.
		ActorLogin: cr.ActorLogin,
		ActorGrid:  string(cr.ActorGRID),

		TriggeringEvent: cr.triggeringEventForHydro(),

		// The CodeqlConfiguration associated with the Run
		CodeqlConfigId: uint64(cr.CodeqlConfigID),
		// The model packs that are used in a CodeQL run
		CodeqlPacks: packs,

		Type:           cr.runTypeForHydro(),
		EventTimestamp: timestamp,
	}
}

func (cr *CodeqlRun) statusForHydro() oldtshydro.CodeqlRun_CodeqlRunStatus {
	switch cr.Status {
	case CodeqlRunStatus_PENDING:
		return oldtshydro.CodeqlRun_STATUS_PENDING
	case CodeqlRunStatus_INPROGRESS:
		return oldtshydro.CodeqlRun_STATUS_INPROGRESS
	case CodeqlRunStatus_COMPLETED:
		return oldtshydro.CodeqlRun_STATUS_COMPLETED
	case CodeqlRunStatus_FAILED:
		return oldtshydro.CodeqlRun_STATUS_FAILED
	case CodeQlRunStatus_CANCELLED:
		return oldtshydro.CodeqlRun_STATUS_CANCELLED
	default:
		return oldtshydro.CodeqlRun_STATUS_UNKNOWN
	}
}

func (cr *CodeqlRun) triggeringEventForHydro() oldtshydro.CodeqlRun_TriggeringEvent {
	switch cr.TriggeringEvent {
	case CodeqlRunTriggeringEvent_UNKNOWN:
		return oldtshydro.CodeqlRun_UNKNOWN
	case CodeqlRunTriggeringEvent_VALIDATION:
		return oldtshydro.CodeqlRun_VALIDATION
	case CodeqlRunTriggeringEvent_PUSH:
		return oldtshydro.CodeqlRun_PUSH
	case CodeqlRunTriggeringEvent_PULL_REQUEST:
		return oldtshydro.CodeqlRun_PULL_REQUEST
	case CodeqlRunTriggeringEvent_SCHEDULED:
		return oldtshydro.CodeqlRun_SCHEDULED
	case CodeqlRunTriggeringEvent_LANGUAGES_CHANGE:
		return oldtshydro.CodeqlRun_LANGUAGES_CHANGE
	default:
		return oldtshydro.CodeqlRun_UNKNOWN
	}
}

func (cr *CodeqlRun) runTypeForHydro() oldtshydro.CodeqlRun_CodeqlRunType {
	switch cr.RunType {
	case CodeqlRunType_STEADY:
		return oldtshydro.CodeqlRun_TYPE_STEADY
	case CodeqlRunType_VALIDATION:
		return oldtshydro.CodeqlRun_TYPE_VALIDATION
	default:
		return oldtshydro.CodeqlRun_TYPE_UNKNOWN
	}
}
