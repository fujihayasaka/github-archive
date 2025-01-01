package selfhostedrunners

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

type listLabelsTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestListLabelsTestSuite(t *testing.T) {
	suite.Run(t, new(listLabelsTestSuite))
}

func (s *listLabelsTestSuite) SetupTest() {
	s.rcf = &azp.MockRepositoryClientFactory{}
	s.arr = &deployer.MockAzpResourcesRepository{}
	s.rrc = &azp.MockRepositoryClient{}
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: s.rcf,
		azpResourceRepo:      s.arr,
	}
}

func (s *listLabelsTestSuite) TestServiceWillReturnLabelsList() {
	expectedLabels := s.getMockLabels()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListLabels", mock.Anything).Return(expectedLabels, nil)

	req := &ListLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListLabels(context.TODO(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Labels, len(expectedLabels))
	s.Equal(expectedLabels, s.asAzpLabels(res.Labels))
}

func (s *listLabelsTestSuite) TestServiceFailsWithInvalidGlobalID() {

	req := &ListLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
	}

	res, err := s.svc.ListLabels(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *listLabelsTestSuite) TestServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &ListLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListLabels(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *listLabelsTestSuite) TestServiceFailsWithBadCredentials() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListLabels", mock.Anything).Return(nil, errs.New("error!"))

	req := &ListLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListLabels(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *listLabelsTestSuite) getMockLabels() []*azp.Label {
	return []*azp.Label{
		{
			ID:   1,
			Name: "macOS",
			Type: "system",
		},
		{
			ID:   2,
			Name: "some label!",
			Type: "user",
		},
	}
}

func (s *listLabelsTestSuite) asAzpLabels(ls []*Label) []*azp.Label {
	var azpLs []*azp.Label
	for _, l := range ls {
		azpl := &azp.Label{
			ID:   l.Id,
			Name: l.Name,
			Type: l.Type,
		}
		azpLs = append(azpLs, azpl)
	}
	return azpLs
}
