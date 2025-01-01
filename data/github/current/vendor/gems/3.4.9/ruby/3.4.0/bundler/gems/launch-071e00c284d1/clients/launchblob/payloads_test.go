package launchblob

import (
	"context"
	"database/sql"
	"os"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/github/go-blob"
	"github.com/github/go-blob/azure"
	"github.com/stretchr/testify/suite"

	"github.com/facebookgo/clock"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/payloads"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"

	"github.com/github/launch/utils/testutils"
)

const (
	testContainer     = "payloads"
	testAccountPrefix = "devstoreaccount"
	testAccountName   = "devstoreaccount1"
	testAccountKey    = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="
	testFile          = "testfile/world/"
)

type payloadsSuite struct {
	suite.Suite

	accounts         []string
	blobClient       blob.Client
	conn             *sql.DB
	obs              *observability.Observability
	payloads         payloads.Store
	payloadsMetadata deployer.PayloadMetadataRepository
}

func TestBlobPayloadsSuite(t *testing.T) {
	suite.Run(t, new(payloadsSuite))
}

func (s *payloadsSuite) SetupSuite() {
	ctx := context.Background()

	s.obs = observability.NewTestObservability()

	s.accounts = []string{
		testAccountName,
	}

	client, err := azure.NewClient(
		s.accounts,
		azure.WithBaseURLFormat(os.Getenv("AZURITE_BLOB_HOST")+"/%s"),
		azure.WithAccountKeyAuth(testAccountKey),
	)

	err = client.CreateContainer(ctx, testAccountName, testContainer)
	if err != nil && !bloberror.HasCode(err, bloberror.ContainerAlreadyExists) {
		s.Suite.Require().NoError(err)
	}

	s.blobClient = client

	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Suite.Require().NoError(err)

	s.conn = conn

	adb := asql.New(conn, s.obs.Logger, s.obs.Statter, testutils.NewNoopBreaker(), asql.LaunchCluster)

	clock := clock.NewMock()

	s.payloadsMetadata = deployer.NewPayloadMetadataStoreSQL(adb, s.obs.Logger, s.obs.Statter, clock)
	s.payloads, err = NewPayloadStore(
		s.blobClient,
		[]int{1},
		testAccountPrefix,
		1,
		testContainer,
		s.obs.Logger,
		s.obs.Statter,
		s.payloadsMetadata,
	)
	s.Suite.Require().NoError(err)
}

func (s *payloadsSuite) SetupTest() {
	_, err := s.conn.Exec(`TRUNCATE workflow_payloads_metadata`)
	s.Suite.Require().NoError(err)
}

func (s *payloadsSuite) TearDownSuite() {
	err := s.conn.Close()
	s.Suite.Require().NoError(err)
}

func (s *payloadsSuite) TestPayloadPersistToBlob() {
	ctx := context.Background()

	repo := types.GlobalID(testutils.EncodeGlobalID("Repository", 789))

	_, err := s.payloads.Persist(ctx, 1, []byte("hello"), repo)
	s.Suite.Require().NoError(err)
}

func (s *payloadsSuite) TestPayloadGetFromBlob() {
	ctx := context.Background()

	repo := types.GlobalID(testutils.EncodeGlobalID("Repository", 789))

	_, err := s.payloads.Persist(ctx, 1, []byte("hello"), repo)
	s.Suite.Require().NoError(err)

	payload, err := s.payloads.Get(ctx, 1, repo)
	s.Suite.Require().NoError(err)
	s.Suite.Equal([]byte("hello"), payload)
}
