package azp

import (
	"context"
	"sort"
	"time"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/keystore"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type TenantHandler interface {
	GetOrCreateTenants(ctx context.Context, repoID, ownerID, planOwnerID types.GlobalID, NWO types.RepositoryFullName) (azp.RepositoryClient, *types.RepositoryTenants, deployer.OrgCreationOutcome, error)
	GetOrCreateTenant(ctx context.Context, globalNodeID, ownerGlobalNodeID types.GlobalID) (deployer.OrgCreationOutcome, error)
}

type tenantHandler struct {
	s2sClient          azp.S2SClient
	keystore           keystore.Store
	repoClients        azp.RepositoryClientFactory
	log                logger.Logger
	stats              statter.Statter
	env                launchconfig.AppEnv
	repo               deployer.AzpResourcesRepository
	tenantKeyGenerator TenantKeyGenerator
	ghTwirpClient      ghtwirp.Client
}

func NewTenantHandler(client azp.S2SClient, keystore keystore.Store, obs *observability.Observability, fact azp.RepositoryClientFactory, repo deployer.AzpResourcesRepository, tenantKeyGenerator TenantKeyGenerator, env launchconfig.AppEnv, ghTwirpClient ghtwirp.Client) TenantHandler {
	return &tenantHandler{
		s2sClient:          client,
		keystore:           keystore,
		repoClients:        fact,
		log:                obs.Logger,
		stats:              obs.Statter,
		env:                env,
		repo:               repo,
		tenantKeyGenerator: tenantKeyGenerator,
		ghTwirpClient:      ghTwirpClient,
	}
}

func (e *tenantHandler) GetOrCreateTenants(ctx context.Context, repoID, ownerID, planOwnerID types.GlobalID, NWO types.RepositoryFullName) (client azp.RepositoryClient, repositoryTenants *types.RepositoryTenants, outcome deployer.OrgCreationOutcome, err error) {
	// as this is handled as a startErr and not needled, ensure we capture errors here while we're developing
	ctx, span := tracing.Start(ctx)
	defer span.End()

	startTime := time.Now().UTC()
	defer func() {
		duration := time.Since(startTime)
		e.stats.Timing(ctx, "tenants_acquisition_time_ms", statter.Tags{"outcome": string(outcome)}, duration)
		if err != nil {
			e.log.Report(ctx, err,
				kvp.String("gh.repo.global_id", repoID.String()))
		}
	}()

	var repoResources, ownerResources, planOwnerResources *azptypes.BackingResources
	var repoOutcome, ownerOutcome, planOwnerOutcome deployer.OrgCreationOutcome
	var g errgroup.Group

	g.Go(func() error {
		res, outcome, err := e.repo.GetOrCreate(ctx, repoID,
			func(ctx context.Context) (*azptypes.BackingResources, error) {
				return e.createResources(ctx, repoID, ownerID, NWO)
			},
		)
		if err == nil {
			repoResources = res
			repoOutcome = outcome
			e.log.Debug(ctx, "fetched azure repository tenant",
				kvp.String("gh.repo.global_id", repoID.String()),
				kvp.String("gh.tenant.name", repoResources.TenantName),
				kvp.String("gh.launch.project.name", repoResources.ProjectName),
				kvp.Int64("gh.launch.pipeline.id", repoResources.PipelineID),
			)
		}
		return errors.Wrap(err, "error creating tenant for repository")
	})

	// Owner and planOwner level tenants are not tied to any particular repository
	g.Go(func() error {
		res, outcome, err := e.repo.GetOrCreate(ctx, ownerID,
			func(ctx context.Context) (*azptypes.BackingResources, error) {
				return e.createResources(ctx, ownerID, types.NilGlobalID, types.EmptyRepositoryFullName)
			},
		)
		if err == nil {
			ownerResources = res
			ownerOutcome = outcome
			e.log.Debug(ctx, "fetched azure owner tenant",
				kvp.String("gh.launch.owner.global_id", ownerID.String()),
				kvp.String("gh.tenant.name", ownerResources.TenantName),
				kvp.String("gh.launch.project.name", ownerResources.ProjectName),
				kvp.Int64("gh.launch.pipeline.id", ownerResources.PipelineID),
			)
		}
		return errors.Wrap(err, "error creating tenant for owner")
	})

	g.Go(func() error {
		if ownerID.IsEquivalent(planOwnerID) {
			// For user-owned repositories, the owner == the plan owner
			planOwnerOutcome = deployer.OrgCreationUnnecessary
			return nil
		}
		res, outcome, err := e.repo.GetOrCreate(ctx, planOwnerID,
			func(ctx context.Context) (*azptypes.BackingResources, error) {
				return e.createResources(ctx, planOwnerID, types.NilGlobalID, types.EmptyRepositoryFullName)
			},
		)
		if err == nil {
			planOwnerResources = res
			planOwnerOutcome = outcome
			e.log.Debug(ctx, "fetched azure plan owner tenant",
				kvp.String("gh.launch.owner.global_id", planOwnerID.String()),
				kvp.String("gh.tenant.name", planOwnerResources.TenantName),
				kvp.String("gh.launch.project.name", planOwnerResources.ProjectName),
				kvp.Int64("gh.launch.pipeline.id", planOwnerResources.PipelineID),
			)
		}
		return errors.Wrap(err, "error creating tenant for plan owner")
	})

	if err := g.Wait(); err != nil {
		e.log.Error(ctx, "error creating tenant",
			kvp.Err(err),
			kvp.String("gh.repo.global_id", repoID.String()),
			kvp.String("gh.launch.owner.global_id", ownerID.String()),
			kvp.String("gh.launch.plan_owner.global_id", planOwnerID.String()),
		)
		return nil, nil, deployer.OrgCreationError, tracing.RecordError(span, err)
	}

	client = e.repoClients.ClientFromResources(ctx, repoResources)

	repositoryTenants = &types.RepositoryTenants{
		OwnerTenantID:   ownerResources.TenantID,
		OwnerTenantName: ownerResources.TenantName,
		OwnerTenantURL:  e.repoClients.GetPipelineServiceURL(ctx, ownerResources),
	}

	if planOwnerResources != nil {
		repositoryTenants.BillingPlanOwnerTenantID = planOwnerResources.TenantID
		repositoryTenants.BillingPlanOwnerTenantName = planOwnerResources.TenantName
		repositoryTenants.BillingPlanOwnerTenantURL = e.repoClients.GetPipelineServiceURL(ctx, planOwnerResources)
	} else {
		repositoryTenants.BillingPlanOwnerTenantID = repositoryTenants.OwnerTenantID
		repositoryTenants.BillingPlanOwnerTenantName = repositoryTenants.OwnerTenantName
		repositoryTenants.BillingPlanOwnerTenantURL = repositoryTenants.OwnerTenantURL
	}

	outcomes := []deployer.OrgCreationOutcome{repoOutcome, ownerOutcome, planOwnerOutcome}
	overallOutcome := worstOutcome(outcomes)
	tc := tenantsCreated(outcomes)
	duration := time.Since(startTime)
	e.log.Debug(ctx, "acquired tenants for repository",
		kvp.String("gh.launch.get_or_create_tenant.outcome", string(overallOutcome)),
		kvp.Int("gh.launch.tenants_created.count", tc),
		kvp.Duration("gh.launch.tenants_acquisition_time_seconds", duration))

	return client, repositoryTenants, overallOutcome, nil
}

