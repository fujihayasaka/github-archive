package deployer

import (
	"context"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/testutils"
)

const (
	testRepoGlobalID         = types.GlobalID("test-repo-global-id")
	testPlanOwnerGlobalID    = types.GlobalID("test-repo-owner-global-id")
	testEnvironment          = "test-environment"
	testTenantName           = "test-tenant-name"
	testTenantID             = "test-tenant-id"
	testOwnerTenantName      = "test-owner-tenant-name"
	testOwnerTenantID        = "test-owner-tenant-id"
	testOwnerGlobalID        = types.GlobalID("test-owner-global-id")
	testPlanOwnerTenantName  = "test-plan-owner-tenant-name"
	testPlanOwnerTenantID    = "test-plan-owner-tenant-id"
	testWorkflowFilePath     = "test-workflow-file-path"
	testUUID                 = "test-uuid"
	testProjectName          = "test-project-name"
	testWorkflowBuildID      = "74657374-2d75-7569-6400-000000000000" // testUUID formatted as UUID
	testExternalBuildID      = "1234567890"
	testPipelinesScaleUnitID = "6bfa0b85-0342-b826-1c9f-bc636d8425af"
)

type AzpResourcesLoaderSuite struct {
	suite.Suite
	conn             *asql.SQL
	repo             *azpResourcesLoader
	globalIDMigrator GlobalIDMigrator
	mockTwirpClient  *ghtwirp.MockClient
}

func TestAzpResourcesLoader(t *testing.T) {
	testutils.NoShort(t)
	suite.Run(t, new(AzpResourcesLoaderSuite))
}

func (s *AzpResourcesLoaderSuite) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)
	s.conn = asql.New(conn, logger.TestLogger(), statter.NullStatter(), testutils.NewNoopBreaker(), asql.LaunchCluster)
	s.mockTwirpClient = ghtwirp.NewMockClient(s.T())
	s.globalIDMigrator = NewGlobalIDMigrator(s.mockTwirpClient)
	s.repo = &azpResourcesLoader{
		db:          s.conn,
		obs:         observability.NewTestObservability(),
		gidMigrator: s.globalIDMigrator,
	}
	s.mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		if strings.HasPrefix(globalID, nextIDPrefix) {
			// already a next id, return original argument
			return types.GlobalID(globalID)
		}
		return nextIDFromGlobalID(types.GlobalID(globalID))
	}, nil)
}

func (s *AzpResourcesLoaderSuite) SetupTest() {
	_, err := s.conn.Conn().Exec(`TRUNCATE azp_resources`)
	s.Require().NoError(err)
	_, err = s.conn.Conn().Exec(`TRUNCATE workflow_builds`)
	s.Require().NoError(err)
}

func (s *AzpResourcesLoaderSuite) TestGetByExisitingID_NoResults() {
	res, found, err := s.repo.GetByTenantID(context.Background(), "some-missing-tenant-id")
	s.NoError(err)
	s.False(found)
	s.Nil(res)
}

func (s *AzpResourcesLoaderSuite) TestGetByExisitingID_Result() {
	s.conn.ExecContext(
		context.Background(),
		"INSERT INTO azp_resources SET entity_id=?, tenant_id=?",
		testRepoGlobalID,
		testTenantID,
	)
	res, found, err := s.repo.GetByTenantID(context.Background(), testTenantID)
	s.NoError(err)
	s.True(found)

	s.Equal(types.GlobalID(testRepoGlobalID), res.EntityID)
	s.Equal(testTenantID, res.TenantID)
}

