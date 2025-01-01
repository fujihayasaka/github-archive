package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

type pullRequestReview struct {
	baseBatchHandler
	pb   *v1.PullRequestReview
	key  keys.PullRequestReviewKey
	resp *octov1.ImportPullRequestReviewResponse
}

var _ batchHandler = (*pullRequestReview)(nil)

func newPullRequestReview(pb *v1.PullRequestReview, logger log.Logger) *pullRequestReview {
	return &pullRequestReview{
		baseBatchHandler: baseBatchHandler{logger},
		pb:               pb,
	}
}

func (p *pullRequestReview) batchID() string {
	return p.pb.ResourceId
}

func (p *pullRequestReview) itemIDs() []string {
	ids := set.New[string]()
	for _, t := range p.pb.Threads {
		ids.Add(t.ResourceId)
		for _, c := range t.Comments {
			ids.Add(c.ResourceId)
		}
	}
	return ids.ToSlice()
}

func (p *pullRequestReview) dependencies(_ idSet) (*transformedDeps, error) {
	k, err := keys.ToPullRequestReviewKey(p.pb.ResourceId)
	if err != nil {
		return nil, fmt.Errorf("could not parse pr review key: %w", err)
	}
	p.key = k

	deps := newTransformedDeps()
	deps.int64Deps.Add(k.PullRequestKey.String())
	for _, comment := range p.pb.Comments {
		deps.int64Deps.Add(comment.InReplyToCommentResourceId, comment.PullRequestReviewThreadResourceId)
	}

	deps.strDeps.Add(p.pb.UserResourceId)
	deps.strDeps.Add(p.pb.AttachmentResourceIds...)
	deps.strDeps.Add(k.BaseURL())
	for _, thread := range p.pb.Threads {
		if thread.ResolvedUserResourceId != "" {
			deps.strDeps.Add(thread.ResolvedUserResourceId)
		}
		for _, comment := range thread.Comments {
			deps.strDeps.Add(comment.UserResourceId)
		}
	}
	for _, comment := range p.pb.Comments {
		deps.strDeps.Add(comment.UserResourceId)
	}
	return deps, nil
}

func (p *pullRequestReview) transform(_ idSet, resolved resolvedIDsByResource) error {
	urlMap := make(map[string]string)
	for _, id := range p.pb.AttachmentResourceIds {
		urlMap[id] = resolved[id].strVal
	}

	// transform the body of the pr reviews and pr review comments to replace attachment URLs with the new URLs
	// and rewrite the base URL to the new URL
	rewritePullRequestReviewBodyAttachmentURLs(p.pb, urlMap)

	for i := range p.pb.Threads {
		for j := range p.pb.Threads[i].Comments {
			rewritePullRequestReviewCommentBodyAttachmentURLs(p.pb.Threads[i].Comments[j], urlMap)
			p.pb.Threads[i].Comments[j].Body = rewriteBaseURL(
				p.pb.Threads[i].Comments[j].Body, p.key.BaseURL(), resolved[p.key.BaseURL()].strVal)
		}
	}
	for i := range p.pb.Comments {
		rewritePullRequestReviewCommentBodyAttachmentURLs(p.pb.Comments[i], urlMap)
		p.pb.Comments[i].Body = rewriteBaseURL(
			p.pb.Comments[i].Body, p.key.BaseURL(), resolved[p.key.BaseURL()].strVal)
	}

	p.pb.Body = rewriteBaseURL(p.pb.Body, p.key.BaseURL(), resolved[p.key.BaseURL()].strVal)

	return nil
}

func (p *pullRequestReview) load(ctx context.Context, importer client.Importer, _ idSet, resolved resolvedIDsByResource) error {
	var threads []*octov1.PullRequestReviewThread
	for _, t := range p.pb.Threads {
		var comments []*octov1.PullRequestReviewComment
		for _, c := range t.Comments {
			comments = append(comments, &octov1.PullRequestReviewComment{
				UserLogin: resolved[c.UserResourceId].strVal,
				Body:      c.Body,
				CreatedAt: c.CreatedAt,
			})
		}

		var resolvedUser string
		if t.ResolvedUserResourceId != "" {
			resolvedUser = resolved[t.ResolvedUserResourceId].strVal
		}

		threads = append(threads, &octov1.PullRequestReviewThread{
			ResolvedByUserLogin: resolvedUser,
			ResolvedAt:          t.ResolvedAt,
			Comments:            comments,
			CreatedAt:           t.CreatedAt,
			BaseCommitId:        t.BaseCommitId,
			CommitId:            t.CommitId,
			Path:                t.Path,
			Line:                t.EndLine.GetValue(),
			Side:                octov1.PullRequestReviewDiffSideType(t.EndSide),
			StartLine:           t.StartLine,
			StartSide:           octov1.PullRequestReviewDiffSideType(t.StartSide),
			DiffHunk:            t.DiffHunk,
			Position:            t.Position,
			OriginalPosition:    t.OriginalPosition,
			SubjectType:         octov1.PullRequestReviewSubjectType(t.SubjectType),
			StartPositionOffset: t.StartPositionOffset,
			BlobPosition:        t.BlobPosition,
			Outdated:            t.Outdated,
		})
	}

	var comments []*octov1.PullRequestReviewComment
	for _, c := range p.pb.Comments {
		comments = append(comments, &octov1.PullRequestReviewComment{
			UserLogin: resolved[c.UserResourceId].strVal,
			Body:      c.Body,
			CreatedAt: c.CreatedAt,
			ReplyToId: wrapperspb.Int64(resolved[c.InReplyToCommentResourceId].int64Val),
			ThreadId:  wrapperspb.Int64(resolved[c.PullRequestReviewThreadResourceId].int64Val),
		})
	}

	req := &octov1.ImportPullRequestReviewRequest{
		UserLogin:     resolved[p.pb.UserResourceId].strVal,
		PullRequestId: resolved[p.key.PullRequestKey.String()].int64Val,
		CreatedAt:     p.pb.CreatedAt,
		SubmittedAt:   p.pb.SubmittedAt,
		HeadSha:       p.pb.HeadSha,
		State:         octov1.PullRequestReviewState(p.pb.State),
		Threads:       threads,
		Comments:      comments,
	}

	if p.pb.Body != "" {
		req.Body = wrapperspb.String(p.pb.Body)
	}

	res, err := importer.ImportPullRequestReview(ctx, req)
	if err != nil {
		p.logger.WithError(err).Error("failed to import pr review", kvp.Any("request", req))
		return fmt.Errorf("failed to load pr review: %w", err)
	}
	p.resp = res

	return nil
}

func (p *pullRequestReview) newResolvedIDs() resolvedIDsByResource {
	r := resolvedIDsByResource{
		p.batchID(): &transformedValues{
			int64Val: p.resp.PullRequestReview.Id,
		},
	}
	for i := range p.resp.PullRequestReview.ReviewThreads {
		r[p.pb.Threads[i].ResourceId] = &transformedValues{
			int64Val: p.resp.PullRequestReview.ReviewThreads[i].Id,
		}
		for j := range p.resp.PullRequestReview.ReviewThreads[i].ReviewComments {
			r[p.pb.Threads[i].Comments[j].ResourceId] = &transformedValues{
				int64Val: p.resp.PullRequestReview.ReviewThreads[i].ReviewComments[j].Id,
			}
		}
	}
	return r
}