func (e *tenantHandler) GetOrCreateTenant(ctx context.Context, globalID, ownerGlobalID types.GlobalID) (outcome deployer.OrgCreationOutcome, err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	defer func() {
		if err != nil {
			e.log.Report(ctx, err,
				kvp.String("gh.launch.resource.global_id", globalID.String()))
		}
	}()

	var tenantOutcome deployer.OrgCreationOutcome
	var g errgroup.Group

	g.Go(func() error {
		res, outcome, err := e.repo.GetOrCreate(ctx, globalID,
			func(ctx context.Context) (*azptypes.BackingResources, error) {
				// NWO is only used by Actions Service for tracing purposes
				// It is not useful when creating tenants for Users, Orgs, and Enterprises
				return e.createResources(ctx, globalID, ownerGlobalID, types.EmptyRepositoryFullName)
			},
		)
		if err == nil {
			tenantResources := res
			tenantOutcome = outcome
			e.log.Debug(ctx, "fetched azure tenant",
				kvp.String("gh.launch.resource.global_id", globalID.String()),
				kvp.String("gh.org.name", tenantResources.TenantName),
				kvp.String("gh.launch.project.name", tenantResources.ProjectName),
				kvp.Int64("gh.launch.pipeline.id", tenantResources.PipelineID),
			)
		}
		return errors.Wrap(err, "error creating tenant for global_id")
	})

	if err := g.Wait(); err != nil {
		e.log.Error(ctx, "error creating tenant",
			kvp.Err(err),
			kvp.String("gh.launch.resource.global_id", globalID.String()),
		)
		return deployer.OrgCreationError, tracing.RecordError(span, err)
	}

	return tenantOutcome, nil
}

var dbOutcomeWeightings = map[deployer.OrgCreationOutcome]float64{
	deployer.OrgCreationIgnore:      0,
	deployer.OrgCreationUnnecessary: 1,
	deployer.OrgCreationSuccess:     2,
	deployer.OrgCreationUnknown:     3,
	deployer.OrgCreationError:       4,
}

