package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type project struct {
	baseHandler
	pb                *v1.Project
	importedProjectID int64
}

var (
	_ handler = (*project)(nil)

	supportedOwnerTypes = map[v1.OwnerType]struct{}{
		v1.OwnerType_OWNER_TYPE_ORGANIZATION: {},
		v1.OwnerType_OWNER_TYPE_REPOSITORY:   {},
	}
)

func newProject(pb *v1.Project, logger log.Logger) *project {
	return &project{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (p *project) skip() bool {
	_, ok := supportedOwnerTypes[p.pb.OwnerType]
	return !ok
}

func (p *project) resourceID() string {
	return p.pb.ResourceId
}

func (p *project) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.strDeps.Add(p.pb.CreatorResourceId)

	switch p.pb.OwnerType {
	case v1.OwnerType_OWNER_TYPE_ORGANIZATION:
		deps.strDeps.Add(p.pb.OwnerResourceId)
	case v1.OwnerType_OWNER_TYPE_REPOSITORY:
		deps.int64Deps.Add(p.pb.OwnerResourceId)
	default:
		return nil, fmt.Errorf("unsupported owner type: %v", p.pb.OwnerType)
	}
	return deps, nil
}

func (p *project) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	var repoID int64
	var ownerLogin string
	switch p.pb.OwnerType {
	case v1.OwnerType_OWNER_TYPE_ORGANIZATION:
		ownerLogin = resolved[p.pb.OwnerResourceId].strVal
	case v1.OwnerType_OWNER_TYPE_REPOSITORY:
		ownerLogin = p.pb.OwnerResourceId
		repoID = resolved[p.pb.OwnerResourceId].int64Val
	default:
		return fmt.Errorf("unsupported owner type: %v", p.pb.OwnerType)
	}
	// Import the project
	projectReq := &octov1.ImportProjectRequest{
		Name:       p.pb.Name,
		Number:     p.pb.Number,
		OwnerLogin: ownerLogin,
		OwnerType: func() octov1.OwnerType {
			switch p.pb.OwnerType {
			case v1.OwnerType_OWNER_TYPE_ORGANIZATION:
				return octov1.OwnerType_OWNER_TYPE_ORGANIZATION
			case v1.OwnerType_OWNER_TYPE_REPOSITORY:
				return octov1.OwnerType_OWNER_TYPE_REPOSITORY
			case v1.OwnerType_OWNER_TYPE_USER:
				return octov1.OwnerType_OWNER_TYPE_USER
			default:
				return octov1.OwnerType_OWNER_TYPE_INVALID
			}
		}(),
		CreatorLogin: resolved[p.pb.CreatorResourceId].strVal,
		RepositoryId: repoID,
		Body:         p.pb.Body,
		IsPublic:     p.pb.IsPublic,
		CreatedAt:    p.pb.CreatedAt,
		ClosedAt:     p.pb.ClosedAt,
		UpdatedAt:    p.pb.UpdatedAt,
	}

	projectRes, projectErr := importer.ImportProject(ctx, projectReq)
	if projectErr != nil {
		p.logger.WithError(projectErr).Error("failed to import project", kvp.Any("request", projectReq))
		return fmt.Errorf("failed to load project: %w", projectErr)
	}
	if projectRes.ProjectImportErrors != nil {
		for _, importErr := range projectRes.ProjectImportErrors {
			p.logger.Error("error importing project",
				kvp.String("error_message", importErr.ErrorMessage),
				kvp.String("model_type", importErr.ModelType.String()),
			)
		}
	}
	p.importedProjectID = projectRes.Project.Id

	return nil
}

func (p *project) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		p.resourceID(): &transformedValues{
			int64Val: p.importedProjectID,
		},
	}
}
