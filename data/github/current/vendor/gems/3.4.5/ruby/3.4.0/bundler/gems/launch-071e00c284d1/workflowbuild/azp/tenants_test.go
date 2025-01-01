package azp

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/keystore"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/azp"
	azpc "github.com/github/launch/pkg/azp"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

func TestProviderRegistryEntry(t *testing.T) {
	suite.Run(t, new(tenantHandlerTestSuite))
}

var (
	repoID      = types.GlobalID("MX1234==")
	ownerID     = types.GlobalID("MX2345==")
	planOwnerID = types.GlobalID("MX3456==")
	nwo         = types.RepositoryFullName{Name: "my-repo", Owner: "my-org"}
)

type tenantHandlerTestSuite struct {
	suite.Suite

	client    *azp.MockS2SClient
	store     *keystore.MockStore
	clientFct *azpc.MockRepositoryClientFactory
	repoDB    *deployer.MockAzpResourcesRepository
	ghTwirp   *ghtwirp.MockClient
}

func (s *tenantHandlerTestSuite) SetupTest() {
	s.client = azp.NewMockS2SClient(s.T())
	s.store = keystore.NewMockStore(s.T())
	s.clientFct = azpc.NewMockRepositoryClientFactory(s.T())
	s.repoDB = deployer.NewMockAzpResourcesRepository(s.T())
	s.ghTwirp = ghtwirp.NewMockClient(s.T())
}

func (s *tenantHandlerTestSuite) TestInitializeProvider_CreatesThreeTenants_IfPlanOwnerNotOwner() {
	resources := &azptypes.BackingResources{}
	repoClient := azpc.NewMockRepositoryClient(s.T())

	pe := NewTenantHandler(
		s.client,
		s.store,
		observability.NewNullObservability(),
		s.clientFct,
		s.repoDB,
		NewMockTenantKeyGenerator(s.T()),
		"test",
		s.ghTwirp,
	)

	s.repoDB.EXPECT().GetOrCreate(
		mock.Anything,
		repoID,
		mock.Anything,
	).Return(resources, deployer.OrgCreationUnnecessary, nil)

	// We expect this organization-level-tenant to be created too
	s.repoDB.EXPECT().GetOrCreate(
		mock.Anything,
		ownerID,
		mock.Anything,
	).Return(resources, deployer.OrgCreationSuccess, nil)

	// We expect this business-level-tenant to be created too
	s.repoDB.EXPECT().GetOrCreate(
		mock.Anything,
		planOwnerID,
		mock.Anything,
	).Return(resources, deployer.OrgCreationSuccess, nil)

	s.clientFct.EXPECT().ClientFromResources(
		mock.Anything,
		resources,
	).Return(repoClient)

	s.clientFct.EXPECT().GetPipelineServiceURL(
		mock.Anything,
		resources,
	).Return("http://pipelines.service.com")

	_, _, outcome, err := pe.GetOrCreateTenants(
		context.TODO(),
		repoID,
		ownerID,
		planOwnerID,
		nwo,
	)
	s.NoError(err)
	s.Equal(deployer.OrgCreationSuccess, outcome)
}

func (s *tenantHandlerTestSuite) TestInitializeProvider_CreatesTwoTenants_IfPlanOwnerIsOwner() {
	resources := &azptypes.BackingResources{}
	repoClient := azpc.NewMockRepositoryClient(s.T())

	pe := NewTenantHandler(
		s.client,
		s.store,
		observability.NewNullObservability(),
		s.clientFct,
		s.repoDB,
		NewMockTenantKeyGenerator(s.T()),
		"test",
		s.ghTwirp,
	)

	s.repoDB.EXPECT().GetOrCreate(
		mock.Anything,
		repoID,
		mock.Anything,
	).Return(resources, deployer.OrgCreationUnnecessary, nil)

	// We expect this organization-level-tenant to be created too
	s.repoDB.EXPECT().GetOrCreate(
		mock.Anything,
		ownerID,
		mock.Anything,
	).Return(resources, deployer.OrgCreationSuccess, nil)

	// We expect no business-level-tenant to be created

	s.clientFct.EXPECT().ClientFromResources(
		mock.Anything,
		resources,
	).Return(repoClient)

	s.clientFct.EXPECT().GetPipelineServiceURL(
		mock.Anything,
		resources,
	).Return("http://pipelines.service.com")

	_, _, outcome, err := pe.GetOrCreateTenants(
		context.TODO(),
		repoID,
		ownerID,
		ownerID, // planOwner same as owner, which is the case for user repos
		nwo,
	)
	s.NoError(err)
	s.Equal(deployer.OrgCreationSuccess, outcome)
}

