package github

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/github/go-kvp"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"
)

var WorkflowsCommitNotFound = terrors.NewRetryable("Commit for workflow files retrieval not found")

// We enable lab for all repos in these orgs
var labEnabledOrgs = map[string]bool{
	// actions-sauron is our e2e testing org, used by automated e2e tests like actions-sauron
	"actions-sauron": true,
	// bbq-beets is where we tend to test stuff
	"bbq-beets": true,
	// bbq-beets-four-nines is where we tend to test stuff with 99.99% uptime
	"bbq-beets-four-nines": true,
	// actions-canary-dependabot is where security checks relating to dependabot execute
	"actions-canary-dependabot": true,
}

/*
sample input data for actions/canary and @spraints:

	{
	  "repo": "R_kgDODBl_BQ",
	  "actorId": "U_kgDNTr4"
	}
*/
var queryDataForWorkflowInvocation = fmt.Sprintf(`query DataForWorkflowInvocation($repo: ID!, $actorId: ID!, $workflowFilesCommit: GitObjectID!, $pipelinesDirExpr: String!) {
  repository:node(id: $repo) {
    ... on Repository {
      id
      allowsAllActions
      actionsCacheSizeLimit
      actionsRetentionLimit
      oidcSubClaimCustomizationTemplate
      customizeEnterpriseOidcIssuer
      forkPrWorkflowsPolicy
      publicForkPrWorkflowsPolicy
      defaultWorkflowPermissions
      launchLabEnabled:isFeatureEnabled(name:"`+LaunchInLabFeatureFlag+`")
      workflowApprovalsUsePRAuthorEnabled:isFeatureEnabled(name:"`+WorkflowApprovalsUsePRAuthorFlag+`")
      skipParserErrorsEnabled:isFeatureEnabled(name:"`+SkipParserErrorsFlag+`")
      isPrivate
      visibility
      name
      databaseId
      gitUrl
      repoSelfHostedRunnersDisabled
      isActionsEligible
      isActionsDisabledAtAnyLevel
      isActionsDisabledByOwner
      actionInvocationBlocked
      isFork
      isAdvisoryWorkspace
      parent {
        name
        owner {
          login
        }
      }
      owner {
        id
        login
        databaseId
        type:__typename
        ... on Organization {
          createdAt
          enterprise {
            id
            managedType
          }
          hasHostedRunnerCustomImagesEnabled
        }
        ... on User {
          createdAt
          enterpriseManagedEnterpriseId
        }
        configurationVariablesEnabled:isFeatureEnabled(name:"`+ConfigurationVariablesEnabledFlag+`")
        sizeRestrictedVarCountEnabled:isFeatureEnabled(name:"`+SizeRestrictedVarCountEnabledFlag+`")
        increasedMaxWorkflowFilesReferencedEnabled:isFeatureEnabled(name:"`+IncreasedMaxWorkflowFilesReferencedEnabledFlag+`")
        customImagesPolicyEnforced:isFeatureEnabled(name:"`+HostedRunnerCustomImagesPolicyEnforced+`")
        workflowApprovalsUsePRAuthorEnabled:isFeatureEnabled(name:"`+WorkflowApprovalsUsePRAuthorFlag+`")
        skipParserErrorsEnabled:isFeatureEnabled(name:"`+SkipParserErrorsFlag+`")
      }
      actionsPlanOwner {
        id
        name
        planName
        type
        customerId
      }
      workflowFilesCommit:object(oid: $workflowFilesCommit) {
        ... on Commit {
          sha: oid
        }
      }
      %s
    }
  }
  actor:node(id: $actorId) {
    type:__typename
    ... on User {
      actionInvocationBlocked
      databaseId
      isSpammy
      noVerifiedEmail
    }
    ... on Organization {
      actionInvocationBlocked
      databaseId
      isSpammy
    }
    ... on Bot {
      databaseId
    }
  }
}`, workflowFilesGQLFragment)

type EnterpriseManagedType string

const (
	EnterpriseManagedTypeDefault           EnterpriseManagedType = "DEFAULT_MANAGED"
	EnterpriseManagedTypeEnterpriseManaged EnterpriseManagedType = "ENTERPRISE_MANAGED"
)

