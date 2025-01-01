package types

// WorkflowSelector identifies a workflow by id and path. Combined with repo + commit we
// have enough to identify a specific runnable workflow
// TODO refactor this out - it's not required:
//   - v1: identifier alone is enough
//   - v2: file alone is enough: although we create one workflow per `On`, all have the same ID and we only queue
//     the workflow that relates to the event
type WorkflowSelector struct {
	WorkflowPath string
	Identifier   string
}
