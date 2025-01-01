package build

import (
	"time"

	"github.com/github/launch/types"
)

// RunEnvironment is a value struct for holding all of the available run
// environment variables used by an action.
type RunEnvironment struct {
	GitURL                            string                           // the url at which to clone the repository
	PrivateRepository                 bool                             // whether this repository is private or not
	RepositoryVisibility              string                           // the visibility of the repository, public/internal/private
	ForkedRepository                  bool                             // whether this repository is a fork or not
	ForkedPullRequest                 bool                             // whether this event is a pull request from a fork
	OwnerID                           types.GlobalID                   // The owner ID (user or org)
	OwnerDatabaseID                   int64                            // The owner Database ID (user or org)
	OwnerCreatedAt                    time.Time                        // when the owner (user or org) was created at
	EnterpriseManagedBusinessID       types.GlobalID                   // The ID of the enterprise managing the owner, set if the enterprise is present and has EMUs enabled
	Repository                        types.RepositoryFullName         // the repository which the event is received for
	RepositoryID                      types.GlobalID                   // the global ID for the repository which the event is received for
	RepositoryDatabaseID              int64                            // the database ID for the repository which the event is received for
	Workflow                          string                           // the identifier from `workflow "identifier" {}`
	WorkflowRunID                     int64                            // the workflow run id
	WorkflowRunNumber                 int64                            // the workflow run number
	WorkflowRunAttempt                int64                            // the attempt number for the workflow run (the first attempt is 1)
	ExecutingActor                    string                           // the user name of the actor which is deemed to be executing the event. usually equals to the triggering actor, unless rerun requested by different actor
	ExecutingActorID                  types.GlobalID                   // the global ID of the actor which is deemed to be executing the event. usually equals to the triggering actor, unless rerun requested by different actor
	ExecutingActorDatabaseID          int64                            // the database ID of the actor which is deemed to be executing the event. usually equals to the triggering actor, unless rerun requested by different actor
	TriggeringActor                   string                           // the user name of the actor in the triggering event
	TriggeringActorID                 types.GlobalID                   // the global ID of the actor in the triggering event
	BaseRef                           types.GitRef                     // ...
	Event                             string                           // the event type of the triggering event
	HeadRef                           types.GitRef                     // ...
	ServerURL                         string                           // the externally accessible GitHub server URL, for example https://github.com or https://my-ghes
	APIURL                            string                           // the externally accessible GitHub v3 API URL, for example https://api.github.com or https://my-ghes/api/v3
	GraphQLURL                        string                           // the externally accessible GitHub GraphQL URL, for example https://api.github.com/graphql or https://my-ghes/api/graphql
	RetentionDays                     int64                            // the repository retention limit in days
	ActionsCacheSizeLimit             uint64                           // the actions cache size limit
	OidcSubClaimCustomizationTemplate string                           // the OIDC sub claim customization template
	CustomizeEnterpriseOidcIssuer     bool                             // the OIDC issuer URL customisation flag. (only for enterprise customer)
	ParentRepository                  types.RepositoryFullName         // the parent repository if the repository is a fork
	RepositoryTier                    types.RepositoryTier             // the repository tier
	HeadRepository                    types.RepositoryFullName         // the head repository if the event is a pull request
	HeadRepositoryID                  types.GlobalID                   // the head repository global ID if the event is a pull request
	HeadRepositoryOwnerID             types.GlobalID                   // the head repository owner global ID if the event is a pull request
	DefaultWorkflowPermissions        types.DefaultWorkflowPermissions // the permissions policy for this run
	SelfHostedRunnersDisabled         bool                             // whether self-hosted repository level runners are disabled for this repository
	WorkflowRef                       string                           // the ref of the workflow file shoud look like  "my-org/my-repo/.github/workflows/foo.yml@main"
	WorkflowSha                       types.CommitSha                  // the commit sha of the workflow file
}