func (s *AzpResourcesLoaderSuite) TestGetByGlobalID_Result() {
	pipelinesScaleUnitId, _ := types.ParseScaleUnitID(testPipelinesScaleUnitID)
	_, err := s.conn.Conn().Exec(`
		INSERT INTO azp_resources
			SET
				entity_id=?,
				entity_next_id=?,
				environment=?,
				tenant_name=?,
				tenant_id=?,
				project_name=?,
				pipelines_scale_unit_id=?
		`,
		testRepoGlobalID,
		nextIDFromGlobalID(testRepoGlobalID),
		testEnvironment,
		testTenantName,
		testTenantID,
		testProjectName,
		pipelinesScaleUnitId,
	)
	s.Require().NoError(err)

	res, found, err := s.repo.GetByGlobalID(context.Background(), testRepoGlobalID, testEnvironment)
	s.NoError(err)
	s.True(found)

	s.Equal(testTenantName, res.TenantName)
	s.Equal(testTenantID, res.TenantID)
	s.Equal(pipelinesScaleUnitId, res.PipelinesScaleUnitID)
}

func (s *AzpResourcesLoaderSuite) TestGetByGlobalID_Result_NextColumn() {
	pipelinesScaleUnitId, _ := types.ParseScaleUnitID(testPipelinesScaleUnitID)
	_, err := s.conn.Conn().Exec(`
		INSERT INTO azp_resources
			SET
				entity_id=?,
				entity_next_id=?,
				environment=?,
				tenant_name=?,
				tenant_id=?,
				project_name=?,
				pipelines_scale_unit_id=?
			`,
		testRepoGlobalID,
		nextIDFromGlobalID(testRepoGlobalID),
		testEnvironment,
		testTenantName,
		testTenantID,
		testProjectName,
		pipelinesScaleUnitId,
	)
	s.Require().NoError(err)

	res, found, err := s.repo.GetByGlobalID(context.Background(), nextIDFromGlobalID(testRepoGlobalID), testEnvironment)
	s.NoError(err)
	s.True(found)

	s.Equal(testTenantName, res.TenantName)
	s.Equal(testTenantID, res.TenantID)
	s.Equal(pipelinesScaleUnitId, res.PipelinesScaleUnitID)
}

func (s *AzpResourcesLoaderSuite) TestGetByGlobalID_Result_EmptyPipelinesScaleUnitId() {
	_, err := s.conn.Conn().Exec(`
		INSERT INTO azp_resources
			SET
				entity_id=?,
				entity_next_id=?,
				environment=?,
				tenant_name=?,
				tenant_id=?,
				project_name=?,
				pipelines_scale_unit_id=?
			`,
		testRepoGlobalID,
		nextIDFromGlobalID(testRepoGlobalID),
		testEnvironment,
		testTenantName,
		testTenantID,
		testProjectName,
		nil,
	)
	s.Require().NoError(err)

	res, found, err := s.repo.GetByGlobalID(context.Background(), nextIDFromGlobalID(testRepoGlobalID), testEnvironment)
	s.NoError(err)
	s.True(found)

	s.Equal(testTenantName, res.TenantName)
	s.Equal(testTenantID, res.TenantID)
	s.Equal(types.NilScaleUnitID, res.PipelinesScaleUnitID)
}

func (s *AzpResourcesLoaderSuite) TestGetByGlobalID_NoResult() {
	res, found, err := s.repo.GetByGlobalID(context.Background(), "not", "there")

	s.NoError(err)
	s.False(found)
	s.Nil(res)
}

func (s *AzpResourcesLoaderSuite) TestGetByTenantName_NoResults() {
	res, found, err := s.repo.GetByTenantName(context.Background(), "some-missing-tenant-name")
	s.NoError(err)
	s.False(found)
	s.Nil(res)
}

func (s *AzpResourcesLoaderSuite) TestGetByTenantName_Result() {
	s.conn.ExecContext(
		context.Background(),
		"INSERT INTO azp_resources SET entity_id=?, tenant_id=?, tenant_name=?, environment=?",
		testRepoGlobalID,
		testTenantID,
		testTenantName,
		testEnvironment,
	)
	res, found, err := s.repo.GetByTenantName(context.Background(), testTenantName)
	s.NoError(err)
	s.True(found)

	s.Equal(types.GlobalID(testRepoGlobalID), res.EntityID)
	s.Equal(testTenantID, res.TenantID)
	s.Equal(testEnvironment, res.Environment)
}
