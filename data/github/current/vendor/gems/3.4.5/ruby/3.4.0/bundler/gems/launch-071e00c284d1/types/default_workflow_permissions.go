package types

// DefaultWorkflowPermissions determine the default GITHUB_TOKEN permissions
// See https://github.com/github/github/blob/master/lib/configurable/default_workflow_permissions.rb
type DefaultWorkflowPermissions string

const (
	// The GITHUB_TOKEN should be limited to read permission for the contents, packages scope.
	LimitedReadWorkflowPermissions DefaultWorkflowPermissions = "READ"

	// The GITHUB_TOKEN should be contain write permission for all scopes.
	// However fork PRs may cause the permissions to be downgraded to read.
	WriteWorkflowPermissions DefaultWorkflowPermissions = ""
)
