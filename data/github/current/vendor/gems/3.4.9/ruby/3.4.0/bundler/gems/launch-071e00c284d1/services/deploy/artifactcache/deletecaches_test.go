package artifactcache

import (
	context "context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	errs "github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type deleteCachesTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestDeleteCachesTestSuite(t *testing.T) {
	suite.Run(t, new(deleteCachesTestSuite))
}

func (s *deleteCachesTestSuite) SetupTest() {
	s.rcf = &azp.MockRepositoryClientFactory{}
	s.arr = &deployer.MockAzpResourcesRepository{}
	s.rrc = &azp.MockRepositoryClient{}
	s.svc = &service{
		log:               logger.TestLogger(),
		stats:             statter.NullStatter(),
		repoClientFactory: s.rcf,
		resourceRepo:      s.arr,
	}
}

func (s *deleteCachesTestSuite) TestServiceWillDeleteCacheForDeleteCacheByID() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("DeleteCacheByID", mock.Anything, int64(1)).Return(nil)

	req := &DeleteCacheByIDRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		CacheId: int64(1),
	}

	res, err := s.svc.DeleteCacheByID(context.TODO(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.Status, "deleted")
}

func (s *deleteCachesTestSuite) TestServiceFailsWithInvalidGlobalIDForDeleteCacheByID() {

	req := &DeleteCacheByIDRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "",
		},
		CacheId: 1,
	}

	res, err := s.svc.DeleteCacheByID(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("repo id cannot be nil"))
}

func (s *deleteCachesTestSuite) TestServiceFailsWithBadRepositoryClientForDeleteCacheByID() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &DeleteCacheByIDRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		CacheId: 1,
	}

	res, err := s.svc.DeleteCacheByID(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *deleteCachesTestSuite) TestServiceFailsWithBadCredentialsForDeleteCacheByID() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("DeleteCacheByID", mock.Anything, int64(1)).Return(errs.New("error!"))

	req := &DeleteCacheByIDRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		CacheId: 1,
	}

	res, err := s.svc.DeleteCacheByID(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *deleteCachesTestSuite) TestServiceWillDeleteCacheForDeleteCachesByKeys() {
	caches := mockCaches()
	caches_to_delete := []*azp.CacheEntry{caches[0]}
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("DeleteCachesByKey", mock.Anything, mock.Anything, mock.Anything).Return(caches_to_delete, int64(1), nil)

	req := &DeleteCachesByKeyRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Key: "linux-node-key1",
	}

	res, err := s.svc.DeleteCachesByKey(context.TODO(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(mapCacheEntries(caches_to_delete), res.Caches)
}

func (s *deleteCachesTestSuite) TestServiceFailsWithInvalidGlobalIDForDeleteCachesByKeys() {
	req := &DeleteCachesByKeyRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "",
		},
		Key: "linux-node-key1",
	}

	res, err := s.svc.DeleteCachesByKey(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("repo id cannot be nil"))
}

func (s *deleteCachesTestSuite) TestServiceFailsWithBadRepositoryClientForDeleteCachesByKeys() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &DeleteCachesByKeyRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Key: "linux-node-key1",
	}

	res, err := s.svc.DeleteCachesByKey(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *deleteCachesTestSuite) TestServiceFailsWithBadCredentialsForDeleteCachesByKeys() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("DeleteCachesByKey", mock.Anything, mock.Anything, mock.Anything).Return(nil, int64(0), errs.New("error!"))

	req := &DeleteCachesByKeyRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Key: "linux-node-key1",
	}

	res, err := s.svc.DeleteCachesByKey(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}
