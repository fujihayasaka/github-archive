package azp

import (
	"context"

	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
)

type AllowPublic = uint

const (
	AllowPublicUnknown AllowPublic = iota
	AllowPublicAllow
	AllowPublicDeny
)

type RestrictedToWorkflows = uint

const (
	RestrictedToWorkflowsUnknown RestrictedToWorkflows = iota
	RestrictedToWorkflowsRestricted
	RestrictedToWorkflowsUnrestricted
)

type RunnerGroupsClient interface {
	ListGroups(ctx context.Context, ownerID, planOwnerID types.GlobalID, planOwnerTenant string, includeRunners bool, isEnterpriseOwner bool, excludeHostedRunnerGroups bool, excludeElasticRunners bool, includeRunnerScaleSets bool) ([]*RunnerGroup, error)
	GetGroup(ctx context.Context, groupID int64, ownerID, planOwnerID types.GlobalID, planOwnerTenant string, includeRunners bool, isEnterpriseOwner bool, excludeHostedRunnerGroups bool, excludeElasticRunners bool, includeRunnerScaleSets bool) (*RunnerGroup, error)
	DeleteGroup(ctx context.Context, groupID int64) error
	CreateGroup(ctx context.Context, runnerIDs []int64, name string, selectedTargets []*pbtypes.Identity, visibility string, allowPublic AllowPublic, selectedWorkflowRefs []string, restrictedToWorkflows RestrictedToWorkflows) (*RunnerGroup, error)
	UpdateGroup(ctx context.Context, ownerID types.GlobalID, groupID int64, runnerOperations []RunnerOp, name string) (*RunnerGroup, error)
	AddRunners(ctx context.Context, groupID int64, runnerIDs []int64) (*RunnerGroup, error)
	RemoveRunner(ctx context.Context, groupID, runnerID int64) (*RunnerGroup, error)
	UpdateGroupRunners(ctx context.Context, groupID int64, runnerIDs []int64) (*RunnerGroup, error)
	AddTarget(ctx context.Context, groupID int64, target *pbtypes.Identity) (*Visibility, error)
	UpdateVisibility(ctx context.Context, groupID int64, visibilityType string, targets []*pbtypes.Identity, allowPublic AllowPublic, selectedWorkflowOperations []WorkflowRestrictionOp, restrictedToWorkflows RestrictedToWorkflows) error
	RemoveTarget(ctx context.Context, groupID int64, target *pbtypes.Identity) (*Visibility, error)
	UpdateGroupTargets(ctx context.Context, groupID int64, targets []*pbtypes.Identity) (*Visibility, error)
}

type RunnerGroup struct {
	ID                   int64             `json:"id"`
	Name                 string            `json:"name"`
	Size                 int64             `json:"size"`
	OwningTenant         types.GlobalID    `json:"owningTenant"`
	Runners              []*RunnerV2       `json:"runners"`
	RunnerScaleSets      []*RunnerScaleSet `json:"runnerScaleSets"`
	Visibility           Visibility        `json:"visibility"`
	IsDefault            bool              `json:"isDefaultGroup"`
	IsHosted             bool              `json:"isHosted"`
	InheritedAllowPublic bool              `json:"owningRunnerGroupAllowPublic"`
	OwnerGroupID         int64             `json:"parentTenantGroupId"`
}

type Visibility struct {
	VisibilityType               string           `json:"visibilityType"`
	SelectedTargets              []types.GlobalID `json:"approvedChildren"`
	AllowPublic                  bool             `json:"allowPublic"`
	SelectedWorkflowRefs         []string         `json:"selectedWorkflowRefs"`
	RestrictedToWorkflows        bool             `json:"restrictedToWorkflows"`
	WorkflowRestrictionsReadOnly bool             `json:"workflowRestrictionsReadOnly"`
}

type patchOp string
type patchPath string

type WorkflowRestrictionOp struct {
	Op    patchOp   `json:"op"`
	Path  patchPath `json:"path"`
	Value []string  `json:"value"`
}
