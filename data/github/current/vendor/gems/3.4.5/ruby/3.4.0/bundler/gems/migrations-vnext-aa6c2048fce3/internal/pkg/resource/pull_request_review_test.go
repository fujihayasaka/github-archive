package resource

import (
	"context"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func createPullRequestReview(t *testing.T) *v1.PullRequestReview {
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	return &v1.PullRequestReview{
		ResourceId:     "http://github.test/test-org/test-repo/pull/2/files#pullrequestreview-1",
		UserResourceId: "http://github.test/monalisa",
		Body:           "pr review body",
		HeadSha:        "head_sha",
		CreatedAt:      timestamppb.New(someTime),
		SubmittedAt:    timestamppb.New(someTime),
		State:          v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_COMMENTED,
		Threads: []*v1.PullRequestReviewThread{
			{
				ResourceId:                  "http://github.test/test-org/test-repo/pull/2/files#pullrequestreviewthread-1",
				PullRequestReviewResourceId: "http://github.test/test-org/test-repo/pull/2/files#pullrequestreview-1",
				ResolvedUserResourceId:      "http://github.test/mona",
				ResolvedAt:                  timestamppb.New(someTime),
				CommitId:                    "commit_id",
				Path:                        "path",
				StartLine:                   wrapperspb.Int64(1),
				EndLine:                     wrapperspb.Int64(2),
				StartSide:                   v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_RIGHT,
				EndSide:                     v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_RIGHT,
				DiffHunk:                    wrapperspb.String("diff_hunk"),
				Position:                    wrapperspb.Int64(3),
				OriginalPosition:            wrapperspb.Int64(4),
				SubjectType:                 v1.PullRequestReviewSubjectType_PULL_REQUEST_REVIEW_SUBJECT_TYPE_FILE,
				StartPositionOffset:         wrapperspb.Int64(5),
				Outdated:                    false,
				Comments: []*v1.PullRequestReviewComment{
					{
						ResourceId:                  "http://github.test/test-org/test-repo/pull/2/files#pullrequestreviewcomment-1",
						PullRequestReviewResourceId: "http://github.test/test-org/test-repo/pull/2/files#pullrequestreview-1",
						UserResourceId:              "http://github.test/lisamona",
						Body:                        "comment body",
						CreatedAt:                   timestamppb.New(someTime),
					},
				},
			},
		},
	}
}

func Test_pullRequestReview_itemIDs(t *testing.T) {
	logger := log.NewNullLogger()

	r := createPullRequestReview(t)
	review := newPullRequestReview(r, logger)

	assert.ElementsMatch(t,
		[]string{
			"http://github.test/test-org/test-repo/pull/2/files#pullrequestreviewthread-1",
			"http://github.test/test-org/test-repo/pull/2/files#pullrequestreviewcomment-1",
		},
		review.itemIDs())
}

func Test_pullRequestReview_dependencies(t *testing.T) {
	logger := log.NewNullLogger()

	r := createPullRequestReview(t)
	review := newPullRequestReview(r, logger)

	deps, err := review.dependencies(nil)
	require.NoError(t, err)
	assert.Equal(t,
		&transformedDeps{
			int64Deps: set.FromSlice([]string{"http://github.test/test-org/test-repo/pull/2"}),
			strDeps:   set.FromSlice([]string{"http://github.test/monalisa", "http://github.test", "http://github.test/mona", "http://github.test/lisamona"}),
		},
		deps)
}

func Test_pullRequestReview_transform(t *testing.T) {
	k, err := keys.ToPullRequestReviewKey("https://github.com/test-org/test-repo/pull/2/files#pullrequestreview-1")
	require.NoError(t, err)

	r := &pullRequestReview{
		pb: &v1.PullRequestReview{
			Body:                  "replace this attachmentURL with the new one and https://github.com with the new base URL",
			AttachmentResourceIds: []string{"attachmentURL"},
			Threads: []*v1.PullRequestReviewThread{
				{
					Comments: []*v1.PullRequestReviewComment{
						{
							Body:                  "replace this attachmentURL with the new one and https://github.com with the new base URL",
							AttachmentResourceIds: []string{"attachmentURL"},
						},
					},
				},
			},
			Comments: []*v1.PullRequestReviewComment{
				{
					Body:                  "replace this attachmentURL with the new one and https://github.com with the new base URL",
					AttachmentResourceIds: []string{"attachmentURL"},
				},
			},
		},
		key: k,
	}

	transformedIDs := resolvedIDsByResource{
		"attachmentURL":      {strVal: "newAttachmentURL"},
		"https://github.com": {strVal: "https://github.localhost"},
	}

	err = r.transform(nil, transformedIDs)
	require.NoError(t, err)

	assert.Equal(t,
		"replace this newAttachmentURL with the new one and https://github.localhost with the new base URL",
		r.pb.Body)

	assert.Equal(t, "replace this newAttachmentURL with the new one and https://github.localhost with the new base URL",
		r.pb.Threads[0].Comments[0].Body)

	assert.Equal(t, "replace this newAttachmentURL with the new one and https://github.localhost with the new base URL",
		r.pb.Comments[0].Body)
}

func Test_pullRequestReview_load(t *testing.T) {
	logger := log.NewNullLogger()

	r := createPullRequestReview(t)
	review := newPullRequestReview(r, logger)
	key, err := keys.ToPullRequestReviewKey(review.pb.ResourceId)
	require.NoError(t, err)
	review.key = key

	importer := client.NewDummyImporter(logger)

	resolved := resolvedIDsByResource{
		"http://github.test/test-org/test-repo/pull/2": {int64Val: 1},
		"http://github.test/monalisa":                  {strVal: "monalisa"},
		"http://github.test":                           {strVal: "http://github.com"},
		"http://github.test/mona":                      {strVal: "mona"},
		"http://github.test/lisamona":                  {strVal: "lisamona"},
	}

	err = review.load(context.Background(), importer, nil, resolved)
	require.NoError(t, err)

	expected := &octov1.ImportPullRequestReviewRequest{
		PullRequestId: 1,
		UserLogin:     "monalisa",
		Body:          wrapperspb.String(r.Body),
		State:         octov1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_COMMENTED,
		HeadSha:       r.HeadSha,
		CreatedAt:     r.CreatedAt,
		SubmittedAt:   r.SubmittedAt,
		Threads: []*octov1.PullRequestReviewThread{
			{
				ResolvedByUserLogin: "mona",
				ResolvedAt:          r.Threads[0].ResolvedAt,
				CommitId:            r.Threads[0].CommitId,
				Path:                r.Threads[0].Path,
				Line:                r.Threads[0].EndLine.GetValue(),
				Side:                octov1.PullRequestReviewDiffSideType(r.Threads[0].EndSide),
				StartLine:           r.Threads[0].StartLine,
				DiffHunk:            r.Threads[0].DiffHunk,
				StartSide:           octov1.PullRequestReviewDiffSideType(r.Threads[0].StartSide),
				Position:            r.Threads[0].Position,
				OriginalPosition:    r.Threads[0].OriginalPosition,
				SubjectType:         octov1.PullRequestReviewSubjectType(r.Threads[0].SubjectType),
				StartPositionOffset: r.Threads[0].StartPositionOffset,
				Comments: []*octov1.PullRequestReviewComment{
					{
						UserLogin: "lisamona",
						Body:      r.Threads[0].Comments[0].Body,
						CreatedAt: r.Threads[0].Comments[0].CreatedAt,
					},
				},
			},
		},
	}
	require.Len(t, importer.PullRequestReviews, 1)
	require.Equal(t, expected, importer.PullRequestReviews[0])
}

func Test_pullRequestReview_newResolvedIDs(t *testing.T) {
	logger := log.NewNullLogger()

	r := createPullRequestReview(t)
	review := newPullRequestReview(r, logger)
	review.resp = &octov1.ImportPullRequestReviewResponse{
		PullRequestReview: &octov1.PullRequestReview{
			Id: 1,
			ReviewThreads: []*octov1.PullRequestReviewThreadResponse{
				{
					Id: 2,
					ReviewComments: []*octov1.PullRequestReviewCommentResponse{
						{
							Id: 3,
						},
					},
				},
			},
		},
	}
	resolved := review.newResolvedIDs()

	expected := resolvedIDsByResource{
		"http://github.test/test-org/test-repo/pull/2/files#pullrequestreview-1":        {int64Val: 1},
		"http://github.test/test-org/test-repo/pull/2/files#pullrequestreviewthread-1":  {int64Val: 2},
		"http://github.test/test-org/test-repo/pull/2/files#pullrequestreviewcomment-1": {int64Val: 3},
	}

	assert.Equal(t, expected, resolved)
}
