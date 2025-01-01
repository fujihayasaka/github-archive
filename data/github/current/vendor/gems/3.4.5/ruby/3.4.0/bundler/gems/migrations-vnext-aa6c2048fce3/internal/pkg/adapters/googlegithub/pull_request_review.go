package googlegithub

import (
	"fmt"
	"maps"
	"slices"
	"strconv"
	"strings"

	mvngithub "github.com/github/migrations-vnext/internal/pkg/github"
	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/shurcooL/githubv4"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// PullRequestReview is a wrapper around the github.PullRequestReview struct which allows us
// to implement our own methods.
type PullRequestReview struct {
	// These fields are populated through the REST API which is our primary source of data.
	Review   github.PullRequestReview
	Comments []*github.PullRequestComment

	// These fields complement the data fetched through the REST API with data fetched through the GraphQL API.
	AugmentedThreads   []*mvngithub.PullRequestReviewThread
	AugmentedCreatedAt githubv4.DateTime
}

// ToV1PullRequestReview converts a googlegithub.PullRequestReview to a v1.PullRequestReview.
// It returns an error if the conversion fails.
//
// Please note that these resources are complex, the logic to convert them is not trivial and is mainly
// based on the logic used by Octoshift.
func (r *PullRequestReview) ToV1PullRequestReview() (*v1.PullRequestReview, error) {
	review := &v1.PullRequestReview{
		ResourceId:     r.Review.GetHTMLURL(),
		UserResourceId: r.Review.GetUser().GetHTMLURL(),
		Body:           r.Review.GetBody(),
		HeadSha:        r.Review.GetCommitID(),
		CreatedAt:      timestamppb.New(r.AugmentedCreatedAt.Time),
		SubmittedAt:    toTimestamp(r.Review.SubmittedAt),
		State:          toReviewState(r.Review.GetState()),
	}

	// Create a map of threads to add comments to
	threads := make(map[string]*v1.PullRequestReviewThread)

	// Create a thread for each comment that is not a reply.
	for _, comment := range r.Comments {
		if comment.InReplyTo != nil {
			continue
		}

		// Create a thread for the comment, this field mapping is based on our understanding of what
		// the Octoshift code does by trying to map the REST API fields and GraphQL fields to Octoshift archive format.
		t := v1.PullRequestReviewThread{
			ResourceId:                  ToThreadResourceID(comment, comment.GetID()),
			PullRequestReviewResourceId: r.Review.GetHTMLURL(),
			CreatedAt:                   toTimestamp(pointer.Of(comment.GetCreatedAt())),
			BaseCommitId:                comment.GetCommitID(),
			CommitId:                    comment.GetOriginalCommitID(),
			Path:                        comment.GetPath(),
			StartSide:                   toPullRequestReviewSide(comment.GetStartSide()),
			EndSide:                     toPullRequestReviewSide(comment.GetSide()),
			DiffHunk:                    setStrIfNotNil(comment.DiffHunk),
			Position:                    setInt64IfNotNil(comment.Position),
			OriginalPosition:            setInt64IfNotNil(comment.OriginalPosition),
			SubjectType:                 toPullRequestReviewSubjectType(comment.GetSubjectType()),

			// Unavailable fields in the REST API. These two fields seem to have an impact on multi-line comments.
			// Without them, for now, the multi-line comments are displayed using the last line of the comment.
			StartPositionOffset: nil, // StartPositionOffset is not available in the REST API
			BlobPosition:        nil, // BlobPosition is not available in the REST API
		}

		if comment.StartLine != nil {
			t.StartLine = &wrapperspb.Int64Value{Value: int64(comment.GetStartLine())}
		} else if comment.OriginalStartLine != nil {
			t.StartLine = &wrapperspb.Int64Value{Value: int64(comment.GetOriginalStartLine())}
		}

		switch {
		case comment.Line != nil:
			t.EndLine = &wrapperspb.Int64Value{Value: int64(comment.GetLine())}
		case comment.OriginalLine != nil:
			t.EndLine = &wrapperspb.Int64Value{Value: int64(comment.GetOriginalLine())}
		default:
			t.EndLine = &wrapperspb.Int64Value{Value: 0}
		}

		// Augment the thread data with the review thread data fetched from the GraphQL API that the REST API
		// does not provide.
		thread := r.findThreadByCommentID(comment.GetID())
		if thread == nil {
			return nil, fmt.Errorf("failed to find thread for comment %d", comment.GetID())
		}
		t.Outdated = thread.IsOutdated
		if thread.IsResolved {
			// ResolvedAt is not available neither in the REST API nor GraphQL API so we use the comment's created at
			t.ResolvedAt = toTimestamp(pointer.Of(comment.GetCreatedAt()))
			t.ResolvedUserResourceId = thread.ResolvedBy.URL.String()
		}

		// Add itself as a comment to the thread as threads always have at least one comment: the root comment.
		t.Comments = append(t.Comments, &v1.PullRequestReviewComment{
			ResourceId:                        ToResourceCommentID(comment, comment.GetID()),
			UserResourceId:                    comment.GetUser().GetHTMLURL(),
			PullRequestReviewResourceId:       r.Review.GetHTMLURL(),
			PullRequestReviewThreadResourceId: t.ResourceId,
			Body:                              comment.GetBody(),
			CreatedAt:                         toTimestamp(pointer.Of(comment.GetCreatedAt())),
		})

		// Add the thread to the map
		threads[t.ResourceId] = &t
	}

	// Add non-root comments to the threads
	for _, comment := range r.Comments {
		// Skip comments that are not replies as they are already added to the threads
		if comment.InReplyTo == nil {
			continue
		}

		// Find the thread that this comment is a reply to
		threadResource := ToThreadResourceID(comment, comment.GetInReplyTo())
		t, ok := threads[threadResource]

		// If the thread is not found, then this is a comment that is a reply to a comment that belongs to  a different review.
		// These comments go in the Comments field of the root review and not in a thread.
		if !ok {
			review.Comments = append(review.Comments, &v1.PullRequestReviewComment{
				ResourceId:                        ToResourceCommentID(comment, comment.GetID()),
				UserResourceId:                    comment.GetUser().GetHTMLURL(),
				PullRequestReviewResourceId:       r.Review.GetHTMLURL(),
				InReplyToCommentResourceId:        ToResourceCommentID(comment, comment.GetInReplyTo()),
				PullRequestReviewThreadResourceId: ToThreadResourceID(comment, comment.GetInReplyTo()),
				Body:                              comment.GetBody(),
				CreatedAt:                         toTimestamp(pointer.Of(comment.GetCreatedAt())),
			})
			continue
		}

		// Add the comment to the thread
		t.Comments = append(t.Comments, &v1.PullRequestReviewComment{
			ResourceId:                        ToResourceCommentID(comment, comment.GetID()),
			UserResourceId:                    comment.GetUser().GetHTMLURL(),
			PullRequestReviewResourceId:       r.Review.GetHTMLURL(),
			PullRequestReviewThreadResourceId: t.ResourceId,
			InReplyToCommentResourceId:        ToResourceCommentID(comment, comment.GetInReplyTo()),
			Body:                              comment.GetBody(),
			CreatedAt:                         toTimestamp(pointer.Of(comment.GetCreatedAt())),
		})
	}

	// Set the threads on the review
	review.Threads = slices.AppendSeq(review.Threads, maps.Values(threads))

	return review, nil
}

// findThreadByCommentID finds a thread that contains a comment with the given commentID.
func (r *PullRequestReview) findThreadByCommentID(commentID int64) *mvngithub.PullRequestReviewThread {
	for _, t := range r.AugmentedThreads {
		if len(t.Comments.Nodes) == 0 {
			continue
		}
		if string(t.Comments.Nodes[0].FullDatabaseID) == strconv.FormatInt(commentID, 10) {
			return t
		}
	}
	return nil
}

// toPullRequestReviewSubjectType converts a string to a v1.PullRequestReviewSubjectType.
func toPullRequestReviewSubjectType(s string) v1.PullRequestReviewSubjectType {
	switch strings.ToLower(s) {
	case "file":
		return v1.PullRequestReviewSubjectType_PULL_REQUEST_REVIEW_SUBJECT_TYPE_FILE
	case "line":
		return v1.PullRequestReviewSubjectType_PULL_REQUEST_REVIEW_SUBJECT_TYPE_LINE
	default:
		return v1.PullRequestReviewSubjectType_PULL_REQUEST_REVIEW_SUBJECT_TYPE_INVALID
	}
}

// toPullRequestReviewSide converts a string to a v1.PullRequestReviewDiffSideType.
func toPullRequestReviewSide(side string) v1.PullRequestReviewDiffSideType {
	switch strings.ToLower(side) {
	case "left":
		return v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_LEFT
	case "right":
		return v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_RIGHT
	default:
		return v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_INVALID
	}
}

// toReviewState converts a string to a v1.PullRequestReviewState.
func toReviewState(state string) v1.PullRequestReviewState {
	switch strings.ToLower(state) {
	case "approved":
		return v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_APPROVED
	case "changes_requested":
		return v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_CHANGES_REQUESTED
	case "commented":
		return v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_COMMENTED
	case "dismissed":
		return v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_DISMISSED
	case "pending":
		return v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_PENDING
	default:
		return v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_INVALID
	}
}

// setStrIfNotNil returns a wrapperspb.StringValue with the value of s if s is not nil.
func setStrIfNotNil(s *string) *wrapperspb.StringValue {
	if s != nil {
		return &wrapperspb.StringValue{
			Value: *s,
		}
	}
	return nil
}

// setInt64IfNotNil returns a wrapperspb.Int64Value with the value of i if i is not nil.
func setInt64IfNotNil(i *int) *wrapperspb.Int64Value {
	if i == nil {
		return nil
	}
	return wrapperspb.Int64(int64(*i))
}

// ToThreadResourceID returns a synthetic resource ID for a thread based on its first comment
func ToThreadResourceID(comment *github.PullRequestComment, id int64) string {
	return fmt.Sprintf("%s-thread-%d", comment.GetPullRequestURL(), id)
}

// ToResourceCommentID returns a synthetic resource ID for a comment based on the comment ID
func ToResourceCommentID(comment *github.PullRequestComment, id int64) string {
	return fmt.Sprintf("%s-comment-%d", comment.GetPullRequestURL(), id)
}