func worstOutcome(o []deployer.OrgCreationOutcome) deployer.OrgCreationOutcome {
	sort.Slice(o, func(i, j int) bool {
		return dbOutcomeWeightings[o[i]] > dbOutcomeWeightings[o[j]]
	})

	return o[0]
}

func tenantsCreated(outcomes []deployer.OrgCreationOutcome) int {
	created := 0
	for _, outcome := range outcomes {
		if outcome == deployer.OrgCreationSuccess {
			created++
		}
	}

	return created
}

func (e *tenantHandler) createResources(ctx context.Context, globalID, ownerGlobalID types.GlobalID, NWO types.RepositoryFullName) (resources *azptypes.BackingResources, err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	keyCtx, cancel := context.WithTimeout(ctx, 10*time.Second) // optional - we could just pass ctx below.
	defer cancel()
	key, err := e.tenantKeyGenerator.Get(keyCtx)
	if err != nil {
		return nil, errors.Wrap(err, "error generating a key for the new tenant")
	}

	// globalID can be for a repo, owner or billing owner. ownerGlobalID is only not set when globalID is owner or billing owner
	planName := ""
	billingOwnerCreatedAt := time.Time{}
	additionalFields := []kvp.Field{}

	if ownerGlobalID == types.NilGlobalID {
		planName, billingOwnerCreatedAt, err = e.getBillingOwnerInfo(ctx, globalID)
		if err != nil {
			e.log.Error(ctx, "unable to get plan sku and billing owner created time for tenant creation",
				kvp.Err(err),
				kvp.String("gh.launch.resource.global_id", globalID.String()),
			)
		} else if planName != "" {
			additionalFields = append(additionalFields,
				kvp.String("gh.launch.plan.sku", planName),
				kvp.Time("gh.launch.resource.created_at", billingOwnerCreatedAt),
			)
		}
	}

	result, err := e.s2sClient.CreateTenantWithResources(ctx, globalID, ownerGlobalID, NWO, &key.PublicKey, planName, billingOwnerCreatedAt)
	if err != nil {
		return nil, errors.Wrap(err, "error creating tenant with resources")
	}
	scope, err := keystore.NewScope(string(e.env), result.TenantName)
	if err != nil {
		return nil, errors.Wrap(err, "error creating keystore scope ")
	}
	cipher, err := e.keystore.EncryptPrivateKeyForOrganization(ctx, scope, key)
	if err != nil {
		return nil, errors.Wrap(err, "error encrypting private key for org")
	}
	resources = &azptypes.BackingResources{
		CreationResult:      *result,
		EncryptedPrivateKey: cipher,
		Environment:         string(e.env),
	}
	e.stats.Counter(ctx, "azp.tenants.created", nil, 1)
	fields := []kvp.Field{
		kvp.String("gh.launch.resource.global_id", globalID.String()),
		kvp.String("gh.repo.name_with_owner", NWO.String()),
		kvp.String("gh.org.name", resources.TenantName),
		kvp.String("gh.launch.project.name", resources.ProjectName),
		kvp.Int64("gh.launch.pipeline.id", resources.PipelineID),
	}
	fields = append(fields, additionalFields...)
	e.log.Debug(ctx, "created azure resources", fields...)
	return resources, err
}

func (e *tenantHandler) getBillingOwnerInfo(ctx context.Context, globalID types.GlobalID) (planSku string, billingOwnerCreatedAt time.Time, err error) {
	typeName, databaseID, err := globalID.Decode()
	if err != nil {
		return "", time.Time{}, errors.Wrap(err, "error decoding globalID")
	}

	switch typeName {
	case types.GlobalIDOrganizationType:
		owner, err := e.ghTwirpClient.GetOrganizationOwner(ctx, databaseID)
		if err != nil {
			return "", time.Time{}, errors.Wrap(err, "error getting owner info")
		}
		if owner.Business != nil {
			// globalID is for org that's part of an enterprise
			// plan sku and billing owner created time will be set when we create enterprise tenant
			return "", time.Time{}, nil
		}
		return owner.OrganizationPlanName, owner.Organization.CreatedAt, nil
	case types.GlobalIDUserType, types.GlobalIDEnterpriseType, types.GlobalIDBusinessType:
		actorsInfo, err := e.ghTwirpClient.GetActorsInfo(ctx, []types.GlobalID{globalID})
		if err != nil {
			return "", time.Time{}, errors.Wrap(err, "error getting actors info")
		}
		actor := actorsInfo.Actors[0]
		return actor.GetPlanName(), actor.GetCreatedAt().AsTime(), nil
	default:
		// not needed
		return "", time.Time{}, nil
	}
}
