package diffs

import (
	"testing"
	"time"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	typesv2 "github.com/github/spokes-proto/gen/go/v2/types"
	"github.com/stretchr/testify/require"
)

var (
	oid1                       = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	oid2                       = types.NewObjectID("bb39a3ee5e6b4b0d3255bfef95601890afd80709")
	filepath1                  = types.NewPath([]byte("my/path1"))
	filepath2                  = types.NewPath([]byte("my/path2"))
	item1                      = &SourcePathLineNumbers{SourcePath: filepath1, LineNumbers: []int64{1}}
	item2                      = &SourcePathLineNumbers{SourcePath: filepath2, LineNumbers: []int64{2, 3}}
	items                      = []*SourcePathLineNumbers{item1, item2}
	repository                 = types.NewRepository(1)
	reqCtx                     = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
	reqCtxWithTransactionState = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE, types.WithTransactionState([]byte("transaction")))
	commitOID                  = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	diffPatch                  = []byte("diff --git a/file.txt b/file.txt\n--- a/file.txt\n+++ b/file.txt\n@@ -1 +1 @@\n-old\n+new\n")
	message                    = []byte("commit message")
	author                     = typesv2.NewAttribution([]byte("John Doe"), []byte("john@example.com"), time.Now())
	committer                  = typesv2.NewAttribution([]byte("Jane Smith"), []byte("jane@example.com"), time.Now())
)

func TestGetDiffPositionsRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *GetDiffPositionsRequest
		err  string
	}{
		{
			"empty",
			&GetDiffPositionsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			&GetDiffPositionsRequest{RequestContext: reqCtx, SourceOid: &selectors.RepoObjectIDSelector{Oid: oid1}, TargetOid: &selectors.RepoObjectIDSelector{Oid: oid2}, SourceItems: items},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing source_oid selector",
			&GetDiffPositionsRequest{RequestContext: reqCtx, Repository: repository, TargetOid: &selectors.RepoObjectIDSelector{Oid: oid2}, SourceItems: items},
			"twirp error invalid_argument: source_oid is required",
		},
		{
			"missing target_oid selector",
			&GetDiffPositionsRequest{RequestContext: reqCtx, Repository: repository, SourceOid: &selectors.RepoObjectIDSelector{Oid: oid1}, SourceItems: items},
			"twirp error invalid_argument: target_oid is required",
		},
		{
			"missing source_items selector",
			&GetDiffPositionsRequest{RequestContext: reqCtx, Repository: repository, SourceOid: &selectors.RepoObjectIDSelector{Oid: oid1}, TargetOid: &selectors.RepoObjectIDSelector{Oid: oid2}},
			"twirp error invalid_argument: line_numbers is required",
		},
		{
			"target_id matches source_id",
			&GetDiffPositionsRequest{RequestContext: reqCtx, Repository: repository, SourceOid: &selectors.RepoObjectIDSelector{Oid: oid1}, TargetOid: &selectors.RepoObjectIDSelector{Oid: oid1}, SourceItems: items},
			"twirp error invalid_argument: target_oid must be different from source_oid",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestGetDiffPositionsRequestValidate(t *testing.T) {
	req := NewGetDiffPositionsRequest(reqCtx, repository, &selectors.RepoObjectIDSelector{Oid: oid1}, &selectors.RepoObjectIDSelector{Oid: oid2}, item1, item2)
	require.NoError(t, req.Validate())
}

func TestGetDiffAppliableRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *GetDiffAppliableRequest
		err  string
	}{
		{
			"empty",
			&GetDiffAppliableRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			&GetDiffAppliableRequest{
				RequestContext: reqCtx,
				CommitOid:      commitOID,
				DiffPatch:      diffPatch,
			},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing commit_oid",
			&GetDiffAppliableRequest{
				Repository:     repository,
				RequestContext: reqCtx,
				DiffPatch:      diffPatch,
			},
			"twirp error invalid_argument: commit_oid is required",
		},
		{
			"empty commit_oid.id",
			&GetDiffAppliableRequest{
				Repository:     repository,
				RequestContext: reqCtx,
				CommitOid:      types.NewObjectID(""),
				DiffPatch:      diffPatch,
			},
			"twirp error invalid_argument: object_id.id is required",
		},
		{
			"invalid commit_oid format",
			&GetDiffAppliableRequest{
				Repository:     repository,
				RequestContext: reqCtx,
				CommitOid:      types.NewObjectID("not-a-valid-sha"),
				DiffPatch:      diffPatch,
			},
			"twirp error invalid_argument: object_id.id must be a valid object id",
		},
		{
			"missing diff_patch",
			&GetDiffAppliableRequest{
				Repository:     repository,
				RequestContext: reqCtx,
				CommitOid:      commitOID,
			},
			"twirp error invalid_argument: diff_patch is required",
		},
		{
			"empty diff_patch",
			&GetDiffAppliableRequest{
				Repository:     repository,
				RequestContext: reqCtx,
				CommitOid:      commitOID,
				DiffPatch:      []byte{},
			},
			"twirp error invalid_argument: diff_patch is required",
		},
		{
			"diff_patch exceeds size limit",
			&GetDiffAppliableRequest{
				Repository:     repository,
				RequestContext: reqCtx,
				CommitOid:      commitOID,
				DiffPatch:      make([]byte, maxDiffPatchSize+1),
			},
			"twirp error invalid_argument: diff_patch cannot exceed 10000 bytes",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestGetDiffAppliableRequestValidate(t *testing.T) {
	req := NewGetDiffAppliableRequest(reqCtx, repository, commitOID, diffPatch)
	require.NoError(t, req.Validate())
}

func TestNewGetDiffAppliableRequest(t *testing.T) {
	req := NewGetDiffAppliableRequest(reqCtx, repository, commitOID, diffPatch)

	require.Equal(t, repository, req.GetRepository())
	require.Equal(t, reqCtx, req.GetRequestContext())
	require.Equal(t, commitOID, req.GetCommitOid())
	require.Equal(t, diffPatch, req.GetDiffPatch())
}

func TestCreateCommitFromDiffRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *CreateCommitFromDiffRequest
		err  string
	}{
		{
			"empty",
			&CreateCommitFromDiffRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			&CreateCommitFromDiffRequest{
				RequestContext: reqCtxWithTransactionState,
				DiffPatch:      diffPatch,
				BaseOid:        oid1,
			},
			"twirp error invalid_argument: repository is required",
		},
		{
 			"missing request_context",
 			&CreateCommitFromDiffRequest{
 				Repository: repository,
 				// RequestContext is nil
 				DiffPatch: diffPatch,
 				BaseOid:   oid1,
 				Author:    author,
 				Committer: committer,
 			},
 			"twirp error invalid_argument: request_context is required",
 		},
 		{
			"missing diff_patch",
			&CreateCommitFromDiffRequest{
				Repository:     repository,
				RequestContext: reqCtxWithTransactionState,
				BaseOid:        oid1,
			},
			"twirp error invalid_argument: diff_patch is required",
		},
		{
			"empty diff_patch",
			&CreateCommitFromDiffRequest{
				Repository:     repository,
				RequestContext: reqCtxWithTransactionState,
				BaseOid:        oid1,
				DiffPatch:      []byte{},
				Committer:      committer,
				Author:         author,
			},
			"twirp error invalid_argument: diff_patch is required",
		},
		{
			"diff_patch exceeds size limit",
			&CreateCommitFromDiffRequest{
				Repository:     repository,
				RequestContext: reqCtxWithTransactionState,
				BaseOid:        oid1,
				DiffPatch:      make([]byte, maxDiffPatchSize+1),
				Committer:      committer,
				Author:         author,
			},
			"twirp error invalid_argument: diff_patch cannot exceed 10000 bytes",
		},
		{
			"missing author",
			&CreateCommitFromDiffRequest{
				Repository:     repository,
				RequestContext: reqCtxWithTransactionState,
				BaseOid:        oid1,
				DiffPatch:      diffPatch,
				Author:         nil,
				Committer:      committer,
			},
			"twirp error invalid_argument: author is required",
		},
		{
			"invalid author",
			&CreateCommitFromDiffRequest{
				Repository:     repository,
				RequestContext: reqCtxWithTransactionState,
				BaseOid:        oid1,
				DiffPatch:      diffPatch,
				Author:         &typesv2.Attribution{},
				Committer:      committer,
			},
			"twirp error invalid_argument: attribution.name is required",
		},
		{
			"missing committer",
			&CreateCommitFromDiffRequest{
				Repository:     repository,
				RequestContext: reqCtxWithTransactionState,
				BaseOid:        oid1,
				DiffPatch:      diffPatch,
				Author:         author,
				Committer:      nil,
			},
			"twirp error invalid_argument: committer is required",
		},
		{
			"invalid committer",
			&CreateCommitFromDiffRequest{
				Repository:     repository,
				RequestContext: reqCtxWithTransactionState,
				BaseOid:        oid1,
				DiffPatch:      diffPatch,
				Author:         author,
				Committer:      &typesv2.Attribution{},
			},
			"twirp error invalid_argument: attribution.name is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestCreateCommitFromDiffRequestValidate(t *testing.T) {
	req := NewCreateCommitFromDiffRequest(reqCtxWithTransactionState, repository, diffPatch, oid1, author, committer, message)
	require.NoError(t, req.Validate())
}

func TestNewCreateCommitFromDiffRequest(t *testing.T) {
	req := NewCreateCommitFromDiffRequest(reqCtxWithTransactionState, repository, diffPatch, oid1, author, committer, message)

	require.Equal(t, repository, req.GetRepository())
	require.Equal(t, reqCtxWithTransactionState, req.GetRequestContext())
	require.Equal(t, oid1, req.GetBaseOid())
	require.Equal(t, diffPatch, req.GetDiffPatch())
	require.Equal(t, author, req.GetAuthor())
 	require.Equal(t, committer, req.GetCommitter())
 	require.Equal(t, message, req.GetMessage())
}
