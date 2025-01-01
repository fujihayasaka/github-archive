package archive

import (
	"testing"
	"time"

	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestPullRequestReviewThread_ToV1PullRequestReviewThread(t *testing.T) {
	now := time.Now()

	type fields struct {
		URL                 string
		PullRequestReview   string
		DiffHunk            *string
		Path                string
		Position            *int64
		OriginalPosition    *int64
		BaseCommitID        string
		CommitID            string
		OriginalCommitID    string
		StartPositionOffset *int64
		BlobPosition        *int64
		StartLine           *int64
		Line                *int64
		StartSide           string
		Side                string
		OriginalStartLine   *int64
		CreatedAt           time.Time
		ResolvedAt          time.Time
		Resolver            string
		SubjectType         string
		Outdated            bool
	}
	tests := []struct {
		name    string
		fields  fields
		want    *v1.PullRequestReviewThread
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "all fields are set",
			fields: fields{
				URL:                 "url",
				PullRequestReview:   "pull_request_review",
				DiffHunk:            pointer.Of("diff_hunk"),
				Path:                "path",
				Position:            pointer.Of(int64(1)),
				OriginalPosition:    pointer.Of(int64(2)),
				BaseCommitID:        "base_commit_id",
				OriginalCommitID:    "original_commit_id",
				CommitID:            "commit_id",
				StartPositionOffset: pointer.Of(int64(3)),
				BlobPosition:        pointer.Of(int64(4)),
				StartLine:           pointer.Of(int64(5)),
				Line:                pointer.Of(int64(6)),
				StartSide:           "right",
				Side:                "left",
				OriginalStartLine:   pointer.Of(int64(7)),
				CreatedAt:           now,
				ResolvedAt:          now,
				Resolver:            "resolver",
				SubjectType:         "line",
				Outdated:            true,
			},
			want: &v1.PullRequestReviewThread{
				ResourceId:                  "url",
				PullRequestReviewResourceId: "pull_request_review",
				ResolvedUserResourceId:      "resolver",
				ResolvedAt:                  timestamppb.New(now),
				CreatedAt:                   timestamppb.New(now),
				BaseCommitId:                "base_commit_id",
				CommitId:                    "original_commit_id",
				Path:                        "path",
				StartLine:                   &wrapperspb.Int64Value{Value: 5},
				EndLine:                     &wrapperspb.Int64Value{Value: 6},
				StartSide:                   v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_RIGHT,
				EndSide:                     v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_LEFT,
				DiffHunk:                    &wrapperspb.StringValue{Value: "diff_hunk"},
				Position:                    &wrapperspb.Int64Value{Value: 1},
				OriginalPosition:            &wrapperspb.Int64Value{Value: 2},
				SubjectType:                 v1.PullRequestReviewSubjectType_PULL_REQUEST_REVIEW_SUBJECT_TYPE_LINE,
				StartPositionOffset:         &wrapperspb.Int64Value{Value: 3},
				BlobPosition:                &wrapperspb.Int64Value{Value: 4},
				Outdated:                    true,
			},
			wantErr: assert.NoError,
		},
		{
			name: "optional fields are not set",
			fields: fields{
				URL:               "url",
				PullRequestReview: "pull_request_review",
				Path:              "path",
				BaseCommitID:      "base_commit_id",
				OriginalCommitID:  "original_commit_id",
				CommitID:          "commit_id",
				StartSide:         "right",
				Side:              "left",
				Resolver:          "resolver",
				SubjectType:       "file",
				Outdated:          true,
			},
			want: &v1.PullRequestReviewThread{
				ResourceId:                  "url",
				PullRequestReviewResourceId: "pull_request_review",
				ResolvedUserResourceId:      "resolver",
				BaseCommitId:                "base_commit_id",
				CommitId:                    "original_commit_id",
				Path:                        "path",
				EndLine:                     wrapperspb.Int64(0),
				StartSide:                   v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_RIGHT,
				SubjectType:                 v1.PullRequestReviewSubjectType_PULL_REQUEST_REVIEW_SUBJECT_TYPE_FILE,
				EndSide:                     v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_LEFT,
				Outdated:                    true,
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &PullRequestReviewThread{
				URL:                 tt.fields.URL,
				PullRequestReview:   tt.fields.PullRequestReview,
				DiffHunk:            tt.fields.DiffHunk,
				Path:                tt.fields.Path,
				Position:            tt.fields.Position,
				OriginalPosition:    tt.fields.OriginalPosition,
				BaseCommitID:        tt.fields.BaseCommitID,
				CommitID:            tt.fields.CommitID,
				OriginalCommitID:    tt.fields.OriginalCommitID,
				StartPositionOffset: tt.fields.StartPositionOffset,
				BlobPosition:        tt.fields.BlobPosition,
				Line:                tt.fields.Line,
				StartLine:           tt.fields.StartLine,
				StartSide:           tt.fields.StartSide,
				Side:                tt.fields.Side,
				OriginalStartLine:   tt.fields.OriginalStartLine,
				CreatedAt:           tt.fields.CreatedAt,
				ResolvedAt:          tt.fields.ResolvedAt,
				Resolver:            tt.fields.Resolver,
				SubjectType:         tt.fields.SubjectType,
				Outdated:            tt.fields.Outdated,
			}
			got, err := r.ToV1PullRequestReviewThread()
			if !tt.wantErr(t, err, "ToV1PullRequestReviewThread()") {
				return
			}
			assert.Equalf(t, tt.want, got, "ToV1PullRequestReviewThread()")
		})
	}
}
