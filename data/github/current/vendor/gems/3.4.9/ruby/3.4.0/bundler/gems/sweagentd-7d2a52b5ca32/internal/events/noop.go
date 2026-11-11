package events

import (
	"context"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
)

type NoopHandler struct {
	MockOnIssueAssigned              func(ctx context.Context, event IssueAssignmentEvent) error
	MockOnIssueUnassigned            func(ctx context.Context, event IssueAssignmentEvent) error
	MockOnPullRequestReviewSubmit    func(ctx context.Context, event PullRequestReviewSubmitEvent) error
	MockOnPullRequestCommentCreated  func(ctx context.Context, event PullRequestCommentCreatedEvent) error
	MockOnPullRequestStateChanged    func(ctx context.Context, event PullRequestStateChangedEvent) error
	MockOnWorkflowRunCompleted       func(ctx context.Context, event WorkflowRunCompletedEvent) error
	MockOnCodeScanningAlertsAssigned func(ctx context.Context, event CodeScanningAlertsAssignmentEvent) error
	MockCopilotSWEAgentEnabled       func(ctx context.Context, repoID uint64) bool
	MockProcess                      func(ctx context.Context, event any) error
	MockObservability                observability.Exporters
	MockGitHubClientFactory          github.ClientFactoryInterface
}

func (nh *NoopHandler) OnIssueAssigned(ctx context.Context, event IssueAssignmentEvent) error {
	if nh.MockOnIssueAssigned != nil {
		return nh.MockOnIssueAssigned(ctx, event)
	}
	return nil
}
func (nh *NoopHandler) OnIssueUnassigned(ctx context.Context, event IssueAssignmentEvent) error {
	if nh.MockOnIssueUnassigned != nil {
		return nh.MockOnIssueUnassigned(ctx, event)
	}
	return nil
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
func (nh *NoopHandler) OnWorkflowRunCompleted(ctx context.Context, event WorkflowRunCompletedEvent) error {
	if nh.MockOnWorkflowRunCompleted != nil {
		return nh.MockOnWorkflowRunCompleted(ctx, event)
	}
	return nil
}
func (nh *NoopHandler) OnCodeScanningAlertsAssigned(ctx context.Context, event CodeScanningAlertsAssignmentEvent) error {
	if nh.MockOnCodeScanningAlertsAssigned != nil {
		return nh.MockOnCodeScanningAlertsAssigned(ctx, event)
	}
	return nil
}
func (nh *NoopHandler) CopilotSWEAgentEnabled(ctx context.Context, repoID uint64) bool {
	if nh.MockCopilotSWEAgentEnabled != nil {
		return nh.MockCopilotSWEAgentEnabled(ctx, repoID)
	}
	return true
}

func (nh *NoopHandler) Process(ctx context.Context, event any) error {
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
		return jobutils.HandleErrorByType(ctx, obsv, ghFactory, err)
	}
	return nil
}
