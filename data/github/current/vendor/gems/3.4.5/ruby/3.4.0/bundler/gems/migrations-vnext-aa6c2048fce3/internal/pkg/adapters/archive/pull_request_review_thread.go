package archive

import (
	"strings"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// PullRequestReviewThread represents the structure of the JSON for parsing
type PullRequestReviewThread struct {
	URL                 string    `json:"url"`
	PullRequestReview   string    `json:"pull_request_review"`
	DiffHunk            *string   `json:"diff_hunk"`
	Path                string    `json:"path"`
	Position            *int64    `json:"position"`
	OriginalPosition    *int64    `json:"original_position"`
	CommitID            string    `json:"commit_id"`
	BaseCommitID        string    `json:"base_commit_id"`
	OriginalCommitID    string    `json:"original_commit_id"`
	StartPositionOffset *int64    `json:"start_position_offset"`
	BlobPosition        *int64    `json:"blob_position"`
	StartLine           *int64    `json:"start_line"`
	Line                *int64    `json:"line"`
	OriginalLine        *int64    `json:"original_line"`
	StartSide           string    `json:"start_side"`
	Side                string    `json:"side"`
	OriginalStartLine   *int64    `json:"original_start_line"`
	CreatedAt           time.Time `json:"created_at"`
	ResolvedAt          time.Time `json:"resolved_at"`
	Resolver            string    `json:"resolver"`
	SubjectType         string    `json:"subject_type"`
	Outdated            bool      `json:"outdated"`
}

// ToV1PullRequestReviewThread converts an archive pull request review thread to a v1.PullRequestReviewThread
func (r *PullRequestReviewThread) ToV1PullRequestReviewThread() (*v1.PullRequestReviewThread, error) {
	t := &v1.PullRequestReviewThread{
		ResourceId:                  r.URL,
		PullRequestReviewResourceId: r.PullRequestReview,
		ResolvedUserResourceId:      r.Resolver,
		ResolvedAt:                  toTimestamp(r.ResolvedAt),
		CreatedAt:                   toTimestamp(r.CreatedAt),
		BaseCommitId:                r.BaseCommitID,
		CommitId:                    r.OriginalCommitID,
		Path:                        r.Path,
		StartSide:                   toPullRequestReviewSide(r.StartSide),
		EndSide:                     toPullRequestReviewSide(r.Side),
		DiffHunk:                    setStrIfNotNil(r.DiffHunk),
		Position:                    setInt64IfNotNil(r.Position),
		OriginalPosition:            setInt64IfNotNil(r.OriginalPosition),
		SubjectType:                 toPullRequestReviewSubjectType(r.SubjectType),
		StartPositionOffset:         setInt64IfNotNil(r.StartPositionOffset),
		BlobPosition:                setInt64IfNotNil(r.BlobPosition),
		Outdated:                    r.Outdated,
	}

	if r.StartLine != nil {
		t.StartLine = &wrapperspb.Int64Value{Value: *r.StartLine}
	} else if r.OriginalStartLine != nil {
		t.StartLine = &wrapperspb.Int64Value{Value: *r.OriginalStartLine}
	}

	switch {
	case r.Line != nil:
		t.EndLine = &wrapperspb.Int64Value{Value: *r.Line}
	case r.OriginalLine != nil:
		t.EndLine = &wrapperspb.Int64Value{Value: *r.OriginalLine}
	default:
		t.EndLine = &wrapperspb.Int64Value{Value: 0}
	}

	return t, nil
}

func toPullRequestReviewSide(s string) v1.PullRequestReviewDiffSideType {
	switch strings.ToLower(s) {
	case "left":
		return v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_LEFT
	case "right":
		return v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_RIGHT
	default:
		return v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_INVALID
	}
}

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
