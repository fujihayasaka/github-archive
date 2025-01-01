package deployer

import (
	"context"
	"math/rand"
	"os"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"golang.org/x/sync/errgroup"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type AzpResourcesRepositorySuite struct {
	suite.Suite
	conn             *asql.SQL
	repo             *azpResourcesRepository
	repoB            *azpResourcesRepository
	globalIDMigrator GlobalIDMigrator
	mockTwirpClient  *ghtwirp.MockClient
}

func TestAzpResourcesRepository(t *testing.T) {
	testutils.NoShort(t)
	suite.Run(t, new(AzpResourcesRepositorySuite))
}

const (
	testLockPollFreq    = time.Millisecond * 5
	testLockMaxWait     = time.Millisecond * 50
	testLockLongMaxWait = time.Millisecond * 500
)

func (s *AzpResourcesRepositorySuite) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)
	s.conn = asql.New(conn, logger.TestLogger(), statter.NullStatter(), testutils.NewNoopBreaker(), asql.LaunchCluster)

	s.mockTwirpClient = ghtwirp.NewMockClient(s.T())
	s.globalIDMigrator = NewGlobalIDMigrator(s.mockTwirpClient)
	s.mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		if strings.HasPrefix(globalID, nextIDPrefix) {
			// already a next id, return original argument
			return types.GlobalID(globalID)
		}
		return nextIDFromGlobalID(types.GlobalID(globalID))
	}, nil)

	s.repo = &azpResourcesRepository{
		db:            s.conn,
		environment:   "test",
		obs:           observability.NewTestObservability(),
		lockPollFreq:  testLockPollFreq,
		lockDuration:  testLockMaxWait,
		gidMigrator:   s.globalIDMigrator,
		ghTwirpClient: s.mockTwirpClient,
	}

	s.repoB = &azpResourcesRepository{
		db:            s.conn,
		environment:   "test",
		obs:           observability.NewTestObservability(),
		lockPollFreq:  testLockPollFreq,
		lockDuration:  testLockMaxWait,
		gidMigrator:   s.globalIDMigrator,
		ghTwirpClient: s.mockTwirpClient,
	}
}

func (s *AzpResourcesRepositorySuite) SetupTest() {
	_, err := s.conn.Conn().Exec(`TRUNCATE azp_resources`)
	s.Require().NoError(err)
}

var (
	testResources = azptypes.BackingResources{
		CreationResult: azptypes.CreationResult{
			EntityID:                 "test-existing-resources",
			TenantName:               "test-org-name",
			TenantID:                 "f393b0d3-a287-4108-98cb-d0fc78b2ec18",
			ProjectName:              "test-project-name",
			PipelineID:               4,
			ClientID:                 "test-client-id",
			PipelinesScaleUnitID:     "1234543a-4531-bc43-ad23-a341b53cec14",
			ArtifactCacheScaleUnitID: "1709abc2-34b6-12ce-ba56-abb24ed168ca",
			RunnerScaleUnitID:        "",
		},
		EncryptedPrivateKey: []byte("test-private-key"),
		Environment:         "test",
	}
)

func (s *AzpResourcesRepositorySuite) TestGetOrCreateNoExistingResources() {
	repoID := types.GlobalID("test-no-existing-resources")
	ctx := context.Background()

	called := false
	resources, outcome, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		called = true
		return &testResources, nil
	})
	s.Require().NoError(err)

	s.Assert().True(called)
	s.Assert().Equal(resources, &testResources)
	s.Assert().Equal(OrgCreationSuccess, outcome)
}

func (s *AzpResourcesRepositorySuite) TestGetOrCreateExistingResources() {
	repoID := types.GlobalID("test-existing-resources")
	ctx := context.Background()

	_, outcome, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		return &testResources, nil
	})
	s.Require().NoError(err)
	s.Assert().Equal(OrgCreationSuccess, outcome)

	resources, outcome, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		return nil, errors.New("called create handler while there is are existing resources")
	})
	testResources.CreatedAt = resources.CreatedAt // copy created timestamp value so Assert doesn't fail
	s.Require().NoError(err)

	s.Assert().Equal(resources, &testResources)
	s.Assert().Equal(OrgCreationUnnecessary, outcome)
}

