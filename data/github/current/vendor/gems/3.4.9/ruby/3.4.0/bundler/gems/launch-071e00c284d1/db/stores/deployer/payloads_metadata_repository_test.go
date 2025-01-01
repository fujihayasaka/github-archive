package deployer

import (
	"context"
	"database/sql"
	"os"
	"testing"

	"github.com/facebookgo/clock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/testutils"
)

type PayloadMetadataRepositorySuite struct {
	suite.Suite
	conn                 *sql.DB
	adb                  *asql.SQL
	payloadsMetadataRepo PayloadMetadataRepository
}

func TestPayloadMetadataRepositorySuite(t *testing.T) {
	testutils.NoShort(t)
	suite.Run(t, new(PayloadMetadataRepositorySuite))
}

func (s *PayloadMetadataRepositorySuite) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)

	clock := clock.NewMock()

	obs := observability.NewTestObservability()

	s.adb = asql.New(conn, obs.Logger, obs.Statter, testutils.NewNoopBreaker(), asql.LaunchCluster)

	s.payloadsMetadataRepo = NewPayloadMetadataStoreSQL(s.adb, obs.Logger, obs.Statter, clock)
}

func (s *PayloadMetadataRepositorySuite) SetupTest() {
	_, err := s.adb.Conn().Exec(`TRUNCATE workflow_payloads_metadata`)
	s.Require().NoError(err)
}

func (s *PayloadMetadataRepositorySuite) TearDownSuite() {
	s.Require().NoError(s.adb.Close())
}

func (s *PayloadMetadataRepositorySuite) TestPersist() {
	err := s.payloadsMetadataRepo.Persist(context.Background(), 1, 1, 1)
	s.Require().NoError(err)

	var count int
	err = s.adb.Conn().QueryRow(`SELECT COUNT(*) FROM workflow_payloads_metadata`).Scan(&count)
	s.Require().NoError(err)
	s.Equal(1, count)
}

func (s *PayloadMetadataRepositorySuite) TestGet() {
	err := s.payloadsMetadataRepo.Persist(context.Background(), 1, 1, 1)
	s.Require().NoError(err)

	metadata, ok, err := s.payloadsMetadataRepo.Get(context.Background(), 1)
	s.Require().NoError(err)
	s.True(ok)
	s.Equal(&PayloadMetadata{StorageAccountID: 1, Version: 1}, metadata)
}
