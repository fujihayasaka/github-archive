package types

// WorkflowFileReference is a unique reference to a workflow file in a source repo.
// This is needed for required workflows which have a prefix on their path to indicate their source
// repo and that they are required.
// Required workflows can be pinned to a specific SHA or ref, so they are unique by path, SHA, and ref.
type WorkflowFileReference struct {
	Path string
	SHA  CommitSha
	Ref  GitRef
}

// NewWorkflowFileReference creates a new WorkflowFileReference for a regular workflow.
// SHA and Ref are not filled out for regular workflows.
func NewWorkflowFileReference(path string) WorkflowFileReference {
	return WorkflowFileReference{
		Path: path,
	}
}

// NewRulesetWorkflowFileReference creates a new WorkflowFileReference for a ruleset workflow.
// SHA and Ref are only filled out for ruleset workflows.
func NewRulesetWorkflowFileReference(path string, ref GitRef, sha CommitSha) WorkflowFileReference {
	return WorkflowFileReference{
		Path: path,
		SHA:  sha,
		Ref:  ref,
	}
}