func (s *AzpResourcesRepositorySuite) TestGetOrCreateExistingResources_NextColumn() {
	repoID := types.GlobalID("test-existing-resources")
	ctx := context.Background()

	_, outcome, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		return &testResources, nil
	})
	s.Require().NoError(err)
	s.Assert().Equal(OrgCreationSuccess, outcome)

	resources, outcome, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		return nil, errors.New("called create handler while there is are existing resources")
	})
	testResources.CreatedAt = resources.CreatedAt // copy created timestamp value so Assert doesn't fail
	s.Require().NoError(err)

	s.Assert().Equal(resources, &testResources)
	s.Assert().Equal(OrgCreationUnnecessary, outcome)

	resources, outcome, err = s.repo.GetOrCreate(ctx, nextIDFromGlobalID(repoID), func(ctx context.Context) (*azptypes.BackingResources, error) {
		return nil, errors.New("called create handler while there is are existing resources")
	})
	nextTestResources := testResources
	nextTestResources.CreatedAt = resources.CreatedAt // copy created timestamp value so Assert doesn't fail
	nextTestResources.EntityID = nextIDFromGlobalID(repoID)
	s.Require().NoError(err)

	s.Assert().Equal(resources, &nextTestResources)
	s.Assert().Equal(OrgCreationUnnecessary, outcome)
}

func (s *AzpResourcesRepositorySuite) TestGetOrCreateWaitsForLock() {
	repoID := types.GlobalID("test-get-locked-row")
	ctx := context.Background()

	r := NewAZPResourcesRepo(
		s.conn,
		"test",
		observability.NewTestObservability(),
		testLockPollFreq,
		time.Minute*20, // We (basically) never want the lock to expire for this repository
		s.globalIDMigrator,
		s.mockTwirpClient,
	)

	eg, ctx := errgroup.WithContext(ctx)

	events := NewEventOrder()
	var waitForLock sync.WaitGroup
	waitForLock.Add(1)

	eg.Go(func() error {
		events.Add("A")
		_, _, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
			events.Add("B")
			// Allow the other routine to wait for the lock to be taken
			waitForLock.Done()
			// Hold the lock to demonstate the other call waiting
			time.Sleep(testLockPollFreq * 5)
			return &testResources, nil
		})
		return err
	})

	eg.Go(func() error {
		// Wait for the lock to be taken by the other routine
		waitForLock.Wait()
		events.Add("C")
		_, _, err := r.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
			s.Assert().Fail("should not have run this")
			return nil, errors.New("called create handler while the row is locked")
		})
		return err
	})

	s.Require().NoError(eg.Wait())
	s.Assert().Equal("ABC", events.String())
}

func (s *AzpResourcesRepositorySuite) TestGetOrCreateParsingPipelinesScaleUnitIDsError() {
	repoID := types.GlobalID("test-no-existing-resources")
	ctx := context.Background()

	called := false
	testResourcesError := testResources
	testResourcesError.PipelinesScaleUnitID = "not-an-uuid"
	_, outcome, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		called = true
		return &testResourcesError, nil
	})
	s.Assert().Error(err)

	s.Assert().True(called)
	s.Assert().Equal(OrgCreationError, outcome)
}

func (s *AzpResourcesRepositorySuite) TestGetOrCreateParsingArtifactCacheScaleUnitIDError() {
	repoID := types.GlobalID("test-no-existing-resources")
	ctx := context.Background()

	called := false
	testResourcesError := testResources
	testResourcesError.ArtifactCacheScaleUnitID = "not-an-uuid"
	_, outcome, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		called = true
		return &testResourcesError, nil
	})
	s.Assert().Error(err)

	s.Assert().True(called)
	s.Assert().Equal(OrgCreationError, outcome)
}

func (s *AzpResourcesRepositorySuite) TestGetOrCreateParsingRunnerScaleUnitIDError() {
	repoID := types.GlobalID("test-no-existing-resources")
	ctx := context.Background()

	called := false
	testResourcesError := testResources
	testResourcesError.RunnerScaleUnitID = "not-an-uuid"
	_, outcome, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		called = true
		return &testResourcesError, nil
	})
	s.Assert().Error(err)

	s.Assert().True(called)
	s.Assert().Equal(OrgCreationError, outcome)
}

