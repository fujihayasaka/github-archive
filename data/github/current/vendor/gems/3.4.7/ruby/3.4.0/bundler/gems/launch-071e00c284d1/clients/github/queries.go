package github

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/flow/flowfile"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchconfig"

	errs "github.com/pkg/errors"
	"github.com/shurcooL/githubv4"

	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
)

const queryGetDatabaseNWO = `query GetRepositoryNWO($id: ID!) {
  node(id: $id) {
    ... on Repository {
      owner {
        login
      }
      name
    }
  }
}
`

// Resolves a global relay ID to a repository name with owner.
func (c *client) RepositoryNWO(ctx context.Context, globalID types.GlobalID) (types.RepositoryFullName, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	data := struct {
		Node struct {
			Owner struct {
				Login string `json:"login"`
			} `json:"owner"`
			Name string `json:"name"`
		} `json:"node"`
	}{}

	variables := map[string]any{"id": globalID}
	_, err := c.do(ctx, "RepositoryNWO", "query", queryGetDatabaseNWO, variables, &data, nil)
	if err != nil {
		return types.RepositoryFullName{}, err
	}

	node := data.Node
	return types.RepositoryFullName{Owner: node.Owner.Login, Name: node.Name}, nil
}

const queryResolveDefaultBranch = `query ResolveDefaultBranch($id: ID!) {
  repository:node(id: $id) {
    ... on Repository {
      defaultBranch:defaultBranchRef {
        name,
        target {
          commitSha:oid
        }
      }
    }
  }
}
`

func (c *client) ResolveDefaultBranch(ctx context.Context, repositoryID types.GlobalID) (types.CommitSha, types.GitRef, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var data struct {
		Node struct {
			DefaultBranch struct {
				Name   string `json:"name"`
				Target struct {
					CommitSha types.CommitSha `json:"commitSha"`
				} `json:"target"`
			} `json:"defaultBranch"`
		} `json:"repository"`
	}

	variables := map[string]any{
		"id": repositoryID,
	}

	_, err := c.do(ctx, "ResolveDefaultBranch", "query", queryResolveDefaultBranch, variables, &data, nil)
	if err != nil {
		return types.CommitShaZeroValue, types.GitRefZeroValue, err
	}

	commitSha := data.Node.DefaultBranch.Target.CommitSha
	if commitSha.IsZeroValue() && data.Node.DefaultBranch.Name == "" {
		return types.CommitShaZeroValue, types.GitRefZeroValue, errs.New("Unable to default branch")
	}
	gitRef := types.NewBranchRef(data.Node.DefaultBranch.Name)
	return commitSha, gitRef, nil
}

// .repository.ref.target.oid looks like the GitObject query, but `ref` resolves annotated tags as the tag OID (not the target commit)
// .repository.object correctly resolves branches, commits, lightweight and annotated tags to the target commit SHA.
const queryResolveRef = `query ResolveRef($id: ID!, $ref: String!) {
  repository:node(id: $id) {
    ... on Repository {
      ref(qualifiedName: $ref) {
        name
        prefix
      }
      object(expression: $ref) {
        ... on Commit {
          oid
        }
      }
    }
  }
}
`

// ResolveRef spends up to 5 seconds attempting to resolve a ref, retrying to account for replication lag
func (c *client) ResolveRef(ctx context.Context, repositoryID types.GlobalID, ref types.GitRef, opts ...ResolveRefOption) (types.CommitSha, types.GitRef, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var data struct {
		Repository struct {
			Ref struct {
				Name   string `json:"name"`
				Prefix string `json:"prefix"`
			} `json:"ref"`
			Object struct {
				CommitSha types.CommitSha `json:"oid"`
			} `json:"object"`
		} `json:"repository"`
	}

	variables := map[string]any{
		"id":  repositoryID,
		"ref": ref,
	}

	cfg := retryConfig{
		deadline: time.Now().Add(5 * time.Second),
		backoff:  time.Second / 2,
	}
	for _, opt := range opts {
		opt(&cfg)
	}

	count := 0

	for time.Now().Before(cfg.deadline) {
		if count > 0 {
			time.Sleep(cfg.backoff)
			cfg.backoff *= 2
		}

		_, err := c.do(ctx, "ResolveRef", "query", queryResolveRef, variables, &data, nil)
		if err != nil {
			return types.CommitShaZeroValue, types.GitRefZeroValue, err
		}

		resRef := data.Repository.Ref
		commitSha := data.Repository.Object.CommitSha
		if commitSha.IsZeroValue() && resRef.Name == "" {
			count++
			continue
		}
		gitRef := types.GitRef(resRef.Prefix + resRef.Name)
		return commitSha, gitRef, nil
	}

	return types.CommitShaZeroValue, types.GitRefZeroValue, &terrors.RefResolutionError{
		Count: count,
	}
}

