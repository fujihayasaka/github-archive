package policy

import (
	"context"
	"fmt"

	"github.com/github/osslicensecompliance/internal/application"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

// Writer handles all policy write operations at different levels.
type Writer interface {
	AddLicenses(ctx context.Context, licenses []string, distributionContexts []string) error
	AddPackage(ctx context.Context, packagePolicy *proto.PackagePolicy, distributionContexts []string) error
	RemoveLicenses(ctx context.Context, spdxIDs []string, distributionContext string) error
	RemovePackages(ctx context.Context, packages []*proto.PackagePolicy, distributionContext string) error
}

// NewWriter creates a Writer for the specified policy level and entity.
func NewWriter(app *application.Application, level proto.PolicyLevel, entityID uint64) (Writer, error) {
	switch level {
	case proto.PolicyLevel_POLICY_LEVEL_REPOSITORY:
		return &repositoryWriter{
			app:          app,
			storage:      app.Subsystems.Storage,
			publisher:    app.Subsystems.EventPublisher,
			repositoryID: entityID,
		}, nil
	case proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION:
		return &organizationWriter{
			app:            app,
			storage:        app.Subsystems.Storage,
			publisher:      app.Subsystems.EventPublisher,
			organizationID: entityID,
		}, nil
	case proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE:
		return &enterpriseWriter{
			app:          app,
			storage:      app.Subsystems.Storage,
			publisher:    app.Subsystems.EventPublisher,
			enterpriseID: entityID,
		}, nil
	default:
		return nil, fmt.Errorf("unsupported policy level: %v", level)
	}
}
