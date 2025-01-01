package build

import (
	"fmt"
	"time"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/services/auth/hkdf"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/requiredworkflowutils"
	"github.com/github/launch/workflowparser"
)

const (
	// from sysexits.h, EX_CONFIG
	DeclinedExitCode = 78
)

// WorkflowBuild represents the complete execution lifecycle of a Flow as a Build
type WorkflowBuild struct {
	// ExecutionID is a unique identifier across launch, provider, and github/github (maps to `uuid`)
	ExecutionID             types.WorkflowExecutionID
	CheckoutSHA             types.CommitSha
	CheckoutRef             types.GitRef
	CheckoutRefProtected    bool
	EventTime               time.Time
	OriginTime              time.Time
	EventPayload            []byte
	RunEnvironment          RunEnvironment
	WorkflowFilePath        string
	ResolvedFiles           []types.ResolvedFile
	ActionsBillingPlanOwner ActionsBillingPlanOwner
	GitHubEvent             flowevents.GitHubEvent
	// WebhookDeliveryID is a unique identifier for the webhook that triggered this build. Can be nil
	// in cases where a build failed to run.
	WebhookDeliveryID *string

	ReferencedFiles map[string]ReferencedFile

	ExternalID           string
	Event                string
	SigningKey           *hkdf.DerivedKey
	AbuseContext         *types.ActionsAbuseTriggerInfo
	RerunInfo            *types.RerunInfo // This is only populated when a workflow is a partial rerun
	PreviousOrchContexts []string         // This is only populated when a workflow is a partial rerun with Run-Service
	CustomerLabel        string
	RootWorkflow         RootWorkflow
	Backend              types.WorkflowBackend
	FileReference        types.WorkflowFileReference
	GitHubTenant         ghtenant.GitHubTenant
}

type RootWorkflow struct {
	FilePath           string
	Ref                string
	SHA                string
	Repository         string
	RepositoryID       types.GlobalID
	IsRequiredWorkflow bool
}

type ReferencedFile struct {
	TenantID             string
	Ref                  string
	SHA                  string
	RepositoryNWO        types.RepositoryFullName
	RepositoryID         types.GlobalID
	RepositoryDatabaseID uint64
	IsTrusted            bool
	PlanOwnerID          types.GlobalID
}

// ActionsBillingPlanOwner defines the entity that is responsible for paying for this workflow build.
type ActionsBillingPlanOwner struct {
	ID                        types.GlobalID
	DatabaseID                int64
	Name                      string
	PlanSKU                   string
	Type                      string
	TenantID                  string
	TenantName                string
	TenantURL                 string
	RepositoryOwnerID         types.GlobalID
	RepositoryOwnerDatabaseID int64
	RepositoryOwnerName       string
	OrganizationTenantID      string
	OrganizationTenantName    string
	OrganizationTenantURL     string
}

func NewWorkflowBuild(
	executionID types.WorkflowExecutionID,
	wf *workflowparser.Workflow,
	runEnv RunEnvironment,
	webhookDeliveryID *string,
	event string,
	eventPayload []byte,
	eventTime time.Time,
	originTime time.Time,
	data *types.WorkflowInvocationData,
	repositoryTenants *types.RepositoryTenants,
	ghe flowevents.GitHubEvent,
	partialAbuseContext *types.PartialAbuseTriggerInfo,
	customerLabel string,
	ghTenant ghtenant.GitHubTenant,
) (*WorkflowBuild, error) {
	resolvedFiles := []types.ResolvedFile{wf.File}
	referencedFiles := map[string]ReferencedFile{}

	eachCalledWorkflow(wf, func(cw *workflowparser.CalledWorkflow) {
		resolvedFiles = append(resolvedFiles, cw.Workflow.File)
		referencedFiles[cw.Workflow.Path] = ReferencedFile{
			SHA:                  cw.Workflow.File.SHA,
			Ref:                  cw.Workflow.File.Ref,
			TenantID:             cw.Metadata.TenantID,
			RepositoryNWO:        cw.Metadata.RepositoryNWO,
			RepositoryID:         cw.Metadata.RepositoryID,
			RepositoryDatabaseID: cw.Metadata.RepositoryDatabaseID,
			IsTrusted:            cw.Metadata.IsTrusted,
			PlanOwnerID:          cw.Metadata.PlanOwnerID,
		}
	})

	actionsBillingPlanOwner, err := mapActionsBillingPlanOwner(repositoryTenants, data.Owner, data.PlanOwner)
	if err != nil {
		return nil, err
	}
	wfb := &WorkflowBuild{
		ExecutionID:             executionID,
		CheckoutSHA:             data.References.CheckoutCommit.CommitSHA,
		CheckoutRef:             data.References.CheckoutCommit.GitRef,
		CheckoutRefProtected:    data.References.CheckoutRefProtected,
		Event:                   event,
		EventTime:               eventTime,
		WebhookDeliveryID:       webhookDeliveryID,
		OriginTime:              originTime,
		EventPayload:            eventPayload,
		RunEnvironment:          runEnv,
		WorkflowFilePath:        wf.Path,
		ResolvedFiles:           resolvedFiles,
		ReferencedFiles:         referencedFiles,
		ActionsBillingPlanOwner: actionsBillingPlanOwner,
		GitHubEvent:             ghe,
		CustomerLabel:           customerLabel,
		RootWorkflow:            mapRootWorkflow(wf, data, runEnv),
		GitHubTenant:            ghTenant,
	}

	if partialAbuseContext != nil {
		wfb.AbuseContext = &types.ActionsAbuseTriggerInfo{
			WorkflowExecutionID:     wfb.ExecutionID.String(),
			WorkflowFilePath:        wfb.WorkflowFilePath,
			TargetRepositoryTier:    int(wfb.RunEnvironment.RepositoryTier),
			PartialAbuseTriggerInfo: *partialAbuseContext,
		}
	} else {
		wfb.AbuseContext = nil
	}

	return wfb, nil
}

