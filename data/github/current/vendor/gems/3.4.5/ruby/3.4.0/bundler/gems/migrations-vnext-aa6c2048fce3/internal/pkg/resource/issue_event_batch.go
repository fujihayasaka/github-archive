package resource

import (
	"context"
	"fmt"
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type issueEventBatch struct {
	baseBatchHandler
	pb        *v1.IssueEventBatch
	failedIDs idSet
}

var _ batchHandler = (*issueEventBatch)(nil)

func newIssueEventBatch(pb *v1.IssueEventBatch, logger log.Logger) *issueEventBatch {
	return &issueEventBatch{
		baseBatchHandler: baseBatchHandler{logger},
		pb:               pb,
		failedIDs:        make(idSet),
	}
}

func (i *issueEventBatch) batchID() string {
	return i.pb.ResourceId
}

func (i *issueEventBatch) itemIDs() []string {
	var ids []string
	for _, e := range i.pb.Events {
		ids = append(ids, e.ResourceId)
	}
	return ids
}

func (i *issueEventBatch) dependencies(loaded idSet) (*transformedDeps, error) {
	deps := newTransformedDeps()
	for _, e := range i.pb.Events {
		if _, ok := loaded[e.ResourceId]; ok {
			continue
		}
		k, err := keys.ToIssueEventKey(e.ResourceId)
		if err != nil {
			return nil, fmt.Errorf("could not parse issue event key: %w", err)
		}
		deps.int64Deps.Add(k.RepositoryKey.String())
		deps.strDeps.Add(e.ActorResourceId)
		if e.SubjectUserResourceId != "" {
			deps.strDeps.Add(e.SubjectUserResourceId)
		}
		if e.SubjectIssueResourceId != "" {
			deps.int64Deps.Add(e.SubjectIssueResourceId)
		}
		if e.SubjectPullRequestResourceId != "" {
			deps.int64Deps.Add(e.SubjectPullRequestResourceId)
		}
		if e.CommitRepositoryResourceId != "" {
			deps.int64Deps.Add(e.CommitRepositoryResourceId)
		}
	}
	return deps, nil
}

func (i *issueEventBatch) load(ctx context.Context, importer client.Importer, loaded idSet, resolved resolvedIDsByResource) error {
	// Add the events to the batch
	var events []*octov1.TimelineEvent
	for _, e := range i.pb.Events {
		if _, ok := loaded[e.ResourceId]; ok {
			continue
		}
		k, err := keys.ToIssueEventKey(e.ResourceId)
		if err != nil {
			return fmt.Errorf("could not parse issue event k: %w", err)
		}
		var subject string
		switch {
		case e.SubjectUserResourceId != "":
			subject = resolved[e.SubjectUserResourceId].strVal
		case e.SubjectIssueResourceId != "":
			issueID := resolved[e.SubjectIssueResourceId].int64Val
			subject = strconv.FormatInt(issueID, 10)
		case e.SubjectPullRequestResourceId != "":
			issueID := resolved[e.SubjectPullRequestResourceId].int64Val
			subject = strconv.FormatInt(issueID, 10)
		}
		var refNumber int64
		if e.ReferencingPullRequestResourceId != "" {
			prK, err := keys.ToPullRequestKey(e.ReferencingPullRequestResourceId)
			if err != nil {
				return fmt.Errorf("could not parse pull request key: %w", err)
			}
			refNumber = prK.Number
		}
		var commitRepoID int64
		if e.CommitRepositoryResourceId != "" {
			commitRepoID = resolved[e.CommitRepositoryResourceId].int64Val
		}
		// Add the event to the batch
		events = append(events, &octov1.TimelineEvent{
			Actor:                  resolved[e.ActorResourceId].strVal,
			Subject:                subject,
			RepositoryId:           resolved[k.RepositoryKey.String()].int64Val,
			CommitRepositoryId:     commitRepoID,
			CommitId:               e.CommitId,
			BeforeCommitOid:        e.BeforeCommitOid,
			AfterCommitOid:         e.AfterCommitOid,
			Ref:                    e.Ref,
			IssueNumber:            k.Number,
			ReferencingIssueNumber: refNumber,
			Event:                  e.Event,
			CreatedAt:              e.CreatedAt,
			LabelName:              e.LabelName,
			TitleWas:               e.TitleWas,
			TitleIs:                e.TitleIs,
			MilestoneTitle:         e.MilestoneTitle,
			ColumnName:             e.ColumnName,
			PreviousColumnName:     e.PreviousColumnName,
			LockReason:             e.LockReason,
			BlockDurationDays:      e.BlockDurationDays,
			Message:                e.Message,
		})
	}

	// If there are no events, return early
	if len(events) == 0 {
		return nil
	}

	// Import the batch and save response for later
	req := &octov1.ImportTimelineEventsRequest{TimelineEvents: events}
	res, err := importer.ImportTimelineEvent(ctx, req)
	if err != nil {
		i.logger.WithError(err).Error("failed to import issue event batch", kvp.Any("request", req))
		return fmt.Errorf("failed to load issue event batch: %w", err)
	}

	// If all events were imported successfully, we are done
	if len(res.BatchValidationErrors) == 0 {
		return nil
	}

	// Some events failed to be imported, return a partial batch error containing the validation errors
	// and the IDs of the items that failed
	items, err := toFailedItems(res.BatchValidationErrors, i.pb.Events)
	if err != nil {
		return fmt.Errorf("failed to get failed indices: %w", err)
	}
	for _, e := range items {
		i.failedIDs[e.ResourceId] = struct{}{}
	}
	for _, failed := range res.BatchValidationErrors {
		i.logger.Error("failed to import issue event",
			kvp.String("error", failed.ErrorMessage),
			kvp.Any("request", req.TimelineEvents[failed.BatchIndex]))
	}
	return &PartialBatchError{toFailedErrors(res.BatchValidationErrors), i.failedIDs}
}

func (i *issueEventBatch) newResolvedIDs() resolvedIDsByResource {
	depVals := make(resolvedIDsByResource)
	for _, e := range i.pb.Events {
		if _, ok := i.failedIDs[e.ResourceId]; ok {
			continue
		}
		depVals[e.ResourceId] = &transformedValues{int64Val: 1}
	}
	return depVals
}