const queryIsRefProtected = `query IsRefProtected($id: ID!, $ref: String!) {
	repository:node(id: $id) {
		... on Repository {
			ref(qualifiedName: $ref) {
				name
				prefix
				rules {
					totalCount
		  		}
		  		branchProtectionRule {
					id
				}
			}
		}
	}
}
`

func (c *client) IsRefProtected(ctx context.Context, repositoryID types.GlobalID, ref types.GitRef, opts ...ResolveRefOption) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var data struct {
		Repository struct {
			Ref struct {
				Name   string `json:"name"`
				Prefix string `json:"prefix"`
				Rules  struct {
					TotalCount int `json:"totalCount"`
				} `json:"rules"`
				BranchProtectionRule struct {
					ID string `json:"id"`
				} `json:"branchProtectionRule"`
			} `json:"ref"`
		} `json:"repository"`
	}

	variables := map[string]any{
		"id":  repositoryID,
		"ref": ref,
	}

	cfg := retryConfig{
		deadline: time.Now().Add(5 * time.Second),
		backoff:  time.Second / 2,
	}
	for _, opt := range opts {
		opt(&cfg)
	}

	count := 0

	for time.Now().Before(cfg.deadline) {
		if count > 0 {
			time.Sleep(cfg.backoff)
			cfg.backoff *= 2
		}

		_, err := c.do(ctx, "IsRefProtected", "query", queryIsRefProtected, variables, &data, nil)
		if err != nil {
			return false, err
		}

		resRef := data.Repository.Ref
		if resRef.Name == "" {
			count++
			continue
		}

		gitRefProtected := false
		rulesCount := data.Repository.Ref.Rules.TotalCount
		if data.Repository.Ref.BranchProtectionRule.ID != "" || rulesCount > 0 {
			gitRefProtected = true
		}

		return gitRefProtected, nil
	}

	return false, &terrors.CheckRefProtectedRuleError{
		Count: count,
	}
}

type retryConfig struct {
	deadline time.Time
	backoff  time.Duration
}

// ResolveRefOption modifies the behavior of Client.ResolveRef.
type ResolveRefOption func(*retryConfig)

const queryRepositoryInfoFromID = `query RepositoryInfoFromID($id: ID!) {
  repository: node(id: $id) {
    ... on Repository {
      id
      databaseId
      name
      owner {
        id
        login
      }
      actionsPlanOwner {
        id
      }
    }
  }
}`

type BasicOwnerInfo struct {
	ID types.GlobalID `json:"id"`

	Name string `json:"login"`
}

type BasicPlanOwnerInfo struct {
	ID types.GlobalID `json:"id"`
}

type BasicRepositoryInfo struct {
	ID         types.GlobalID     `json:"id"`
	DatabaseID uint64             `json:"databaseId"`
	Name       string             `json:"name"`
	Owner      BasicOwnerInfo     `json:"owner"`
	PlanOwner  BasicPlanOwnerInfo `json:"actionsPlanOwner"`
}

func (repoInfo *BasicRepositoryInfo) RepositoryFullName() *types.RepositoryFullName {
	return &types.RepositoryFullName{
		Owner: repoInfo.Owner.Name,
		Name:  repoInfo.Name,
	}
}

func (c *client) RepositoryInfoFromID(ctx context.Context, id types.GlobalID) (*BasicRepositoryInfo, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	data := struct {
		Repository BasicRepositoryInfo `json:"repository"`
	}{}

	variables := map[string]any{
		"id": id,
	}

	_, err := c.do(ctx, "RepositoryInfoFromID", "query", queryRepositoryInfoFromID, variables, &data, nil)
	if err != nil {
		return nil, err
	}

	return &data.Repository, nil
}

