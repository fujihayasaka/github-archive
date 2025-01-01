package github

import (
	"github.com/github/launch/clients/hydro/metadata"
	hydro "github.com/github/launch/hydro/schemas/github/v1/entities"
)

type actorResult struct {
	ID           string `json:"id"`
	DatabaseID   uint32 `json:"databaseId"`
	Login        string `json:"login"`
	IsDependabot bool   `json:"isDependabot"`
}

type repoResult struct {
	ID                                              string      `json:"id"`
	DatabaseID                                      uint32      `json:"databaseId"`
	IsPrivate                                       bool        `json:"isPrivate"`
	Owner                                           actorResult `json:"owner"`
	DisableDependabotSecurityEnforcementFeatureFlag bool        `json:"disableDependabotSecurityEnforcementFeatureFlag"`
}

func convertActor(a actorResult) (*metadata.WorkflowMetadataUser, *metadata.WorkflowMetadataActor) {
	user := &metadata.WorkflowMetadataUser{
		ID:            a.DatabaseID,
		Login:         a.Login,
		GlobalRelayID: a.ID,
	}
	return user, &metadata.WorkflowMetadataActor{
		IsDependabot: a.IsDependabot,
		Login:        a.Login,
	}
}

func convertRepo(r repoResult) (repositoryMetadata *metadata.WorkflowRepositoryMetadata, disableDependabotSecurityEnforcementFeatureFlag bool) {
	repo := &metadata.WorkflowRepositoryMetadata{
		ID:            r.DatabaseID,
		GlobalRelayID: r.ID,
	}

	if r.IsPrivate {
		repo.Visibility = hydro.Repository_PRIVATE
	} else {
		repo.Visibility = hydro.Repository_PUBLIC
	}
	return repo, r.DisableDependabotSecurityEnforcementFeatureFlag
}

const metadataForWorkflowsQuery = `query GetReportingMetadata($targetRepoId: ID!, $actorId: ID!) {
  targetRepo:node(id: $targetRepoId) {
    ...RepoFields
  }
  actor:node(id: $actorId) {
    ... on Node { id }
    ... on Actor { login }
    ... on Bot {
      isDependabot
      databaseId
    }
    ... on User {
      databaseId
    }
    ... on Organization { databaseId }
  }
}

fragment RepoFields on Repository {
  id
  databaseId
  isPrivate
  owner {
    ...OwnerFields
  }
  disableDependabotSecurityEnforcementFeatureFlag:isFeatureEnabled(name:"` + DisableDependabotSecurityEnforcementFeatureFlag + `")
}

fragment OwnerFields on RepositoryOwner {
  id
  login
  ... on User {
    databaseId
    createdAt
  }
  ... on Organization {
    databaseId
  }
}
`
