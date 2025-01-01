package largerrunners

import (
	"context"
	"strconv"

	"github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

func (s *service) CreatePool(ctx context.Context, req *CreatePoolRequest) (*CreatePoolResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "createpool")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for CreatePool lookup")
			return &CreatePoolResponse{Pool: nil}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	var imageKey *azp.ImageKey

	var shouldCreateNewImageDefinition = req.Image.Source == ImageKey_Custom && req.ImageSasUri != "" && req.Image.Id == ""

	if shouldCreateNewImageDefinition {
		imageKey, err = s.initializeCustomImageVersionForNewPool(ctx, arc, obs, req)
		if err != nil {
			return nil, err
		}
	} else {
		imageKey = &azp.ImageKey{
			Source:  imageSourceToString[req.Image.Source],
			ID:      req.Image.Id,
			Version: req.Image.Version,
		}
	}

	poolDetails := azp.CreatePoolRequest{
		Name:              req.Name,
		Platform:          req.Platform,
		RunnerGroupID:     req.RunnerGroupId,
		Labels:            req.Labels,
		IsDev:             false,
		Image:             *imageKey,
		MachineSpecID:     req.MachineSpecId,
		IsPublicIPEnabled: req.IsPublicIpEnabled,
		MaximumRunners:    req.MaximumRunners,
		PersistentOSDisk:  req.PersistentOsDisk,
	}

	runnerPool, err := arc.CreateRunnerPool(ctx, poolDetails)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	rp := s.mapRunnerPool(runnerPool)
	return &CreatePoolResponse{Pool: rp}, nil
}

func (s *service) initializeCustomImageVersionForNewPool(ctx context.Context, arc azp.RepositoryClient, obs *observability.Observability, req *CreatePoolRequest) (*azp.ImageKey, error) {
	imageDefinition, err := arc.CreateImageDefinition(ctx, platformToOsType[req.Platform], req.Name)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	var imageVersion *azp.ImageVersion
	imageVersion, err = arc.CreateImageVersion(ctx, req.ImageSasUri, imageDefinition.ID)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	// converting Image Version to ImageKey acceptable for Pool creation:
	return &azp.ImageKey{
		Source:  "Custom",
		ID:      strconv.FormatInt(imageVersion.ImageDefinitionID, 10),
		Version: req.Image.Version,
	}, nil
}
