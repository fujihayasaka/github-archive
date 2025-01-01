package e2e

import (
	"strings"
	"time"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
)

func (s *BaseE2ETestSuite) waitForAdminImageVersionProvisionFailed(imageDefinitionId uint64, version string) *adminapi.ImageVersion {
	getImageVersionReq := &adminapi.GetCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinitionId,
		Version:           version,
	}

	getImageVersionResp, err := s.adminTwirpClient.GetCuratedImageVersion(s.ctx, getImageVersionReq)
	s.Require().NoError(err)

	for getImageVersionResp.ImageVersion.State != sharedapi.ImageVersionState_ProvisionFailed {
		s.T().Logf("Waiting for image version state to be ProvisionFailed. The current state: %s", getImageVersionResp.ImageVersion.State)
		time.Sleep(10 * time.Second)

		getImageVersionResp, err = s.adminTwirpClient.GetCuratedImageVersion(s.ctx, getImageVersionReq)
		s.Require().NoError(err)
	}

	return getImageVersionResp.ImageVersion
}

func (s *BaseE2ETestSuite) waitForCustomerImageVersionProvisionFailed(imageOwner *sharedapi.Actor, imageDefinitionId uint64, version string) *imagesapi.ImageVersion {
	getImageVersionReq := &imagesapi.GetCustomerImageVersionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: imageDefinitionId,
		Version:           version,
	}

	getImageVersionResp, err := s.customerTwirpClient.GetCustomerImageVersion(s.ctx, getImageVersionReq)
	s.Require().NoError(err)

	for getImageVersionResp.ImageVersion.State != sharedapi.ImageVersionState_ProvisionFailed {
		s.T().Logf("Waiting for image version state to be ProvisionFailed. The current state: %s", getImageVersionResp.ImageVersion.State)
		time.Sleep(10 * time.Second)

		getImageVersionResp, err = s.customerTwirpClient.GetCustomerImageVersion(s.ctx, getImageVersionReq)
		s.Require().NoError(err)
	}

	return getImageVersionResp.ImageVersion
}

func (s *BaseE2ETestSuite) waitForAdminImageVersionDeletion(imageDefinitionId uint64, version string) {
	getImageVersionRequest := &adminapi.GetCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinitionId,
		Version:           version,
	}

	getImageVersionResponse, err := s.adminTwirpClient.GetCuratedImageVersion(s.ctx, getImageVersionRequest)

	for err == nil {
		s.Assert().Equal(sharedapi.ImageVersionState_Deleting, getImageVersionResponse.ImageVersion.State)

		s.T().Logf("Waiting for image version %s to be fully deleted", version)

		time.Sleep(10 * time.Second)

		getImageVersionResponse, err = s.adminTwirpClient.GetCuratedImageVersion(s.ctx, getImageVersionRequest)
	}

	s.Assert().ErrorContains(err, "twirp error not_found:")
}

func (s *BaseE2ETestSuite) waitForCustomerImageVersionDeletion(imageOwner *sharedapi.Actor, imageDefinitionId uint64, version string) {
	getImageVersionRequest := &imagesapi.GetCustomerImageVersionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: imageDefinitionId,
		Version:           version,
	}

	getImageVersionResponse, err := s.customerTwirpClient.GetCustomerImageVersion(s.ctx, getImageVersionRequest)

	for err == nil {
		s.Assert().Equal(sharedapi.ImageVersionState_Deleting, getImageVersionResponse.ImageVersion.State)

		s.T().Logf("Waiting for image version %s to be fully deleted", version)

		time.Sleep(10 * time.Second)

		getImageVersionResponse, err = s.customerTwirpClient.GetCustomerImageVersion(s.ctx, getImageVersionRequest)
	}

	s.Assert().ErrorContains(err, "twirp error not_found:")
}

func (s *BaseE2ETestSuite) filterTestCuratedImageDefinitions(list []*adminapi.ImageDefinition) []*adminapi.ImageDefinition {
	result := make([]*adminapi.ImageDefinition, 0)
	for _, def := range list {
		if strings.HasPrefix(def.Name, s.uniquePrefix) {
			result = append(result, def)
		}
	}

	return result
}

func (s *BaseE2ETestSuite) filterTestCustomerImageDefinitions(list []*imagesapi.ImageDefinition) []*imagesapi.ImageDefinition {
	result := make([]*imagesapi.ImageDefinition, 0)
	for _, def := range list {
		if strings.HasPrefix(def.Name, s.uniquePrefix) {
			result = append(result, def)
		}
	}

	return result
}
