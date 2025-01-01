package status

import (
	"context"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/types"
)

// client to update check entities from status requests
type statusClient interface {
	UpdateCheckSuite(ctx context.Context, rsr *RunStatusRequest, params UpdateCheckSuiteParams) error
	UpdateCheckRun(ctx context.Context, jsr *JobStatusRequest, params UpdateCheckRunParams) error
	UpdateGateStatus(ctx context.Context, gsr *GateStatusRequest, params UpdateGateStatusParams) error
}

type usageClient interface {
	EmitUsage(ctx context.Context, dbData *deployer.DataForStatusPostback, jobID int64, checkRunID int64, update *JobStatusRequest, complete *JobComplete, billingChecked bool) error
}

type syncClient interface {
	CreateCheckRun(ctx context.Context, workflowRunBackendID string, workflowJobRunBackendID string, repoID types.GlobalID, displayName string, checkRunDatabaseID int64) error
}

// stricter client to update check entities from status requests (and receive data back)
type syncStatusClient interface {
	CreateCheckRun(ctx context.Context, jsr *JobStatusRequest, params CreateCheckRunParams) (*types.IDPair, error)
}

// UpdateCheckSuiteParams contain additional parameters needed to update a check suite
type UpdateCheckSuiteParams struct {
	CheckSuiteState *types.CheckSuiteState
	WaitingOn       *WaitingOn
}

// UpdateCheckRunParams contain additional parameters needed to update a check run
type UpdateCheckRunParams struct {
	CheckSuiteState *types.CheckSuiteState
	WaitingOn       *WaitingOn
	CheckRunID      types.GlobalID
}

// CreateCheckRunParams contain additional parameters needed to create a check run
type CreateCheckRunParams struct {
	CheckSuiteState *types.CheckSuiteState
	WaitingOn       *WaitingOn
}

// UpdateGateStatusParams contain additional parameters needed to update the gate status
type UpdateGateStatusParams struct {
	RepositoryID types.GlobalID
	OwnerID      types.GlobalID
	CheckRunID   types.GlobalID
}

// GateState represents the state of the gate
type GateState int

const (
	closed GateState = iota + 1
	open
)

func (gs GateState) String() string {
	switch gs {
	case closed:
		return "CLOSED"
	case open:
		return "OPEN"
	}

	return "UNKNOWN"
}