type RepositoryBillingResponse struct {
	IsStorageAllowed bool
	IsUsageAllowed   bool
	IsOwnerSpammy    bool
}

type SecretPolicies struct {
	CanUseEnvironments    bool
	ForkPRWorkflowsPolicy types.ForkPRWorkflowsPolicy
}

type Policies struct {
	CanUseEnvironments          bool
	ForkPRWorkflowsPolicy       types.ForkPRWorkflowsPolicy
	PublicForkPRWorkflowsPolicy types.PublicForkPRWorkflowsPolicy
}

// Look up information about an invocation of a workflow file
func (c *client) GetReportingMetadata(
	ctx context.Context,
	repositoryID types.GlobalID,
	actorNodeID types.GlobalID,
) (metadata.WorkflowMetadata, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ret := metadata.WorkflowMetadata{}

	query := metadataForWorkflowsQuery

	var rawResults map[string]json.RawMessage
	queryVars := make(map[string]any)
	queryVars["targetRepoId"] = repositoryID
	queryVars["actorId"] = actorNodeID
	_, err := c.do(ctx, "GetReportingMetadata", "query", query, queryVars, &rawResults, nil)
	if err != nil {
		if _, isNotFoundError := err.(*terrors.NotFoundError); !isNotFoundError {
			// Ignore Not Found errors
			// This error can be caused by poorly configured workflows
			// Other actions may have been successfully looked up
			return ret, errs.Wrap(err, "failed to fetch action repos")
		}
	}

	workflowMetadaActor := &metadata.WorkflowMetadataActor{}
	var disableDependabotSecurityEnforcementFeatureFlag bool
	for k, v := range rawResults {
		switch k {
		case "targetRepo":
			var dst repoResult
			if err := json.Unmarshal(v, &dst); err != nil {
				return ret, errs.Wrap(err, "failed to decode targetRepo in result")
			}
			ret.Repository, disableDependabotSecurityEnforcementFeatureFlag = convertRepo(dst)
			ret.RepositoryOwner, _ = convertActor(dst.Owner)
		case "actor":
			var dst actorResult
			if err := json.Unmarshal(v, &dst); err != nil {
				return ret, errs.Wrap(err, "failed to decode actor in result")
			}
			ret.InvokingUser, workflowMetadaActor = convertActor(dst)
		default:
			// Ignore
		}
	}

	if workflowMetadaActor.IsDependabot && (disableDependabotSecurityEnforcementFeatureFlag) {
		c.obs.Log(ctx, "actions_disable_dependabot_enforcement is enabled, not treating the actor as dependabot")
		// This is a quick and dirty way to address customer issues, reasoning and decisions are at https://github.com/github/c2c-actions/blob/master/docs/adrs/2875-addressing-customers-reactions-to-dependabot-limitations.md#option-d-feature-flag-to-opt-out-of-permissions-and-secrets
		// Note that this won't work for deprecated dependabot app (https://github.com/github/dsp/issues/345), because the IsDependabotActor will still be true in that case
		workflowMetadaActor.IsDependabot = false
	}

	ret.Actor = workflowMetadaActor
	return ret, nil
}

func (c *client) GetRepositoryScheduleData(
	ctx context.Context,
	repoNodeID types.GlobalID,
	branchRef types.GitRef,
	actorNodeID types.GlobalID,
	env launchconfig.AppEnv,
) (*RepositoryScheduleData, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	return c.scheduleQuery(ctx, repoNodeID, branchRef, &actorNodeID, env, "GetRepositoryScheduleData")
}

func (c *client) GetCurrentScheduleState(
	ctx context.Context,
	repoGID types.GlobalID,
	env launchconfig.AppEnv,
) (*RepositoryScheduleState, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	data, err := c.scheduleQuery(ctx, repoGID, "HEAD", nil, env, "GetCurrentScheduleState")
	if err != nil {
		return nil, err
	}
	return &data.RepositoryScheduleState, nil
}