func (s *AzpResourcesRepositorySuite) TestGetOrCreateUnlockedOnError() {
	repoID := types.GlobalID("test-error-unlock")
	ctx := context.Background()

	var waitForLock sync.WaitGroup
	waitForLock.Add(1)

	var waitForTest sync.WaitGroup
	waitForTest.Add(2)

	events := NewEventOrder()

	go (func() {
		defer waitForTest.Done()

		// runs first, errors
		events.Add("A")
		_, _, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
			// Allow the other routine to wait for the lock to be taken
			waitForLock.Done()
			// Hold the lock to demonstrate the other routine waiting
			time.Sleep(testLockPollFreq * 5)

			events.Add("C")
			return nil, errors.New("fail")
		})
		s.Assert().Error(err)
	})()

	go (func() {
		defer waitForTest.Done()

		// Wait for the lock to be taken by the other routine
		waitForLock.Wait()
		events.Add("B")
		_, _, err := s.repoB.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
			events.Add("D")
			return &testResources, nil
		})
		s.Assert().NoError(err)
	})()

	waitForTest.Wait()

	s.Assert().Equal("ABCD", events.String())
}

func (s *AzpResourcesRepositorySuite) TestGetOrCreateWaitForLockExpiry() {
	repoID := types.GlobalID("test-lock-expiry")
	ctx := context.Background()

	assertions := s.Assert()

	events := NewEventOrder()

	stopTest := make(chan bool, 1)
	var wg sync.WaitGroup
	wg.Add(1)

	go (func() {
		events.Add("A")
		_, _, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
			// Make sure that the main routine has a chance to wait on wg and then unlock it
			runtime.Gosched()
			events.Add("B")
			wg.Done()

			// Wait until the first routine is done or time out at 10s
			select {
			case <-stopTest:
				events.Add("OK")
				wg.Done()
				return nil, errors.New("abort")
			case <-time.After(10 * time.Second):
				events.Add("TIMEOUT")
				wg.Done()
				return nil, errors.New("timed out")
			}
		})
		assertions.Error(err)
	})()

	// Wait for the lock to be taken by the other routine
	wg.Wait()

	wg.Add(1)
	events.Add("C")

	// This will steal the lock from the first goroutine and execute the creation
	_, _, err := s.repoB.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		events.Add("D")
		return &testResources, nil
	})

	s.Assert().NoError(err)
	s.Assert().Equal("ABCD", events.String())

	// Stop first goroutine and check that it didn't time out
	stopTest <- true
	wg.Wait()
	s.Assert().Equal("OK", events.String())
}

func (s *AzpResourcesRepositorySuite) TestGetOrCreateConcurrency() {
	iterations := 5
	workerCount := 3
	repoID := types.GlobalID("test-concurrency-lock")
	ctx := context.Background()

	iter := func() {
		// start each test run with an empty DB
		s.SetupTest()

		calls := 0
		eg, _ := errgroup.WithContext(context.TODO())

		repos := make([]*azpResourcesRepository, 0)
		// make all connections first
		for wc := 0; wc < workerCount; wc++ {
			r := NewAZPResourcesRepo(
				s.conn,
				"test",
				observability.NewTestObservability(),
				testLockPollFreq,
				testLockLongMaxWait,
				s.globalIDMigrator,
				s.mockTwirpClient,
			)
			rr := r.(*azpResourcesRepository)
			repos = append(repos, rr)
		}

		for _, loopRepo := range repos {
			thisRepo := loopRepo
			// scheduling of go routines will cause these to run in a random order
			eg.Go(func() error {
				_, _, err := thisRepo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
					calls++
					time.Sleep(time.Millisecond * time.Duration(rand.Float32()*10))
					return &testResources, nil
				})
				s.Assert().NoError(err)

				return nil
			})
		}

		s.Assert().NoError(eg.Wait())
		s.Assert().Equal(1, calls)
	}

	for tc := 0; tc < iterations; tc++ {
		iter()
	}
}

