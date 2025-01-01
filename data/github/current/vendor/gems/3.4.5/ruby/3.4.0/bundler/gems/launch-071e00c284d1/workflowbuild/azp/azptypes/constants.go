package azptypes

const (
	// Actions Service Run Statuses
	// https://dev.azure.com/mseng/AzureDevOps/_git/AzDevNext?path=%2FActions%2FClient%2FWebApi%2FActionPipelineStateConverter.cs&_a=contents&version=GBmaster

	// StatusCancelling "cancelling" - Build is in the process of cancelling.
	StatusCancelling = "cancelling"

	// StatusCompleted "completed" - Build has finished executing and has a
	// result.
	StatusCompleted = "completed"

	// StatusInProgress "inProgress" - Build is currently being executed.
	StatusInProgress = "inProgress"

	// StatusThrottled "throttled" - Build is being throttled
	StatusThrottled = "throttled"

	// StatusPending "pending" - Build is waiting on some external resource
	StatusPending = "pending"

	// StatusNone "none" - Build has no status, should never be shown.
	StatusNone = "none"

	// StatusNotStarted "notStarted" - Build is queued; work has not yet begun.
	StatusNotStarted = "notStarted"

	// Actions Service Run Conclusions
	// https://github.com/github/c2c-actions/blob/master/docs/adrs/1125-support-skipped-as-a-conclusion-for-completed-jobs-and-steps.md
	// https://dev.azure.com/mseng/AzureDevOps/_git/AzDevNext?path=%2FActions%2FRuntime%2FClient%2FWebApi%2FWebApi%2FWorkflowConclusion.cs&_a=contents&version=GBmaster

	// ResultCanceled "canceled" - Build was canceled by a user.
	ResultCanceled = "canceled"

	// ResultFailed  "failed" - Build failed to complete successfully.
	ResultFailed = "failed"

	// ResultNone "none" - Build has no result.
	ResultNone = "none"

	// ResultSkipped "skipped" - Build was skipped.
	ResultSkipped = "skipped"

	// ResultPartiallySucceeded "partiallySucceeded" - Build compiled but there
	// were errors executing.
	ResultPartiallySucceeded = "partiallySucceeded"

	// ResultSucceeded - Build finished successfully.
	ResultSucceeded = "succeeded"
)
