package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type initialActionsSettings struct {
	baseHandler
	pb *v1.InitialActionsSettings
}

var _ handler = (*initialActionsSettings)(nil)

func newInitialActionsSettings(pb *v1.InitialActionsSettings, logger log.Logger) *initialActionsSettings {
	return &initialActionsSettings{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (s *initialActionsSettings) resourceID() string {
	return s.pb.ResourceId
}

func (s *initialActionsSettings) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(s.pb.RepositoryResourceId)
	return deps, nil
}

func (s *initialActionsSettings) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	repoID := resolved[s.pb.RepositoryResourceId].int64Val
	req := &octov1.UpdateActionsSettingsRequest{
		RepositoryId: repoID,
		ActionsPermission: func() octov1.ActionsPermissionType {
			switch s.pb.ActionsPermissions {
			case v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_ALL_ENABLED:
				return octov1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_ALL_ENABLED
			case v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED:
				return octov1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED
			case v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED:
				return octov1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED
			case v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_INHERITED:
				return octov1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_INHERITED
			default:
				return octov1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_INVALID
			}
		}(),
		AllowsGithubOwnedActions: s.pb.AllowsGithubOwnedActions,
		AllowsVerifiedActions:    s.pb.AllowsVerifiedActions,
		Patterns:                 s.pb.Patterns,
	}
	_, err := importer.UpdateActionsSettings(ctx, req)
	if err != nil {
		s.logger.WithError(err).Error("failed to update actions settings")
		return fmt.Errorf("failed to update actions settings: %w", err)
	}

	return nil
}