func (s *AzpResourcesRepositorySuite) TestGetOrCreateUpdatesNextGlobalID() {
	repoID := types.GlobalID("test-find-me")
	testOrgName := "one-off-test-name"
	ctx := context.Background()

	// Have to reset all mocks since we want a different one for GetNextGlobalID
	s.mockTwirpClient.ExpectedCalls = []*mock.Call{}
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, mock.Anything).Return(nextIDFromGlobalID(repoID), nil)

	res, _, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		tr := testResources
		tr.TenantName = testOrgName
		return &tr, nil
	})
	s.Require().NoError(err)

	var entityIDRes, entityNextIDRes types.GlobalID
	err = s.conn.QueryScan(ctx, "select entity_id, entity_next_id from azp_resources where tenant_id = ?", asql.Params(res.CreationResult.TenantID), &entityIDRes, &entityNextIDRes)
	s.Require().NoError(err)
	s.Require().Equal(entityIDRes, entityNextIDRes)
}

func (s *AzpResourcesRepositorySuite) TestTryGetNoExistingResources() {
	repoID := types.GlobalID("test-no-existing-resources")
	ctx := context.Background()

	resources, err := s.repo.TryGet(ctx, repoID)

	s.Assert().Error(err)
	s.Assert().Nil(resources)
}

func (s *AzpResourcesRepositorySuite) TestTryGetExistingResources() {
	repoID := types.GlobalID("test-existing-resources")
	ctx := context.Background()

	_, outcome, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		return &testResources, nil
	})
	s.Require().NoError(err)

	resources, err := s.repo.TryGet(ctx, repoID)
	testResources.CreatedAt = resources.CreatedAt // copy created timestamp value so Assert doesn't fail
	s.Require().NoError(err)

	s.Assert().Equal(resources, &testResources)
	s.Assert().Equal(OrgCreationSuccess, outcome)
}

func (s *AzpResourcesRepositorySuite) TestTryGetWaitsForLock() {
	repoID := types.GlobalID("test-get-locked-row")
	ctx := context.Background()

	eg, ctx := errgroup.WithContext(ctx)

	var waitForLock sync.WaitGroup
	waitForLock.Add(1)
	var waitForGet sync.WaitGroup
	waitForGet.Add(1)

	eg.Go(func() error {
		waitForLock.Wait()
		_, err := s.repo.TryGet(ctx, repoID)
		waitForGet.Done()
		return err
	})

	ctx = context.Background()
	_, outcome, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		waitForLock.Done()
		waitForGet.Wait()
		return &testResources, nil
	})
	s.Assert().NoError(err)

	s.Require().Error(eg.Wait())
	s.Assert().Equal(OrgCreationSuccess, outcome)
}

func (s *AzpResourcesRepositorySuite) TestGetDataForAbuseHydro() {
	repoID := nextIDFromGlobalID("test-find-me")
	testOrgName := "one-off-test-name"
	ctx := context.Background()

	_, _, err := s.repo.GetOrCreate(ctx, repoID, func(ctx context.Context) (*azptypes.BackingResources, error) {
		tr := testResources
		tr.TenantName = testOrgName
		return &tr, nil
	})
	s.Require().NoError(err)

	res, err := s.repo.GetDataForAbuseHydro(ctx, []string{testOrgName})
	s.Require().NoError(err)

	s.Equal(&AbuseHydroDBData{
		EntityIDsToTenantIDs: map[types.GlobalID]string{
			repoID: testOrgName,
		},
	}, res)
}

// concurrency safe event ordering helper
func NewEventOrder() EventOrder {
	return make(chan string, 20)
}

type EventOrder chan string

func (e EventOrder) String() string {
	b := strings.Builder{}
	for {
		select {
		case s := <-e:
			b.WriteString(s)
		default:
			return b.String()
		}
	}
}
func (e EventOrder) Add(s string) {
	e <- s
}

func (s *AzpResourcesRepositorySuite) TestGetAzpResourcesError() {
	entityID := types.GlobalID("test-entity")
	err := NewGetAzpResourcesError(entityID)

	s.Equal("failed to get AZP resources", err.Error())

	f := err.Context().Field("gh.launch.entity.global_id")
	s.Equal(entityID, f.Value(), "the error has expected context")
}
func (s *AzpResourcesRepositorySuite) TestGetAzpResourcesErrorTypeAssertion() {
	factory := func() error {
		return NewGetAzpResourcesError(types.NilGlobalID)
	}
	_, ok := errors.Cause(factory()).(*GetAzpResourcesError)
	s.True(ok)
}

