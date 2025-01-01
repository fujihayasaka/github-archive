package artifactcache

import (
	context "context"
	"testing"

	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type listCachesTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestListCachesTestSuite(t *testing.T) {
	suite.Run(t, new(listCachesTestSuite))
}

func (s *listCachesTestSuite) SetupTest() {
	s.rcf = &azp.MockRepositoryClientFactory{}
	s.arr = &deployer.MockAzpResourcesRepository{}
	s.rrc = &azp.MockRepositoryClient{}
	s.svc = &service{
		log:               logger.TestLogger(),
		stats:             statter.NullStatter(),
		repoClientFactory: s.rcf,
		// bearerTokenClientFactory: s.bcf,
		resourceRepo: s.arr,
	}
}

func (s *listCachesTestSuite) TestServiceWillReturnCachesList() {
	expectedCaches := mockCaches()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListCaches", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(expectedCaches, int64(len(expectedCaches)), nil)

	req := &ListCachesRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListCaches(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Caches, len(expectedCaches))
	s.Equal(mapCacheEntries(expectedCaches), res.Caches)
}

func (s *listCachesTestSuite) TestServiceFailsWithInvalidGlobalID() {

	req := &ListCachesRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "",
		},
	}

	res, err := s.svc.ListCaches(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("repo id cannot be nil"))
}

func (s *listCachesTestSuite) TestServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &ListCachesRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListCaches(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *listCachesTestSuite) TestServiceFailsWithBadCredentials() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListCaches", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, int64(0), errs.New("error!"))

	req := &ListCachesRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListCaches(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}
