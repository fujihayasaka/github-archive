package types

import "time"

type WorkflowInvocationOwner struct {
	GlobalID                    GlobalID
	DatabaseID                  int64
	Type                        string
	Name                        string
	CreatedAt                   time.Time
	EnterpriseManagedBusinessID GlobalID
}

type WorkflowInvocationPlanOwner struct {
	GlobalID   GlobalID
	Name       string
	PlanName   string
	Type       string
	CustomerID *int64
}

type WorkflowInvocationData struct {
	AllowsAllActions                   bool
	IsActionsDisabledAtAnyLevel        bool
	IsActionsDisabledByOwner           bool
	HasHostedRunnerCustomImagesEnabled bool
	ActionInvocationBlocked            bool
	ActionsCacheSizeLimit              uint64
	ActionsRetentionLimit              int64
	ForkPRWorkflowsPolicy              ForkPRWorkflowsPolicy
	PublicForkPRWorkflowsPolicy        PublicForkPRWorkflowsPolicy
	DefaultWorkflowPermissions         DefaultWorkflowPermissions
	NWO                                RepositoryFullName
	OidcSubClaimCustomizationTemplate  string
	CustomizeEnterpriseOidcIssuer      bool
	FeatureFlags                       InvokerFeatureFlags
	WorkflowFeatureFlags               WorkflowFeatureFlags
	RepoIsPrivate                      bool
	RepoIsFork                         bool
	RepoIsAdvisoryWorkspace            bool
	RepoSelfHostedRunnersDisabled      bool
	PipelineFiles                      []ResolvedFile
	Owner                              WorkflowInvocationOwner
	PlanOwner                          WorkflowInvocationPlanOwner
	RepoDatabaseID                     int64
	RepoGlobalID                       GlobalID
	RepoGitURL                         string
	Actor                              WorkflowInvocationActorData
	References                         WorkflowInvocationReferences
	ParentRepositoryNWO                RepositoryFullName
	Visibility                         string
}

type WorkflowInvocationReferences struct {
	// EventCommit references the commit and reference which most
	// calls/services use to to reference the event - Check Suites, Database etc.
	EventCommit WorkflowInvocationReference
	// CheckoutCommit references the commit and reference which should be checked out
	// by the provider, a merge commit for instance in the context of a PR.
	CheckoutCommit WorkflowInvocationReference
	// CheckoutRefProtected references the ref of the CheckoutCommit is protected or not.
	CheckoutRefProtected bool
}

type WorkflowInvocationReference struct {
	CommitSHA CommitSha
	GitRef    GitRef
}

// IsZeroValue checks to see if both the sha and ref are blank.
func (w WorkflowInvocationReference) IsZeroValue() bool {
	return w.CommitSHA.IsZeroValue() && w.GitRef.IsZeroValue()
}

func NewWorkflowInvocationReference(sha CommitSha, ref GitRef) WorkflowInvocationReference {
	return WorkflowInvocationReference{
		CommitSHA: sha,
		GitRef:    ref,
	}
}

// WorkflowInvocationActorData contains the Actor information/data
type WorkflowInvocationActorData struct {
	ActionInvocationBlocked bool
	IsSpammy                bool
	NoVerifiedEmail         bool
	Type                    string
	DatabaseID              int64
	GlobalID                GlobalID
}