// schedule query, handling both getting current state and getting state for a specific event
func (c *client) scheduleQuery(
	ctx context.Context,
	repoNodeID types.GlobalID,
	branchRef types.GitRef,
	actorNodeID *types.GlobalID,
	env launchconfig.AppEnv,
	opname string,
) (*RepositoryScheduleData, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const actorFields = `
		actor:node(id: $actorId) {
			... on Actor {
				login
			}
			... on Node {
				id
			}
		}
		`

	querySetup := struct {
		extraParams strings.Builder
		extraFields strings.Builder
	}{
		extraParams: strings.Builder{},
		extraFields: strings.Builder{},
	}

	if actorNodeID != nil {
		querySetup.extraFields.WriteString(actorFields)
		querySetup.extraParams.WriteString(", $actorId: ID!")
	}

	scheduleDataGQL := fmt.Sprintf(`
		query RepositoryScheduleData($id: ID!, $commitExpression: String!, $pipelinesDirExpr: String! %s) {
			%s
			repository: node(id: $id) {
				... on Repository {
					id
					name
					head: object(expression: $commitExpression) {
						sha: oid
					}
					defaultBranchRef {
						prefix
						name
					}
					owner {
						login
					}
					actionsPlanOwner {
					  id
					}
					%s
				}
			}
		}
	`, querySetup.extraParams.String(), querySetup.extraFields.String(), workflowFilesGQLFragment)

	data := struct {
		Actor struct {
			Login string
			ID    types.GlobalID
		}
		Repository struct {
			ID   types.GlobalID
			Name string
			Head struct {
				Sha types.CommitSha
			}
			DefaultBranchRef struct {
				Prefix string
				Name   string
			}
			Owner struct {
				Login string
			}
			ActionsPlanOwner struct {
				ID types.GlobalID `json:"id"`
			}
			PipelinesDirectory pipelinesDirResult `json:"pipelinesDirectory"`
		}
	}{}

	pipelineDir := flowfile.PipelineDirectoryForEnvironment(env)

	variables := map[string]any{
		"id":               string(repoNodeID),
		"commitExpression": branchRef,
		"pipelinesDirExpr": pathAtRef(pipelineDir, branchRef),
	}
	if actorNodeID != nil {
		variables["actorId"] = *actorNodeID
	}
	_, err := c.do(ctx, opname, "query", scheduleDataGQL, variables, &data, nil)
	if err != nil {
		return nil, err
	}

	repo := data.Repository

	fullRef := fmt.Sprintf("%s%s", repo.DefaultBranchRef.Prefix, repo.DefaultBranchRef.Name)
	nwo := types.RepositoryFullName{Owner: data.Repository.Owner.Login, Name: data.Repository.Name}

	return &RepositoryScheduleData{
		DefaultBranchFullRef: fullRef,
		ActorLogin:           data.Actor.Login,
		ActorGID:             data.Actor.ID,

		RepositoryScheduleState: RepositoryScheduleState{
			CurrentHeadSHA:       data.Repository.Head.Sha,
			PipelineFiles:        mapPipelineFiles(data.Repository.PipelinesDirectory.Entries, pipelineDir, repo.ID, nwo, data.Repository.Head.Sha),
			ActionsPlanOwner:     data.Repository.ActionsPlanOwner.ID,
			FullName:             nwo,
			WorkflowFeatureFlags: types.WorkflowFeatureFlags{},
		},
	}, nil
}

// Note: Querying the mergeable and potentialMergeCommit fields has the side effect of enqueuing GitHub's CreatePullRequestMergeCommitJob.
// See https://github.com/github/github/blob/31b0577336114194624b5267af06941de678567c/packages/pull_requests/app/models/pull_request.rb#L1206-L1216
const getMergeStatusForPullRequestQuery = `query MergeStatusForPullRequest($repoID: ID!, $prNumber: Int!) {
	repository:node(id: $repoID) {
		... on Repository {
			pullRequest(number: $prNumber) {
				merged
				closed
				mergeable
				potentialMergeCommit {
					oid
					parents(first: 2) {
						nodes {
							oid
						}
					}
				}
				mergeCommit {
					oid
					parents(first: 2) {
						nodes {
							oid
						}
					}
				}
				# get head commits for comparison to parent commits and event_commit.
				baseRef {
					target {
						oid
					}
				}
				headRef {
					target {
						oid
					}
				}
			}
		}
	}
}`