// GetDataForWorkflowInvocation fetches everything we'll need whether we go on to execute any workflows or not
func (c *client) GetDataForWorkflowInvocation(ctx context.Context, repositoryID types.GlobalID, workflowFilesCommit types.CommitSha, actorID types.GlobalID, pipelinesDirectory string) (*types.WorkflowInvocationData, error) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.repo.global_id", string(repositoryID)),
		attribute.String("gh.launch.workflow_files_commit", string(workflowFilesCommit)),
	))
	defer span.End()

	var data struct {
		Repository struct {
			AllowsAllActions            bool                              `json:"allowsAllActions"`
			ActionsCacheSizeLimit       uint64                            `json:"actionsCacheSizeLimit"`
			ActionsRetentionLimit       int64                             `json:"actionsRetentionLimit"`
			ForkPRWorkflowsPolicy       types.ForkPRWorkflowsPolicy       `json:"forkPrWorkflowsPolicy"`
			PublicForkPRWorkflowsPolicy types.PublicForkPRWorkflowsPolicy `json:"publicForkPrWorkflowsPolicy"`
			DefaultWorkflowPermissions  types.DefaultWorkflowPermissions  `json:"defaultWorkflowPermissions"`

			// Repository Feature Flags
			LaunchLabEnabled                      bool `json:"launchLabEnabled"`
			RunServiceSyncCheckRunCreationEnabled bool `json:"runServiceSyncCheckRunCreationEnabled"`
			WorkflowApprovalsUsePRAuthorEnabled   bool `json:"workflowApprovalsUsePRAuthorEnabled"`
			SkipParserErrorsEnabled               bool `json:"skipParserErrorsEnabled"`

			IsPrivate                         bool           `json:"isPrivate"`
			Visibility                        string         `json:"visibility"`
			IsFork                            bool           `json:"isFork"`
			IsAdvisoryWorkspace               bool           `json:"isAdvisoryWorkspace"`
			DatabaseID                        int64          `json:"databaseId"`
			GitURL                            string         `json:"gitUrl"`
			GlobalID                          types.GlobalID `json:"id"`
			IsActionsEligible                 bool           `json:"isActionsEligible"`
			IsActionsDisabledAtAnyLevel       bool           `json:"isActionsDisabledAtAnyLevel"`
			IsActionsDisabledByOwner          bool           `json:"isActionsDisabledByOwner"`
			ActionInvocationBlocked           bool           `json:"actionInvocationBlocked"`
			OidcSubClaimCustomizationTemplate string         `json:"oidcSubClaimCustomizationTemplate"`
			CustomizeEnterpriseOidcIssuer     bool           `json:"customizeEnterpriseOidcIssuer"`
			RepoSelfHostedRunnersDisabled     bool           `json:"repoSelfHostedRunnersDisabled"`
			Owner                             struct {
				ID         types.GlobalID `json:"id"`
				Login      string         `json:"login"`
				DatabaseID int64          `json:"databaseId"`
				Type       string         `json:"type"`
				CreatedAt  time.Time      `json:"createdAt"`

				// Repository Owner Feature Flags
				ConfigurationVariablesEnabled              bool `json:"configurationVariablesEnabled"`
				SizeRestrictedVarCountEnabled              bool `json:"sizeRestrictedVarCountEnabled"`
				IncreasedMaxWorkflowFilesReferencedEnabled bool `json:"increasedMaxWorkflowFilesReferencedEnabled"`
				CustomImagesPolicyEnforced                 bool `json:"customImagesPolicyEnforced"`
				WorkflowApprovalsUsePRAuthorEnabled        bool `json:"workflowApprovalsUsePRAuthorEnabled"`
				SkipParserErrorsEnabled                    bool `json:"skipParserErrorsEnabled"`

				// Only present for users
				EnterpriseManagedBusinessID types.GlobalID `json:"enterpriseManagedEnterpriseId"`
				// Only present for orgs
				Enterprise struct {
					ID          types.GlobalID        `json:"id"`
					ManagedType EnterpriseManagedType `json:"managedType"`
				}
				HasHostedRunnerCustomImagesEnabled bool `json:"hasHostedRunnerCustomImagesEnabled"`
			} `json:"owner"`
			PlanOwner struct {
				ID         types.GlobalID `json:"id"`
				Name       string         `json:"name"`
				PlanName   string         `json:"planName"`
				Type       string         `json:"type"`
				CustomerID *int64         `json:"customerId"`
			} `json:"actionsPlanOwner"`
			Name   string `json:"name"`
			Parent *struct {
				Name  string `json:"name"`
				Owner struct {
					Login string `json:"login"`
				} `json:"owner"`
			} `json:"parent"`
			WorkflowFilesCommit struct {
				Sha types.CommitSha `json:"sha"`
			} `json:"workflowFilesCommit"`
			PipelinesDirectory pipelinesDirResult `json:"pipelinesDirectory"`
		} `json:"repository"`
		Actor struct {
			Type                    string `json:"type"`
			ActionInvocationBlocked bool   `json:"actionInvocationBlocked"`
			IsSpammy                bool   `json:"isSpammy"`
			NoVerifiedEmail         bool   `json:"noVerifiedEmail"`
			DatabaseID              int64  `json:"databaseId"`
		} `json:"actor"`
	}

	variables := map[string]any{
		"repo":                repositoryID,
		"actorId":             actorID,
		"workflowFilesCommit": workflowFilesCommit,
		"pipelinesDirExpr":    pathAtCommitExpression(pipelinesDirectory, workflowFilesCommit),
	}

	optHeaders := http.Header{}
	optHeaders = c.setSerializeLoginHeader(optHeaders, ghtenant.SerializeLoginDisplay)

	_, err := c.do(ctx, "GetDataForWorkflowInvocation", "query", queryDataForWorkflowInvocation, variables, &data, optHeaders)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	nwo := types.RepositoryFullName{Owner: data.Repository.Owner.Login, Name: data.Repository.Name}

	// If we can't find the commit, something's wrong.
	// If we see this frequently we can add in-job retries or escalate to git-systems team.
	if data.Repository.WorkflowFilesCommit.Sha == "" {
		if len(data.Repository.PipelinesDirectory.Entries) == 0 {
			c.obs.Error(ctx, "Commit for workflow files retrieval not found", kvp.String("gh.launch.workflow_files.commit_sha", workflowFilesCommit.String()))

			return nil, tracing.RecordError(span, WorkflowsCommitNotFound)
		}

		c.obs.Debug(ctx, "Internal inconsistency in graphql result. Workflow files found, but not the commit.",
			kvp.String("gh.repo.name_with_owner", nwo.String()),
			kvp.String("gh.launch.workflow_files.commit_sha", workflowFilesCommit.String()))
	}

	pipelineFiles := mapPipelineFiles(data.Repository.PipelinesDirectory.Entries, pipelinesDirectory, data.Repository.GlobalID, nwo, data.Repository.WorkflowFilesCommit.Sha)

	c.obs.Debug(ctx, "Retrieved workflow files",
		kvp.String("gh.repo.name_with_owner", nwo.String()),
		kvp.String("gh.launch.workflow_files.commit_sha", workflowFilesCommit.String()),
		kvp.String("gh.launch.workflow.directory.name", pipelinesDirectory),
		kvp.Int("gh.launch.workflow.directory.count", len(data.Repository.PipelinesDirectory.Entries)),
		kvp.Int("gh.launch.workflows_found.count", len(pipelineFiles)))

	labEnabled := data.Repository.LaunchLabEnabled
	if labEnabledOrgs[data.Repository.Owner.Login] {
		labEnabled = true
	}

	if data.Repository.Owner.DatabaseID == 0 {
		c.obs.Log(ctx, "encountered default value for owner databaseID")
	}

	var parentRepositoryNWO types.RepositoryFullName

	if data.Repository.Parent != nil {
		parentRepositoryNWO = types.RepositoryFullName{Owner: data.Repository.Parent.Owner.Login, Name: data.Repository.Parent.Name}
	}

	enterpriseManagedBusinessID := data.Repository.Owner.EnterpriseManagedBusinessID
	// If the owner is an org, we need to use the enterprise ID from the org's enterprise.
	if data.Repository.Owner.Enterprise.ID != "" && data.Repository.Owner.Enterprise.ManagedType == EnterpriseManagedTypeEnterpriseManaged {
		enterpriseManagedBusinessID = data.Repository.Owner.Enterprise.ID
	}

	return &types.WorkflowInvocationData{
		AllowsAllActions:                   data.Repository.AllowsAllActions,
		IsActionsDisabledAtAnyLevel:        data.Repository.IsActionsDisabledAtAnyLevel,
		IsActionsDisabledByOwner:           data.Repository.IsActionsDisabledByOwner,
		HasHostedRunnerCustomImagesEnabled: data.Repository.Owner.HasHostedRunnerCustomImagesEnabled,
		ActionsCacheSizeLimit:              data.Repository.ActionsCacheSizeLimit,
		ActionInvocationBlocked:            data.Repository.ActionInvocationBlocked,
		ActionsRetentionLimit:              data.Repository.ActionsRetentionLimit,
		ForkPRWorkflowsPolicy:              data.Repository.ForkPRWorkflowsPolicy,
		PublicForkPRWorkflowsPolicy:        data.Repository.PublicForkPRWorkflowsPolicy,
		DefaultWorkflowPermissions:         data.Repository.DefaultWorkflowPermissions,
		FeatureFlags: types.InvokerFeatureFlags{
			IsActionsEligible: data.Repository.IsActionsEligible,
			LaunchLabEnabled:  labEnabled,
		},
		WorkflowFeatureFlags: types.WorkflowFeatureFlags{
			IncreasedMaxWorkflowFilesReferencedEnabled: data.Repository.Owner.IncreasedMaxWorkflowFilesReferencedEnabled,
			ConfigurationVariablesEnabled:              data.Repository.Owner.ConfigurationVariablesEnabled,
			SizeRestrictedVarCountEnabled:              data.Repository.Owner.SizeRestrictedVarCountEnabled,
			CustomImagesPolicyEnforced:                 data.Repository.Owner.CustomImagesPolicyEnforced,
			WorkflowApprovalsUsePRAuthorEnabled:        data.Repository.Owner.WorkflowApprovalsUsePRAuthorEnabled || data.Repository.WorkflowApprovalsUsePRAuthorEnabled,
			SkipParserErrorsEnabled:                    data.Repository.Owner.SkipParserErrorsEnabled || data.Repository.SkipParserErrorsEnabled,
		},
		NWO:                               nwo,
		OidcSubClaimCustomizationTemplate: data.Repository.OidcSubClaimCustomizationTemplate,
		CustomizeEnterpriseOidcIssuer:     data.Repository.CustomizeEnterpriseOidcIssuer,
		RepoGlobalID:                      data.Repository.GlobalID,
		RepoDatabaseID:                    data.Repository.DatabaseID,
		RepoGitURL:                        data.Repository.GitURL,
		RepoSelfHostedRunnersDisabled:     data.Repository.RepoSelfHostedRunnersDisabled,
		Owner: types.WorkflowInvocationOwner{
			GlobalID:                    data.Repository.Owner.ID,
			DatabaseID:                  data.Repository.Owner.DatabaseID,
			Type:                        data.Repository.Owner.Type,
			CreatedAt:                   data.Repository.Owner.CreatedAt,
			Name:                        data.Repository.Owner.Login,
			EnterpriseManagedBusinessID: enterpriseManagedBusinessID,
		},
		PlanOwner: types.WorkflowInvocationPlanOwner{
			GlobalID:   data.Repository.PlanOwner.ID,
			Name:       data.Repository.PlanOwner.Name,
			PlanName:   data.Repository.PlanOwner.PlanName,
			Type:       data.Repository.PlanOwner.Type,
			CustomerID: data.Repository.PlanOwner.CustomerID,
		},
		RepoIsPrivate:           data.Repository.IsPrivate,
		RepoIsFork:              data.Repository.IsFork,
		RepoIsAdvisoryWorkspace: data.Repository.IsAdvisoryWorkspace,
		Visibility:              data.Repository.Visibility,
		PipelineFiles:           pipelineFiles,
		Actor: types.WorkflowInvocationActorData{
			Type:                    data.Actor.Type,
			GlobalID:                actorID,
			ActionInvocationBlocked: data.Actor.ActionInvocationBlocked,
			DatabaseID:              data.Actor.DatabaseID,
			IsSpammy:                data.Actor.IsSpammy,
			NoVerifiedEmail:         data.Actor.NoVerifiedEmail,
		},
		ParentRepositoryNWO: parentRepositoryNWO,
	}, nil
}

func pathAtCommitExpression(path string, sha types.CommitSha) string {
	return fmt.Sprintf("%s:%s", sha, path)
}

func pathAtRef(path string, ref types.GitRef) string {
	return fmt.Sprintf("%s:%s", ref, path)
}
