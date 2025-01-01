package workflowparser

import (
	"context"
	"crypto/sha1"
	"fmt"
	"strings"

	"github.com/github/launch/model"
	"github.com/github/launch/types"
)

type RepositoryMetadata struct {
	TenantID             string
	RepositoryNWO        types.RepositoryFullName
	RepositoryID         types.GlobalID
	RepositoryDatabaseID uint64
	IsTrusted            bool
	PlanOwnerID          types.GlobalID
}

type WorkflowSource interface {
	GetCallerRepoMetadata(context.Context) (*RepositoryMetadata, error)
	GetWorkflowFile(context.Context, model.WorkflowRef, *RepositoryMetadata, int64) (*types.ResolvedFile, *RepositoryMetadata, bool, error)
	SetCallerRepo(types.GlobalID, types.RepositoryFullName, string, string)
	LoadPreviousRunAttemptInfo(context.Context) error
	Clone() WorkflowSource
}

type NullWorkflowSource struct{}

func (NullWorkflowSource) GetCallerRepoMetadata(context.Context) (*RepositoryMetadata, error) {
	return nil, nil
}

func (NullWorkflowSource) GetWorkflowFile(context.Context, model.WorkflowRef, *RepositoryMetadata, int64) (*types.ResolvedFile, *RepositoryMetadata, bool, error) {
	return nil, nil, false, nil
}

func (NullWorkflowSource) SetCallerRepo(types.GlobalID, types.RepositoryFullName, string, string) {}

func (NullWorkflowSource) LoadPreviousRunAttemptInfo(context.Context) error { return nil }

func (NullWorkflowSource) Clone() WorkflowSource { return NullWorkflowSource{} }

type WorkflowDetails struct {
	Content string
	RefType string
	Sha     string
}

type StubWorkflowSource struct {
	CallerRepoID  types.GlobalID
	CallerRepoNWO types.RepositoryFullName
	SourceMap     map[string]WorkflowDetails
	CallerRepoRef string
	CallerRepoSHA string
}

func (wfSrc *StubWorkflowSource) GetCallerRepoMetadata(context.Context) (*RepositoryMetadata, error) {
	return &RepositoryMetadata{
		RepositoryID:  wfSrc.CallerRepoID,
		RepositoryNWO: wfSrc.CallerRepoNWO,
	}, nil
}

func (wfSrc *StubWorkflowSource) GetWorkflowFile(_ context.Context, wfRef model.WorkflowRef, _ *RepositoryMetadata, _ int64) (*types.ResolvedFile, *RepositoryMetadata, bool, error) {
	refPath := wfRef.String()
	if strings.HasPrefix(refPath, "./.github/workflows") {
		// local workflows
		wfRef.Owner = wfSrc.CallerRepoNWO.Owner
		wfRef.Repo = wfSrc.CallerRepoNWO.Name

		if wfRef.Version.String() == "" {
			// Use the SHA for fetching the file
			wfRef.Version.GitRef = &(wfSrc.CallerRepoSHA)
		}
		refPath = wfRef.String()
	}

	workflowDetails, ok := wfSrc.SourceMap[refPath]
	if !ok {
		return nil, nil, false, nil
	}
	h := sha1.New()
	_, _ = h.Write([]byte(workflowDetails.Content))

	prefix := workflowDetails.RefType
	resolvedSHA := workflowDetails.Sha
	if resolvedSHA == "" {
		resolvedSHA = wfRef.Version.String()
	}

	return &types.ResolvedFile{
			Path:        wfRef.String(),
			Text:        workflowDetails.Content,
			Ref:         fmt.Sprintf("%s%s", prefix, wfRef.Version.String()),
			SHA:         resolvedSHA,
			IsTruncated: false,
		}, &RepositoryMetadata{
			RepositoryNWO: wfRef.GetNWO(),
		}, true, nil
}

func (wfSrc *StubWorkflowSource) SetCallerRepo(repoID types.GlobalID, callerNWO types.RepositoryFullName, ref string, sha string) {
	wfSrc.CallerRepoID = repoID
	wfSrc.CallerRepoNWO = callerNWO
	wfSrc.CallerRepoRef = ref
	wfSrc.CallerRepoSHA = sha
}

func (wfSrc *StubWorkflowSource) LoadPreviousRunAttemptInfo(context.Context) error {
	return nil
}

func (wfSrc *StubWorkflowSource) Clone() WorkflowSource {
	clonedWfs := *wfSrc
	clonedWfs.SourceMap = make(map[string]WorkflowDetails)
	for k, v := range wfSrc.SourceMap {
		clonedWfs.SourceMap[k] = v
	}
	return &clonedWfs
}

// Stubbing WorkflowSource to return an error we define within the test/test case
type ErrorWorkflowSource struct {
	Error error
}

func (wfSrc ErrorWorkflowSource) GetCallerRepoMetadata(context.Context) (*RepositoryMetadata, error) {
	return nil, wfSrc.Error
}

func (wfSrc ErrorWorkflowSource) GetWorkflowFile(context.Context, model.WorkflowRef, *RepositoryMetadata, int64) (*types.ResolvedFile, *RepositoryMetadata, bool, error) {
	return nil, nil, false, wfSrc.Error
}

func (wfSrc ErrorWorkflowSource) SetCallerRepo(types.GlobalID, types.RepositoryFullName, string, string) {
}

func (wfSrc ErrorWorkflowSource) LoadPreviousRunAttemptInfo(context.Context) error {
	return nil
}

func (wfSrc ErrorWorkflowSource) Clone() WorkflowSource { return wfSrc }