func (c *client) GetSecretPolicies(ctx context.Context, repositoryID types.GlobalID) (*SecretPolicies, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	query := `
		query GetSecretPolicies($id: ID!) {
			node(id: $id) {
				...on Repository {
					canUseEnvironments
					forkPrWorkflowsPolicy
				}
			}
		}`

	variables := map[string]any{"id": repositoryID.String()}

	data := struct {
		Node struct {
			CanUseEnvironments    bool
			ForkPRWorkflowsPolicy types.ForkPRWorkflowsPolicy
		}
	}{}

	if _, err := c.do(ctx, "GetSecretPolicies", "query", query, variables, &data, nil); err != nil {
		return nil, err
	}

	return &SecretPolicies{
		CanUseEnvironments:    data.Node.CanUseEnvironments,
		ForkPRWorkflowsPolicy: data.Node.ForkPRWorkflowsPolicy,
	}, nil
}

func (c *client) GetPolicies(ctx context.Context, repositoryID types.GlobalID) (*Policies, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	query := `
		query GetPolicies($id: ID!) {
			node(id: $id) {
				...on Repository {
					canUseEnvironments
					forkPrWorkflowsPolicy
					publicForkPrWorkflowsPolicy
				}
			}
		}`

	variables := map[string]any{"id": repositoryID.String()}

	data := struct {
		Node struct {
			CanUseEnvironments          bool
			ForkPRWorkflowsPolicy       types.ForkPRWorkflowsPolicy
			PublicForkPRWorkflowsPolicy types.PublicForkPRWorkflowsPolicy
		}
	}{}

	if _, err := c.do(ctx, "GetPolicies", "query", query, variables, &data, nil); err != nil {
		return nil, err
	}

	return &Policies{
		CanUseEnvironments:          data.Node.CanUseEnvironments,
		ForkPRWorkflowsPolicy:       data.Node.ForkPRWorkflowsPolicy,
		PublicForkPRWorkflowsPolicy: data.Node.PublicForkPRWorkflowsPolicy,
	}, nil
}

type PullRequestMergeState struct {
	Merged    bool
	Closed    bool
	Mergeable githubv4.MergeableState
	// Either the merge commit or the test merge commit, depending on Merged
	MergeCommit        types.CommitSha
	MergeCommitParents [2]types.CommitSha
	PRHeadCommit       types.CommitSha
}

// HasMergeCommit returns true if a merge commit or potential merge commit
// exists on the pull request
func (s PullRequestMergeState) HasMergeCommit() bool {
	return !s.MergeCommit.IsZeroValue()
}

// HasTwoParents returns true if the merge commit has two parents.
func (s PullRequestMergeState) HasTwoParents() bool {
	// MergeCommitParents is an array of size 2. No need for a length check.
	return !s.MergeCommitParents[1].IsZeroValue()
}

// HasMergeCommitForEventCommit returns true if a merge commit or potential merge commit
// exists on the pull request and the second parent is the event commit sha.
func (s PullRequestMergeState) HasMergeCommitForEventCommit(eventCommitSHA types.CommitSha) bool {
	return !s.MergeCommit.IsZeroValue() && s.MergeCommitParents[1].IsEqual(eventCommitSHA)
}

// GetEnvironment get environment information from dotcom thru graphql
func (c *client) GetEnvironment(ctx context.Context, repoID types.GlobalID, environmentName string) (*EnvironmentResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	data := struct {
		Repository struct {
			Environment struct {
				ID         types.GlobalID `json:"id"`
				DatabaseID int64          `json:"databaseId"`
				Name       string         `json:"name"`
				Gates      struct {
					Edges []struct {
						Node struct {
							ID         types.GlobalID `json:"id"`
							DatabaseID int64          `json:"databaseId"`
							GateType   string         `json:"type"`
							Timeout    int32          `json:"timeout"`
						} `json:"node"`
					} `json:"edges"`
				} `json:"gates"`
			} `json:"environment"`
		} `json:"repository"`
	}{}
	vars := map[string]any{
		"id":   repoID,
		"name": environmentName,
	}
	if _, err := c.do(ctx, "GetSecretPolicies", "query", getEnvironmentQuery, vars, &data, nil); err != nil {
		return nil, err
	}
	edges := data.Repository.Environment.Gates.Edges
	gates := make([]*Gate, len(edges))

	for i, edge := range edges {
		gates[i] = &Gate{
			GateID:           edge.Node.ID,
			DatabaseID:       edge.Node.DatabaseID,
			GateType:         edge.Node.GateType,
			TimeoutInMinutes: edge.Node.Timeout,
		}
	}
	res := &EnvironmentResponse{
		EnvironmentID: data.Repository.Environment.ID,
		DatabaseID:    data.Repository.Environment.DatabaseID,
		Name:          data.Repository.Environment.Name,
		Gates:         gates,
	}
	return res, nil
}

