package payloads

import (
	"context"
	"database/sql"
	"os"
	"testing"

	"github.com/facebookgo/clock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/testutils"
)

type PayloadsRepositorySuite struct {
	suite.Suite
	conn  *sql.DB
	clock *clock.Mock
	store *DBStore
}

func TestPayloadsRepository(t *testing.T) {
	noShort(t)
	suite.Run(t, new(PayloadsRepositorySuite))
}

func (s *PayloadsRepositorySuite) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("ACTIONS_PAYLOADS_TEST_DATABASE_URL"))
	s.Require().NoError(err)
	s.conn = conn

	pdb := asql.New(s.conn, logger.TestLogger(), statter.NullStatter(), testutils.NewNoopBreaker(), asql.PayloadsCluster)
	s.clock = clock.NewMock()
	s.store = New(pdb, logger.TestLogger(), statter.NullStatter())

	// clean out DB
	_, err = s.conn.Exec(`TRUNCATE payloads`)
	s.Require().NoError(err)
}

func (s *PayloadsRepositorySuite) TestPersist() {
	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 789))

	payloadID, err := s.store.Persist(context.Background(), 123, []byte("testing"), repoID)
	s.Require().NoError(err)
	s.Assert().NotZero(payloadID)

	payload, err := s.store.Get(context.Background(), 123, "")
	s.Require().NoError(err)
	s.Assert().Equal([]byte("testing"), payload)
}

func (s *PayloadsRepositorySuite) TestGetPayloadMissingWorkflowBuildID() {
	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 789))

	payloadID, err := s.store.Persist(context.Background(), 123, []byte("testing"), repoID)
	s.Require().NoError(err)
	s.Assert().NotZero(payloadID)

	_, err = s.store.Get(context.Background(), 456, repoID)
	s.Require().Error(err)
	s.Assert().Equal(err.Error(), "no payload can be found for workflow build")
}

func (s *PayloadsRepositorySuite) TearDownSuite() {
	err := s.conn.Close()
	s.Require().NoError(err)
}

func noShort(t *testing.T) {
	if testing.Short() {
		t.Skip("skip because -short was selected")
	}
}
