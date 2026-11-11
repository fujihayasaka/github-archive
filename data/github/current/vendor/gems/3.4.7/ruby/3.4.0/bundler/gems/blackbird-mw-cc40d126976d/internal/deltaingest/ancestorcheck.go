package deltaingest

// An operation that protects against tasks that define a circular reference to
// themselves. It is invalid to have a task for a repo that lists itself as an
// ancestor. The AncestorOrderingOp and OffsetTrackingOp require that if a task
// defines ancestors repo ids, those repos are different than the task's repo,
// and that tasks for those ancestors have already been submitted.
type AncestorCheckOp struct {
	inner Op
}

func NewAncestorCheckOp(inner Op) *AncestorCheckOp {
	return &AncestorCheckOp{inner}
}

func (o *AncestorCheckOp) Run(task *Task) {
	task.Begin(o)

	repoID := task.event.GetRepository().GetId()
	ancestorIDs := task.event.GetBlackbirdAncestorRepoIds()
	for _, id := range ancestorIDs {
		if repoID == id {
			task.Done(nil)
			return
		}
	}

	o.inner.Run(task)
}

func (o *AncestorCheckOp) OnDone(task *Task, err error) {
	task.Done(err)
}
