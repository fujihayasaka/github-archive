package utils

import (
	"github.com/github/secret-scanning-proto/gen/go/v1/repositories"
	"github.com/github/spokes-proto/gen/go/v1/types"

	hydro_schemas_github_v1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entities "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"

	"github.com/github/token-scanning-service/ts/proto"
	"github.com/github/token-scanning-service/ts/twirp/proto/job"
)

// We want to be using ts/converters/repos.go instead of this file for the new Repos.RepoService

func ParseTokenScanRepositoryType(t string) hydro_schemas_github_v1.TokenScan_RepositoryType {
	val, ok := hydro_schemas_github_v1.TokenScan_RepositoryType_value[t]
	if !ok {
		return hydro_schemas_github_v1.TokenScan_UNKNOWN
	}
	return hydro_schemas_github_v1.TokenScan_RepositoryType(val)
}

func TokenScanRepositoryTypeToSpokesRepositoryType(t hydro_schemas_github_v1.TokenScan_RepositoryType) types.Repository_Type {
	switch t {
	case hydro_schemas_github_v1.TokenScan_UNKNOWN:
		return types.Repository_TYPE_INVALID
	case hydro_schemas_github_v1.TokenScan_REPOSITORY:
		return types.Repository_TYPE_REPOSITORY
	case hydro_schemas_github_v1.TokenScan_GIST:
		return types.Repository_TYPE_GIST
	default:
		return types.Repository_TYPE_INVALID
	}
}

func RepoToBackfillScan(repo *repositories.Repository, repositoryType job.RepositoryType) *job.BackfillRepoScanJob {
	return &job.BackfillRepoScanJob{
		Repository:          RepoToRepositoryEntity(repo),
		Owner:               RepositoriesUserToEntitiesUser(repo.GetOwner()),
		RequestedAt:         proto.TimestampNow(),
		IsInternalOwnedRepo: false,
		RepoType:            repositoryType,
		FeatureFlags:        repo.GetFeatureFlags(),
	}
}

func RepoToRepoPushScan(repo *repositories.Repository, refUpdates []*job.RefUpdate, repositoryType job.RepositoryType) *job.RepoPushScan {
	return &job.RepoPushScan{
		RequestedAt:  proto.TimestampNow(),
		Repository:   RepoToRepositoryEntity(repo),
		Owner:        RepositoriesUserToEntitiesUser(repo.GetOwner()),
		RefUpdates:   refUpdates,
		RepoType:     repositoryType,
		FeatureFlags: repo.GetFeatureFlags(),
	}
}

func RepoToCommitMetadataScan(repo *repositories.Repository, refUpdates []*job.RefUpdate, repositoryType job.RepositoryType) *job.RepoCommitMetadataScan {
	return &job.RepoCommitMetadataScan{
		RequestedAt:  proto.TimestampNow(),
		Repository:   RepoToRepositoryEntity(repo),
		Owner:        RepositoriesUserToEntitiesUser(repo.GetOwner()),
		RefUpdates:   refUpdates,
		RepoType:     repositoryType,
		FeatureFlags: repo.GetFeatureFlags(),
	}
}

func RepoToRepositoryEntity(repo *repositories.Repository) *entities.Repository {
	visibility := entities.Repository_VISIBILITY_UNKNOWN
	switch repo.GetVisibility() {
	case repositories.Repository_INTERNAL:
		visibility = entities.Repository_INTERNAL
	case repositories.Repository_PRIVATE:
		visibility = entities.Repository_PRIVATE
	case repositories.Repository_PUBLIC:
		visibility = entities.Repository_PUBLIC
	}

	return &entities.Repository{
		Id:            repo.GetId(),
		Name:          repo.GetName(),
		Visibility:    visibility,
		DefaultBranch: repo.GetDefaultBranch(),
	}
}

func RepositoriesUserToEntitiesUser(user *repositories.User) *entities.User {
	userType := entities.User_UNKNOWN
	switch user.GetType() {
	case repositories.User_USER:
		userType = entities.User_USER
	case repositories.User_ORGANIZATION:
		userType = entities.User_ORGANIZATION
	case repositories.User_BOT:
		userType = entities.User_BOT
	}
	return &entities.User{
		Id:            user.GetId(),
		Login:         user.GetLogin(),
		Type:          userType,
		GlobalRelayId: user.GetGlobalRelayId(),
	}
}
