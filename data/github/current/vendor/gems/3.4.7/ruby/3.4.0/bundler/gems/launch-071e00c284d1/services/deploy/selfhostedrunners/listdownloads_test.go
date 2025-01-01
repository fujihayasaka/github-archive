package selfhostedrunners

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

type listDownloadsTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestListDownloadsTestSuite(t *testing.T) {
	suite.Run(t, new(listDownloadsTestSuite))
}

func (s *listDownloadsTestSuite) SetupTest() {
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

func (s *listDownloadsTestSuite) Test_ServiceWillReturnDownloadsList() {
	downloads := s.getMockDownloads()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListDownloads", mock.Anything).Return(downloads, nil)

	req := &ListDownloadsRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListDownloads(context.TODO(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Downloads, len(downloads))
	s.Equal(s.asDownloads(downloads), res.Downloads)
}

func (s *listDownloadsTestSuite) Test_ServiceWillReturnAirGappedDownloadsList() {
	downloads := s.getMockAirGapDownloads()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListDownloads", mock.Anything).Return(downloads, nil)

	req := &ListDownloadsRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListDownloads(context.TODO(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Downloads, len(downloads))
	s.Equal(s.asDownloads(downloads), res.Downloads)
}

func (s *listDownloadsTestSuite) Test_ServiceFailsWithInvalidGlobalID() {

	req := &ListDownloadsRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "",
		},
	}

	res, err := s.svc.ListDownloads(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("repository id cannot be nil"))
}

func (s *listDownloadsTestSuite) Test_ServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &ListDownloadsRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListDownloads(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *listDownloadsTestSuite) Test_ServiceFailsWithBadCredentials() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListDownloads", mock.Anything).Return(nil, errs.New("error!"))

	req := &ListDownloadsRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListDownloads(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *listDownloadsTestSuite) getMockDownloads() []*azp.Download {
	return []*azp.Download{
		{
			Type:     "agent",
			Platform: "osx-x64",
			Version: azp.Version{
				Major: 2,
				Minor: 159,
				Patch: 0,
			},
			DownloadURL: "https://githubassets.com/mac.tar.gz",
			Filename:    "mac.tar.gz",
		},
		{
			Type:     "agent",
			Platform: "linux-x64",
			Version: azp.Version{
				Major: 2,
				Minor: 159,
				Patch: 1,
			},
			DownloadURL: "https://githubassets.com/linux.tar.gz",
			Filename:    "linux.tar.gz",
		},
		{
			Type:     "agent",
			Platform: "win-x64",
			Version: azp.Version{
				Major: 2,
				Minor: 159,
				Patch: 3,
			},
			DownloadURL: "https://githubassets.com/win.tar.gz",
			Filename:    "win.tar.gz",
		},
	}
}

func (s *listDownloadsTestSuite) getMockAirGapDownloads() []*azp.Download {
	return []*azp.Download{
		{
			Type:     "agent",
			Platform: "osx-x64",
			Version: azp.Version{
				Major: 2,
				Minor: 159,
				Patch: 0,
			},
			DownloadURL:   "https://githubassets.com/mac.tar.gz",
			Filename:      "mac.tar.gz",
			Sha256Hash:    "7215c75a462eeb6a839fa8ed298d79f620617d44d47d37c583114fc3f3b27b30",
			DownloadToken: "token_osx",
		},
		{
			Type:     "agent",
			Platform: "linux-x64",
			Version: azp.Version{
				Major: 2,
				Minor: 159,
				Patch: 1,
			},
			DownloadURL:   "https://githubassets.com/linux.tar.gz",
			Filename:      "linux.tar.gz",
			Sha256Hash:    "f1fa173889dc9036cd529417e652e1729e5a3f4d35ec0151806d7480fda6b89b",
			DownloadToken: "token_linux",
		},
		{
			Type:     "agent",
			Platform: "win-x64",
			Version: azp.Version{
				Major: 2,
				Minor: 159,
				Patch: 3,
			},
			DownloadURL:   "https://githubassets.com/win.tar.gz",
			Filename:      "win.tar.gz",
			Sha256Hash:    "02d710fc9e0008e641274bb7da7fde61f7c9aa1cbb541a2990d3450cc88f4e98",
			DownloadToken: "token_win",
		},
	}
}

func (s *listDownloadsTestSuite) asDownloads(ds []*azp.Download) []*Download {
	var out []*Download
	for _, d := range ds {
		os, _ := d.GetOS()
		arch, _ := d.GetArchitecture()
		azpd := &Download{
			Type:          d.Type,
			Platform:      d.Platform,
			Version:       d.Version.String(),
			DownloadUrl:   d.DownloadURL,
			Filename:      d.Filename,
			Os:            os,
			Architecture:  arch,
			DownloadToken: d.DownloadToken,
			Sha256Hash:    d.Sha256Hash,
		}
		out = append(out, azpd)
	}
	return out
}
