package azpclient

import (
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/types"
)

type AllowPublic = uint

const (
	addOp     patchOp = "add"
	removeOp  patchOp = "remove"
	replaceOp patchOp = "replace"

	runnersPath               patchPath = "/runners"
	targetPath                patchPath = "/approvedChildren"
	visibilityTypePath        patchPath = "/visibilityType"
	allowPublicPath           patchPath = "/allowPublic"
	restrictedToWorkflowsPath patchPath = "/restrictedToWorkflows"
)

type RestrictedToWorkflows = uint

const (
	RestrictedToWorkflowsUnknown RestrictedToWorkflows = iota
	RestrictedToWorkflowsRestricted
	RestrictedToWorkflowsUnrestricted
)

var (
	allowPublicMap = map[AllowPublic]string{
		azp.AllowPublicUnknown: "",
		azp.AllowPublicAllow:   "true",
		azp.AllowPublicDeny:    "false",
	}

	restrictedToWorkflowsMap = map[AllowPublic]bool{
		RestrictedToWorkflowsRestricted:   true,
		RestrictedToWorkflowsUnrestricted: false,
	}
)

type runnerGroupsListResponse struct {
	Count int64              `json:"count"`
	Value []*azp.RunnerGroup `json:"value"`
}

type createGroupPayload struct {
	Name       string            `json:"name"`
	Visibility visibilityPayload `json:"visibility"`
}

type visibilityPayload struct {
	SelectedTargets       []types.GlobalID `json:"approvedChildren"`
	VisibilityType        string           `json:"visibilityType"`
	AllowPublic           string           `json:"allowPublic"`
	SelectedWorkflowRefs  []string         `json:"selectedWorkflowRefs"`
	RestrictedToWorkflows bool             `json:"restrictedToWorkflows"`
}

type patchOp string
type patchPath string

type patch struct {
	Op    patchOp   `json:"op"`
	Path  patchPath `json:"path"`
	Value any       `json:"value"`
}

func convertWorkflowOpsToPatches(wfo []azp.WorkflowRestrictionOp) []patch {
	patches := make([]patch, len(wfo))
	for i, op := range wfo {
		patches[i] = patch{Op: patchOp(op.Op), Path: patchPath(op.Path), Value: op.Value}
	}
	return patches
}
