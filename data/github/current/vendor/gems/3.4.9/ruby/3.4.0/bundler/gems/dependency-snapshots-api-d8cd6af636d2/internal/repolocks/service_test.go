package repolocks

import (
	"context"
	"errors"
	"go.uber.org/atomic"
	"testing"
	"time"

	"github.com/github/dependency-snapshots-api/internal/testutil"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/suite"
	"go.uber.org/goleak"
	"golang.org/x/sync/errgroup"
)

type LockTestSuite struct {
	suite.Suite
	testDB      *testutil.TestDB
	repoLockSvc Service
}

func TestRepoLocksSuite(t *testing.T) {
	suite.Run(t, new(LockTestSuite))
}

func (s *LockTestSuite) SetupSuite() {
	tdb, err := testutil.NewNamedTestDB(s.T(), testutil.CreateTestConfig(s.T()), log.NewNullLogger(), stats.NullStatter, "repolocks")
	s.Require().NoError(err)
	s.testDB = tdb

	s.repoLockSvc = NewService(tdb.DB, log.NewNullLogger(), stats.NullStatter)

}

func (s *LockTestSuite) TearDownSuite() {
	s.Require().NoError(s.testDB.Close())
}

func (s *LockTestSuite) BeforeTest(_, _ string) {
	s.Require().NoError(s.testDB.DeleteTables())
}

func (s *LockTestSuite) AfterTest(_, _ string) {
	s.Require().NoError(s.testDB.DeleteTables())
}

func (s *LockTestSuite) TestRepoLockUnlock() {

	ctx := context.Background()

	lock, err := s.repoLockSvc.Lock(ctx, 1, "abc", time.Minute)
	s.Require().NoError(err)
	s.Require().NotNil(lock)
	s.Require().True(lock.IsLocked())

	lock2, err := s.repoLockSvc.Lock(ctx, 1, "abc", time.Minute)
	s.Require().Error(err)
	s.Require().Nil(lock2)
	s.Require().True(errors.Is(err, ErrAlreadyLocked))

	lock.Unlock()
	s.Require().False(lock.IsLocked())

	lock3, err := s.repoLockSvc.Lock(ctx, 1, "abc", time.Minute)
	s.Require().NoError(err)
	s.Require().NotNil(lock3)
	s.Require().True(lock3.IsLocked())

	lock3.Unlock()
	s.Require().False(lock3.IsLocked())

}

func (s *LockTestSuite) TestRelock() {

	ctx := context.Background()
	lock, err := s.repoLockSvc.Lock(ctx, 1, "abc", 2*time.Second)
	s.Require().NoError(err)
	s.Require().NotNil(lock)
	s.Require().True(lock.IsLocked())

	firstExpiration := lock.ExpiresAt()
	time.Sleep(250 * time.Millisecond)
	s.Require().NoError(lock.ReLock(ctx))
	secondExpiration := lock.ExpiresAt()
	s.Require().True(firstExpiration.Before(secondExpiration))

	time.Sleep(250 * time.Millisecond)
	s.Require().NoError(lock.ReLock(ctx))
	thirdExpiration := lock.ExpiresAt()
	s.Require().True(secondExpiration.Before(thirdExpiration))
}

func (s *LockTestSuite) TestConcurrentLocks() {
	ctx := context.Background()
	var eg errgroup.Group
	var acquired atomic.Uint32
	for i := 0; i < 15; i++ {
		eg.Go(func() error {
			// any error not ErrAlreadyLocked is bubbled up as an error from the errgroup
			for {
				lock, err := s.repoLockSvc.Lock(ctx, 5, "concurrent", 100*time.Millisecond)
				if err != nil {
					if errors.Is(err, ErrAlreadyLocked) {
						continue
					}
					return err
				}
				acquired.Inc()
				sleepDuration := time.Until(lock.ExpiresAt())
				//fmt.Printf("lock #%v; %s acquired, sleeping %v\n", acquired, lock, sleepDuration)
				time.Sleep(sleepDuration)

				lock.Unlock()
				s.Require().False(lock.IsLocked())
				return nil
			}
		})
	}

	s.Require().Eventually(func() bool {
		s.Require().NoError(eg.Wait())
		return true
	}, 30*time.Second, time.Second, "errgroup never returned that all locks were acquired: %d", acquired.Load())

	s.Require().Equal(uint32(15), acquired.Load())
}

func (s *LockTestSuite) TestRelockWorksUnlockNotifies() {
	ctx := context.Background()
	defer goleak.VerifyNone(s.T(), goleak.IgnoreCurrent())

	lock, err := s.repoLockSvc.Lock(ctx, 10, "foobar", 500*time.Millisecond)
	s.Require().NoError(err)
	originalExpiration := lock.ExpiresAt()
	lock.StartRelocker(context.Background())

	// unlock after 2 seconds
	go func() {
		time.Sleep(1 * time.Second)
		lock.Unlock()
	}()

	s.Require().Eventually(func() bool {
		<-lock.NotifyUnlocked()
		return true
	}, 5*time.Second, 50*time.Millisecond)

	s.Require().False(lock.IsLocked())
	s.Require().Greater(lock.ExpiresAt(), originalExpiration, "expected at least one re-lock that incremented the expiration")
}