func (s *AzpResourcesRepositorySuite) TestDeleteEntity() {
	testDeleteEntity := types.GlobalID("test-repository-delete")
	testEntityNotToDelete := types.GlobalID("test-repository-do-not-delete")

	s.createTestAzpResourcesTable(testDeleteEntity.String(), testEntityNotToDelete.String())
	ctx := context.Background()

	const query = `SELECT COUNT(*) from azp_resources
		where entity_id=?
		and environment in ("production","lab","test","development")`

	var entityCount int
	s.conn.Conn().QueryRowContext(ctx, query, testDeleteEntity).Scan(&entityCount)
	s.Assert().Equal(4, entityCount)

	deletedCount, err := s.repo.ArchiveEntity(ctx, testDeleteEntity)
	s.NoError(err)

	var postDeleteCount int
	s.conn.Conn().QueryRowContext(ctx, query, testDeleteEntity).Scan(&postDeleteCount)
	s.Assert().Equal(4, int(deletedCount))
	s.Assert().Equal(0, postDeleteCount)

	// verify other entities were not modified
	s.conn.Conn().QueryRowContext(ctx, query, testEntityNotToDelete).Scan(&postDeleteCount)
	s.Assert().Equal(1, postDeleteCount)
}

func (s *AzpResourcesRepositorySuite) TestDeleteEntity_NextColumn() {
	testDeleteEntity := types.GlobalID("test-repository-delete")
	testEntityNotToDelete := types.GlobalID("test-repository-do-not-delete")

	s.createTestAzpResourcesTable(testDeleteEntity.String(), testEntityNotToDelete.String())
	ctx := context.Background()

	const query = `SELECT COUNT(*) from azp_resources
		where entity_id=?
		and environment in ("production","lab","test","development")`

	var entityCount int
	s.conn.Conn().QueryRowContext(ctx, query, testDeleteEntity).Scan(&entityCount)
	s.Assert().Equal(4, entityCount)

	deletedCount, err := s.repo.ArchiveEntity(ctx, nextIDFromGlobalID(testDeleteEntity))
	s.NoError(err)

	var postDeleteCount int
	s.conn.Conn().QueryRowContext(ctx, query, testDeleteEntity).Scan(&postDeleteCount)
	s.Assert().Equal(4, int(deletedCount))
	s.Assert().Equal(0, postDeleteCount)

	// verify other entities were not modified
	s.conn.Conn().QueryRowContext(ctx, query, testEntityNotToDelete).Scan(&postDeleteCount)
	s.Assert().Equal(1, postDeleteCount)
}

func (s *AzpResourcesRepositorySuite) createTestAzpResourcesTable(deleteEntity string, notDeleteEntity string) {
	deleteEntityNext := nextIDFromGlobalID(types.GlobalID(deleteEntity)).String()
	notDeleteEntityNext := nextIDFromGlobalID(types.GlobalID(notDeleteEntity)).String()
	_, err := s.conn.Conn().Exec(`
		TRUNCATE azp_resources
	`)
	s.Require().NoError(err)
	_, err = s.conn.Conn().Exec(`
		INSERT INTO azp_resources (
		  id,
		  entity_id,
		  entity_next_id,
		  environment
		)
		VALUES
			(1, ?, ?, "production"),
			(2, ?, ?, "production"),
			(3, ?, ?, "lab"),
			(4, ?, ?, "test"),
			(5, ?, ?, "development"),
			(6, ?, ?, "production-deleted-1649986344"),
			(7, ?, ?, "lab-deleted-1649986344"),
			(8, ?, ?, "test-deleted-1649986344"),
			(9, ?, ?, "development-deleted-1649986344")
	`,
		deleteEntity, deleteEntityNext,
		notDeleteEntity, notDeleteEntityNext,
		deleteEntity, deleteEntityNext,
		deleteEntity, deleteEntityNext,
		deleteEntity, deleteEntityNext,
		deleteEntity, deleteEntityNext,
		deleteEntity, deleteEntityNext,
		deleteEntity, deleteEntityNext,
		deleteEntity, deleteEntityNext,
	)
	s.Require().NoError(err)
}