func (s *tenantHandlerTestSuite) TestInitializeProvider_CreatesATenant() {
	resources := &azptypes.BackingResources{}

	pe := NewTenantHandler(
		s.client,
		s.store,
		observability.NewNullObservability(),
		s.clientFct,
		s.repoDB,
		NewMockTenantKeyGenerator(s.T()),
		"test",
		s.ghTwirp,
	)

	// We expect a single tenant to be created for the passed in global ID
	s.repoDB.EXPECT().GetOrCreate(
		mock.Anything,
		planOwnerID,
		mock.Anything,
	).Return(resources, deployer.OrgCreationSuccess, nil)

	outcome, err := pe.GetOrCreateTenant(
		context.TODO(),
		planOwnerID,
		types.NilGlobalID,
	)
	s.NoError(err)
	s.Equal(deployer.OrgCreationSuccess, outcome)
}

func (s *tenantHandlerTestSuite) Test_worstOutcome() {
	examples := []struct {
		o1  deployer.OrgCreationOutcome
		o2  deployer.OrgCreationOutcome
		res deployer.OrgCreationOutcome
	}{
		{deployer.OrgCreationUnnecessary, deployer.OrgCreationUnnecessary, deployer.OrgCreationUnnecessary},
		{deployer.OrgCreationUnnecessary, deployer.OrgCreationSuccess, deployer.OrgCreationSuccess},
		{deployer.OrgCreationError, deployer.OrgCreationSuccess, deployer.OrgCreationError},
	}

	for tID, ex := range examples {
		s.Run(fmt.Sprintf("Case:%d", tID), func() {
			res := worstOutcome([]deployer.OrgCreationOutcome{ex.o1, ex.o2})
			s.Equal(ex.res, res)
		})
	}
}

func (s *tenantHandlerTestSuite) TestInitializeProvider_CreatesThreeTenants_GetSKU() {
	resources := &azptypes.BackingResources{}
	repoClient := azpc.NewMockRepositoryClient(s.T())

	pe := NewTenantHandler(
		s.client,
		s.store,
		observability.NewNullObservability(),
		s.clientFct,
		s.repoDB,
		NewMockTenantKeyGenerator(s.T()),
		"test",
		s.ghTwirp,
	)

	s.repoDB.EXPECT().GetOrCreate(
		mock.Anything,
		repoID,
		mock.Anything,
	).Return(resources, deployer.OrgCreationUnnecessary, nil)

	// We expect this organization-level-tenant to be created too
	s.repoDB.EXPECT().GetOrCreate(
		mock.Anything,
		ownerID,
		mock.Anything,
	).Return(resources, deployer.OrgCreationSuccess, nil)

	// We expect this business-level-tenant to be created too
	s.repoDB.EXPECT().GetOrCreate(
		mock.Anything,
		planOwnerID,
		mock.Anything,
	).Return(resources, deployer.OrgCreationSuccess, nil)

	s.clientFct.EXPECT().ClientFromResources(
		mock.Anything,
		resources,
	).Return(repoClient)

	s.clientFct.EXPECT().GetPipelineServiceURL(
		mock.Anything,
		resources,
	).Return("http://pipelines.service.com")

	_, _, outcome, err := pe.GetOrCreateTenants(
		context.TODO(),
		repoID,
		ownerID,
		planOwnerID,
		nwo,
	)
	s.NoError(err)
	s.Equal(deployer.OrgCreationSuccess, outcome)
}
