package events

import (
	"context"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
)

type NoopHandler struct {
	MockOnPullRequestReviewSubmit    func(ctx context.Context, event PullRequestReviewSubmitEvent) error
	MockOnPullRequestCommentCreated  func(ctx context.Context, event PullRequestCommentCreatedEvent) error
	MockOnPullRequestStateChanged    func(ctx context.Context, event PullRequestStateChangedEvent) error
	MockOnPullRequestOpened          func(ctx context.Context, event PullRequestOpenedEvent) error
	MockOnPullRequestSynchronize     func(ctx context.Context, event PullRequestSynchronizeEvent) error
	MockOnWorkflowRunCompleted       func(ctx context.Context, event WorkflowRunCompletedEvent) error
	MockOnWorkflowRunFailed          func(ctx context.Context, event WorkflowRunCompletedEvent) error
	MockOnCodeScanningAlertsAssigned func(ctx context.Context, event CodeScanningAlertsAssignmentEvent) error
	MockOnIssueCreated               func(ctx context.Context, event IssueCreatedEvent) error
	MockOnMergeConflict              func(ctx context.Context, event MergeConflictEvent) error
	MockOnAutomationRunRequested     func(ctx context.Context, event AutomationRunRequestedEvent) error
	MockCopilotSWEAgentEnabled       func(ctx context.Context, repoID uint64) bool
	MockProcess                      func(ctx context.Context, event sweagentd.Event) error
	MockHasAssignmentForPR           func(ctx context.Context, ownerID, repoID int64, pr *PullRequest) (bool, error)
	MockObservability                observability.Exporters
	MockGitHubClientFactory          github.ClientFactoryInterface
}

func (nh *NoopHandler) OnPullRequestReviewSubmit(ctx context.Context, event PullRequestReviewSubmitEvent) error {
	if nh.MockOnPullRequestReviewSubmit != nil {
		return nh.MockOnPullRequestReviewSubmit(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) OnPullRequestCommentCreated(ctx context.Context, event PullRequestCommentCreatedEvent) error {
	if nh.MockOnPullRequestCommentCreated != nil {
		return nh.MockOnPullRequestCommentCreated(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) OnPullRequestStateChanged(ctx context.Context, event PullRequestStateChangedEvent) error {
	if nh.MockOnPullRequestStateChanged != nil {
		return nh.MockOnPullRequestStateChanged(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) OnPullRequestOpened(ctx context.Context, event PullRequestOpenedEvent) error {
	if nh.MockOnPullRequestOpened != nil {
		return nh.MockOnPullRequestOpened(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) OnPullRequestSynchronize(ctx context.Context, event PullRequestSynchronizeEvent) error {
	if nh.MockOnPullRequestSynchronize != nil {
		return nh.MockOnPullRequestSynchronize(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) OnWorkflowRunCompleted(ctx context.Context, event WorkflowRunCompletedEvent) error {
	if nh.MockOnWorkflowRunCompleted != nil {
		return nh.MockOnWorkflowRunCompleted(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) OnWorkflowRunFailed(ctx context.Context, event WorkflowRunCompletedEvent) error {
	if nh.MockOnWorkflowRunFailed != nil {
		return nh.MockOnWorkflowRunFailed(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) OnCodeScanningAlertsAssigned(ctx context.Context, event CodeScanningAlertsAssignmentEvent) error {
	if nh.MockOnCodeScanningAlertsAssigned != nil {
		return nh.MockOnCodeScanningAlertsAssigned(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) OnIssueCreated(ctx context.Context, event IssueCreatedEvent) error {
	if nh.MockOnIssueCreated != nil {
		return nh.MockOnIssueCreated(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) OnMergeConflict(ctx context.Context, event MergeConflictEvent) error {
	if nh.MockOnMergeConflict != nil {
		return nh.MockOnMergeConflict(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) OnAutomationRunRequested(ctx context.Context, event AutomationRunRequestedEvent) error {
	if nh.MockOnAutomationRunRequested != nil {
		return nh.MockOnAutomationRunRequested(ctx, event)
	}
	return nil
}

func (nh *NoopHandler) CopilotSWEAgentEnabled(ctx context.Context, repoID uint64) bool {
	if nh.MockCopilotSWEAgentEnabled != nil {
		return nh.MockCopilotSWEAgentEnabled(ctx, repoID)
	}
	return true
}

func (nh *NoopHandler) Process(ctx context.Context, event sweagentd.Event) error {
	if nh.MockProcess != nil {
		return nh.MockProcess(ctx, event)
	}

	obsv := nh.MockObservability
	if obsv.Reporter == nil || obsv.Logger == nil {
		obsv = observability.NewNoopExporters()
	}
	ghFactory := nh.MockGitHubClientFactory
	if ghFactory == nil {
		ghFactory = &github.NoopClientFactory{}
	}
	err := processEvent(ctx, nh, event)
	if err != nil {
		return jobutils.HandleErrorByType(ctx, obsv, ghFactory, nil, err)
	}
	return nil
}

func (nh *NoopHandler) HasAssignmentForPR(ctx context.Context, ownerID, repoID int64, pr *PullRequest) (bool, error) {
	if nh.MockHasAssignmentForPR != nil {
		return nh.MockHasAssignmentForPR(ctx, ownerID, repoID, pr)
	}
	return false, nil
}