const getEnvironmentQuery = `query EnvironmentByName($id: ID!, $name: String!) {
	repository: node(id: $id) {
		... on Repository {
			environment (name: $name){
				id
				databaseId
				name
				gates(first: 100) {
					edges {
						node {
							id
							databaseId
							type
							timeout
						}
					}
				}
			}
		}
	}
}
`

func (c *client) GetMergeStatusForPullRequest(ctx context.Context, repoGID types.GlobalID, prNumber int) (*PullRequestMergeState, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	vars := map[string]any{
		"repoID":   repoGID,
		"prNumber": prNumber,
	}

	type commitWithParents struct {
		OID     types.CommitSha
		Parents struct {
			Nodes [2]struct {
				OID types.CommitSha
			}
		}
	}

	data := struct {
		Repository struct {
			PullRequest struct {
				Merged               bool
				Closed               bool
				Mergeable            githubv4.MergeableState
				PotentialMergeCommit commitWithParents
				MergeCommit          commitWithParents
				BaseRef              struct {
					Target struct {
						OID types.CommitSha
					}
				}
				HeadRef struct {
					Target struct {
						OID types.CommitSha
					}
				}
			}
		}
	}{}

	if _, err := c.do(ctx, "GetMergeStatusForPullRequest", "query", getMergeStatusForPullRequestQuery, vars, &data, nil); err != nil {
		return nil, err
	}

	var mergeCommit commitWithParents
	if data.Repository.PullRequest.Merged {
		mergeCommit = data.Repository.PullRequest.MergeCommit
	} else {
		mergeCommit = data.Repository.PullRequest.PotentialMergeCommit
	}

	mergeState := &PullRequestMergeState{
		Merged:      data.Repository.PullRequest.Merged,
		Closed:      data.Repository.PullRequest.Closed,
		Mergeable:   data.Repository.PullRequest.Mergeable,
		MergeCommit: mergeCommit.OID,
		MergeCommitParents: [2]types.CommitSha{
			mergeCommit.Parents.Nodes[0].OID,
			mergeCommit.Parents.Nodes[1].OID,
		},
		PRHeadCommit: data.Repository.PullRequest.HeadRef.Target.OID,
	}

	c.obs.Debug(ctx, "Queried PR merge status",
		kvp.Bool("gh.launch.pr_merged", mergeState.Merged),
		kvp.Bool("gh.launch.pr_closed", mergeState.Closed),
		kvp.Any("gh.launch.pr_mergeable", mergeState.Mergeable),
		// Either the merge commit or the test merge commit, depending on Merged
		kvp.Any("gh.launch.pr_merge_commit", mergeState.MergeCommit),
		kvp.Any("gh.launch.pr_merge_commit_parents_0", mergeState.MergeCommitParents[0]),
		kvp.Any("gh.launch.pr_merge_commit_parents_1", mergeState.MergeCommitParents[1]),
		// the PR target branch (base branch)'s head commit - should match the first test merge commit parent.
		kvp.Any("gh.launch.pr_target_head_commit", data.Repository.PullRequest.BaseRef.Target.OID),
		// the PR branch's head commit - should match the event_commit and second test merge commit parent.
		kvp.Any("gh.launch.pr_head_commit", mergeState.PRHeadCommit),
		// means the PR's head branch has been deleted?
		kvp.Bool("gh.launch.pr_head_commit_not_found", mergeState.PRHeadCommit.IsZeroValue()),
	)

	return mergeState, nil
}