func (wfb *WorkflowBuild) GetRootWorkflow() *types.ResolvedFile {
	for _, rf := range wfb.ResolvedFiles {
		if rf.Path == wfb.WorkflowFilePath {
			return &rf
		}
	}
	return nil
}

func (wfb *WorkflowBuild) WorkflowReferencedFiles(coalesceRootFileRef bool) []wfparser.WorkflowReferencedFile {
	wfFiles := []wfparser.WorkflowReferencedFile{}
	for _, file := range wfb.ResolvedFiles {
		nwo := file.RepositoryNwo

		// ReferencedFiles is a map of all the files that were referenced by the workflow
		// and it contains a more accurate RepositoryNWO, meaning it has the correct
		// text case for org/repo names, so if we have a matching one, prefer its NWO.
		if x, ok := wfb.ReferencedFiles[file.Path]; ok {
			nwo = x.RepositoryNWO.String()
		}

		wfFile := wfparser.WorkflowReferencedFile{
			Path:          file.Path,
			Text:          file.Text,
			Ref:           file.Ref,
			SHA:           file.SHA,
			RepositoryNwo: nwo,
			IsRequired:    requiredworkflowutils.IsRequiredWorkflow(file.Path),
		}

		// Fix the ref for the root workflow
		if wfFile.Ref == "" && !wfFile.IsRequired && wfFile.Path == wfb.WorkflowFilePath && coalesceRootFileRef {
			wfFile.Ref = string(wfb.CheckoutRef)
		}

		// TODO: Should this "required/" path stripping be done inside the file provider?
		wfFile.Path = requiredworkflowutils.RemoveMetadataFromRequiredWorkflowPath(file.Path)

		rf, ok := wfb.ReferencedFiles[file.Path]
		if ok {
			wfFile.IsTrusted = rf.IsTrusted
		}

		wfFiles = append(wfFiles, wfFile)
	}

	return wfFiles
}

func eachCalledWorkflow(rootWorkflow *workflowparser.Workflow, f func(*workflowparser.CalledWorkflow)) {
	recurseEachCalledWorkflow(rootWorkflow.CalledWorkflows, f, map[string]struct{}{})
}

func recurseEachCalledWorkflow(calledWorkflows map[string]workflowparser.CalledWorkflow, f func(*workflowparser.CalledWorkflow), set map[string]struct{}) {
	for _, cwf := range calledWorkflows {
		if _, ok := set[cwf.Workflow.Path]; ok {
			continue
		}

		set[cwf.Workflow.Path] = struct{}{}

		f(&cwf)

		recurseEachCalledWorkflow(cwf.Workflow.CalledWorkflows, f, set)
	}
}

func mapActionsBillingPlanOwner(repositoryTenants *types.RepositoryTenants, owner types.WorkflowInvocationOwner, planOwner types.WorkflowInvocationPlanOwner) (ActionsBillingPlanOwner, error) {
	_, databaseID, err := planOwner.GlobalID.Decode()
	if err != nil {
		return ActionsBillingPlanOwner{}, fmt.Errorf("failed to decode billing plan owner id: %w", err)
	}

	actionsBillingPlanOwner := ActionsBillingPlanOwner{
		ID:                        planOwner.GlobalID,
		DatabaseID:                databaseID,
		Name:                      planOwner.Name,
		Type:                      planOwner.Type,
		PlanSKU:                   planOwner.PlanName,
		TenantID:                  repositoryTenants.BillingPlanOwnerTenantID,
		TenantName:                repositoryTenants.BillingPlanOwnerTenantName,
		TenantURL:                 repositoryTenants.BillingPlanOwnerTenantURL,
		RepositoryOwnerID:         owner.GlobalID,
		RepositoryOwnerDatabaseID: owner.DatabaseID,
		RepositoryOwnerName:       owner.Name,
		OrganizationTenantID:      repositoryTenants.OwnerTenantID,
		OrganizationTenantName:    repositoryTenants.OwnerTenantName,
		OrganizationTenantURL:     repositoryTenants.OwnerTenantURL,
	}

	return actionsBillingPlanOwner, nil
}

func mapRootWorkflow(wf *workflowparser.Workflow, data *types.WorkflowInvocationData, runEnv RunEnvironment) RootWorkflow {
	if wf.IsRequiredWorkflow() {
		return RootWorkflow{
			FilePath:           wf.Path,
			SHA:                wf.File.SHA,
			Ref:                wf.File.Ref,
			Repository:         wf.File.RepositoryNwo,
			IsRequiredWorkflow: wf.IsRequiredWorkflow(),
			RepositoryID:       wf.File.RepositoryID,
		}
	}
	return RootWorkflow{
		FilePath:           wf.Path,
		SHA:                data.References.CheckoutCommit.CommitSHA.String(),
		Ref:                data.References.CheckoutCommit.GitRef.String(),
		Repository:         runEnv.Repository.String(),
		IsRequiredWorkflow: wf.IsRequiredWorkflow(),
		RepositoryID:       runEnv.RepositoryID,
	}
}
