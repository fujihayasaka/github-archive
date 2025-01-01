package tokens

import (
	"context"

	"github.com/github/launch/types"
)

// NoopService is a Service implementation that returns no tokens
var NoopService Service = &noopService{}

var NoAccessToken AccessToken

type noopService struct {
}

func (s *noopService) SiteScopedTokenForRepositoryOwner(_ context.Context, _ types.GlobalID, _ int64, _ bool, _ *InstallationPermissions, _ *ExtendedPermissions) (*AccessToken, error) {
	return &NoAccessToken, nil
}

func (s *noopService) SiteScopedTokenForRepository(_ context.Context, _ types.GlobalID, _ int64, _ bool, _ *InstallationPermissions, _ *ExtendedPermissions) (*AccessToken, error) {
	return &NoAccessToken, nil
}

func (s *noopService) ReadTokenForSiteScopedInstallation(_ context.Context, _ int64, _ []string, _ bool) (*AccessToken, error) {
	return &NoAccessToken, nil
}

func (s *noopService) RefreshToken(_ context.Context, _ *AccessToken) (*AccessToken, error) {
	return &NoAccessToken, nil
}

func (s *noopService) RevokeToken(_ context.Context, _ types.GlobalID, _ *AccessToken) error {
	return nil
}
