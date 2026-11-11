package events

import (
	"context"

	"github.com/github/sweagentd/internal/requestctx"
)

func (e *IssueAssignmentEvent) AddToRequestContext(ctx context.Context) error {
	if e == nil {
		return nil
	}
	return requestctxAddAll(ctx,
		e.Actor,
		e.Repo,
		e.Issue)
}

func (e *PullRequestReviewSubmitEvent) AddToRequestContext(ctx context.Context) error {
	if e == nil {
		return nil
	}
	return requestctxAddAll(ctx,
		e.Actor,
		e.Repo,
		e.PullRequest,
		e.PullRequestReview)
}

func (e *PullRequestCommentCreatedEvent) AddToRequestContext(ctx context.Context) error {
	if e == nil {
		return nil
	}
	return requestctxAddAll(ctx,
		e.Actor,
		e.Repo,
		e.PullRequest,
		e.Comment)
}

func (e *PullRequestStateChangedEvent) AddToRequestContext(ctx context.Context) error {
	if e == nil {
		return nil
	}
	return requestctxAddAll(ctx,
		e.Actor,
		e.Repo,
		e.PullRequest)
}

func (e *WorkflowRunCompletedEvent) AddToRequestContext(ctx context.Context) error {
	if e == nil {
		return nil
	}
	return requestctxAddAll(ctx,
		e.Repo,
		e.WorkflowRun)
}

func (e *CodeScanningAlertsAssignmentEvent) AddToRequestContext(ctx context.Context) error {
	if e == nil {
		return nil
	}
	return requestctxAddAll(ctx,
		e.Actor,
		e.Repo)
}

// requestctxAddAll adds the provided items to the request context.
// It returns an error if any of the items fail to add.
func requestctxAddAll(ctx context.Context, p ...interface {
	requestctxAdd(ctx context.Context) error
}) error {
	for _, item := range p {
		if item == nil {
			continue
		}
		if err := item.requestctxAdd(ctx); err != nil {
			return err
		}
	}
	return nil
}

func (e *Actor) requestctxAdd(ctx context.Context) error {
	if e == nil {
		return nil
	}
	return requestctx.AddUser(ctx, &requestctx.UserInfo{
		ID:         uint64(e.ID),
		Login:      e.Login,
		TrackingID: e.TrackingID,
	})
}

func (e *Repository) requestctxAdd(ctx context.Context) error {
	if e == nil {
		return nil
	}
	return requestctx.AddRepo(ctx, requestctx.CtxRepo{
		ID:      e.ID,
		OwnerID: e.OwnerID,
	})
}

func (e *Issue) requestctxAdd(ctx context.Context) error {
	if e == nil {
		return nil
	}
	return requestctx.AddIssue(ctx, requestctx.CtxIssue{
		ID:     e.ID,
		Number: e.Number,
	})
}

func (e *PullRequestIssue) requestctxAdd(ctx context.Context) error {
	if e == nil {
		return nil
	}
	state := ""
	if e.IsOpen {
		state = PullRequestStateOpen
	}
	return requestctx.AddPullRequest(ctx, requestctx.CtxPullRequest{
		Number: e.Number,
		State:  state,
	})
}

func (e *PullRequest) requestctxAdd(ctx context.Context) error {
	if e == nil {
		return nil
	}
	ctxPR, ok := requestctx.PullRequest(ctx)
	if ok {
		ctxPR.ID = &e.ID
		ctxPR.Number = e.Number
		ctxPR.State = e.State
		return nil
	}
	return requestctx.AddPullRequest(ctx, requestctx.CtxPullRequest{
		ID:     &e.ID,
		Number: e.Number,
		State:  e.State,
	})
}

func (e *PullRequestReview) requestctxAdd(ctx context.Context) error {
	if e == nil {
		return nil
	}
	ctxPR, ok := requestctx.PullRequest(ctx)
	if ok {
		ctxPR.ReviewID = &e.ID
		return nil
	}
	return requestctx.AddPullRequest(ctx, requestctx.CtxPullRequest{
		ReviewID: &e.ID,
	})
}

func (e *PullRequestComment) requestctxAdd(ctx context.Context) error {
	if e == nil {
		return nil
	}
	ctxPR, ok := requestctx.PullRequest(ctx)
	if ok {
		ctxPR.CommentID = &e.ID
		return nil
	}

	return requestctx.AddPullRequest(ctx, requestctx.CtxPullRequest{
		CommentID: &e.ID,
	})
}

func (e *WorkflowRun) requestctxAdd(ctx context.Context) error {
	if e == nil {
		return nil
	}
	ctxWorkflowRun := &requestctx.CtxWorkflowRun{
		ID: e.ID,
	}
	if e.JobID != nil {
		ctxWorkflowRun.JobID = e.JobID
	}
	return requestctx.AddWorkflowRun(ctx, ctxWorkflowRun)
}

func (e *WorkflowRepository) requestctxAdd(ctx context.Context) error {
	if e == nil {
		return nil
	}
	return requestctx.AddRepo(ctx, requestctx.CtxRepo{
		ID:      e.ID,
		OwnerID: e.OwnerID,
	})
}
