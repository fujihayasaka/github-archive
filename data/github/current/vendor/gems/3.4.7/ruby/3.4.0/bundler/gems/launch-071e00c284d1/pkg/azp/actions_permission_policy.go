package azp

import (
	"github.com/github/launch/types"
)

// Values to send down to Actions Service to make validation decisions
type ActionsWorkflowPermissionsPolicy string

const (
	LimitedRead ActionsWorkflowPermissionsPolicy = "LimitedRead"

	Write ActionsWorkflowPermissionsPolicy = "Write"
)

func NewWorkflowPermissionPolicy(dwp types.DefaultWorkflowPermissions) ActionsWorkflowPermissionsPolicy {
	switch dwp {
	case types.LimitedReadWorkflowPermissions:
		return LimitedRead
	case types.WriteWorkflowPermissions:
		return Write
	default:
		return LimitedRead
	}
}
