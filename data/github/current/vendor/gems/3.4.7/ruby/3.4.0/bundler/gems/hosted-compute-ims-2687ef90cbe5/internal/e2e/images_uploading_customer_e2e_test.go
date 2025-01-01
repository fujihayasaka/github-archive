package e2e

import (
	"fmt"
	"regexp"
	"testing"

	"github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/suite"
)

type CustomerImagesUploadingE2ETestSuite struct {
	BaseE2ETestSuite
	OsType                sharedapi.OsType
	Architecture          sharedapi.Architecture
	ImageVhdName          string
	ImageVersionsToUpload int32
	ExpectedImageSizeGB   int32
	testCaseTitle         string
}

func (s *CustomerImagesUploadingE2ETestSuite) SetupSuite() {
	s.BaseE2ETestSuite.SetupSuite()
	s.testCaseTitle = fmt.Sprintf("Customer %v, %v", s.OsType, s.Architecture)
}

func TestCustomerImagesUploadingLinuxX64(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(CustomerImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Linux
	s.Architecture = sharedapi.Architecture_X64
	s.ImageVhdName = "test-e2e-ubuntu-18-04-x64.vhd"
	s.ImageVersionsToUpload = 2
	s.ExpectedImageSizeGB = 30

	suite.Run(t, s)
}

func (s *CustomerImagesUploadingE2ETestSuite) Test_ValidateCustomerImageUploading() {
	owner := &sharedapi.Actor{GlobalId: fmt.Sprintf("O_%s_e2e_image_uploading", s.uniquePrefix)}

	s.T().Logf("[%s] GET source vhd url for: %s", s.testCaseTitle, s.ImageVhdName)

	sourceVhdUrl, err := utils.GenerateImageVhdUrl(s.ImageVhdName)
	s.Require().NoError(err)

	s.T().Logf("[%s] CREATE image definition", s.testCaseTitle)

	createImageDefinitionResp, err := s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:        owner,
		Name:         fmt.Sprintf("%s-uploading-def-%d-%d", s.uniquePrefix, s.OsType, s.Architecture),
		OsType:       s.OsType,
		Architecture: s.Architecture,
	})
	s.Require().NoError(err)

	imageDefinition := createImageDefinitionResp.ImageDefinition

	queuedImageVersions := make([]*imagesapi.ImageVersion, 0)

	latestUploadedVersion := ""

	for imageVersionIndex := 0; imageVersionIndex < int(s.ImageVersionsToUpload); imageVersionIndex++ {
		version := fmt.Sprintf("%d.0.0", imageVersionIndex+1)
		latestUploadedVersion = version

		createImageVersionResp, err := s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{
			Owner:             owner,
			ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
			Version:           version,
			SourceVhdUrl:      sourceVhdUrl,
		})
		s.Require().NoError(err)

		s.Require().Equal(version, createImageVersionResp.ImageVersion.Version)
		s.Require().Contains([]sharedapi.ImageVersionState{sharedapi.ImageVersionState_Pending, sharedapi.ImageVersionState_Provisioning}, createImageVersionResp.ImageVersion.State)

		queuedImageVersions = append(queuedImageVersions, createImageVersionResp.ImageVersion)
	}

	s.T().Logf("[%s] WAIT for image versions provisioning", s.testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < int(s.ImageVersionsToUpload); imageVersionIndex++ {
		imageVersion := s.waitForCustomerImageVersionProvisioning(s.testCaseTitle, owner, createImageDefinitionResp.ImageDefinition.Id, queuedImageVersions[imageVersionIndex].Version)
		s.T().Logf("[%s] Image uploading finished. Image state: %s (%s)", s.testCaseTitle, imageVersion.State, imageVersion.StateDetails)
		s.Assert().Equal(imageVersion.SizeGb, s.ExpectedImageSizeGB)
		s.Require().Equal(sharedapi.ImageVersionState_Ready, imageVersion.State)
	}

	s.T().Logf("[%s] GET image definition using Customers API", s.testCaseTitle)

	getImageDefinitionResp, err := s.customerTwirpClient.GetCustomerImageDefinition(s.ctx, &imagesapi.GetCustomerImageDefinitionRequest{
		Owner:             owner,
		ImageDefinitionId: imageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(imageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(imageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(s.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(s.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(latestUploadedVersion, getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(s.ImageVersionsToUpload, getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(s.ExpectedImageSizeGB, getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(s.ExpectedImageSizeGB*s.ImageVersionsToUpload, getImageDefinitionResp.ImageDefinition.TotalImageVersionsSizeGb)

	s.T().Logf("[%s] LIST image definition using Customers API", s.testCaseTitle)

	listImageDefinitionResp, err := s.customerTwirpClient.ListCustomerImageDefinitions(s.ctx, &imagesapi.ListCustomerImageDefinitionsRequest{
		Owner: owner,
	})
	s.Require().NoError(err)
	s.Require().Equal(1, len(listImageDefinitionResp.ImageDefinitions))
	s.Require().Equal(imageDefinition.Id, listImageDefinitionResp.ImageDefinitions[0].Id)
	s.Require().Equal(imageDefinition.Name, listImageDefinitionResp.ImageDefinitions[0].Name)
	s.Require().Equal(s.OsType, listImageDefinitionResp.ImageDefinitions[0].OsType)
	s.Require().Equal(s.Architecture, listImageDefinitionResp.ImageDefinitions[0].Architecture)
	s.Require().Equal(latestUploadedVersion, listImageDefinitionResp.ImageDefinitions[0].LatestVersion)
	s.Require().Equal(s.ImageVersionsToUpload, listImageDefinitionResp.ImageDefinitions[0].ImageVersionsCount)
	s.Require().Equal(s.ExpectedImageSizeGB, listImageDefinitionResp.ImageDefinitions[0].LatestVersionSizeGb)
	s.Require().Equal(s.ExpectedImageSizeGB*s.ImageVersionsToUpload, listImageDefinitionResp.ImageDefinitions[0].TotalImageVersionsSizeGb)

	for imageVersionIndex := 0; imageVersionIndex < int(s.ImageVersionsToUpload); imageVersionIndex++ {
		s.T().Logf("[%s] VALIDATE internal API for image version '%s'", s.testCaseTitle, queuedImageVersions[imageVersionIndex].Version)

		s.validateInternalApiRequests(
			owner,
			"Customer",
			imageDefinition.Id,
			queuedImageVersions[imageVersionIndex].Version,
			imageDefinition,
			fmt.Sprintf("%d.0.0", imageVersionIndex+1),
		)
	}

	s.T().Logf("[%s] VALIDATE internal API for image version 'latest'", s.testCaseTitle)

	s.validateInternalApiRequests(
		owner,
		"Customer",
		imageDefinition.Id,
		"latest",
		imageDefinition,
		fmt.Sprintf("%d.0.0", s.ImageVersionsToUpload),
	)

	s.T().Logf("[%s] DELETE image definition and automatically delete the versions under it", s.testCaseTitle)

	_, err = s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             owner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
}

func (s *CustomerImagesUploadingE2ETestSuite) validateInternalApiRequests(owner *sharedapi.Actor, imageSource string, imageId uint64, imageVersion string, expectedImageDefinition *images_api.ImageDefinition, expectedImageVersion string) {
	s.T().Logf("[%s] GET image reference for key {%s, %d, %s}", s.testCaseTitle, imageSource, imageId, imageVersion)

	imageReferenceResp, err := s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  imageSource,
		ImageId:      imageId,
		ImageVersion: imageVersion,
	})
	s.Require().NoError(err)
	s.Require().Equal(expectedImageVersion, imageReferenceResp.ImageReference.ExactImageVersion)
	s.Require().Regexp(regexp.MustCompile(`Microsoft\.Compute\/galleries\/[\w.]+/images/[\w-]+\/versions\/\d+\.\d+\.\d+`), imageReferenceResp.ImageReference.ResourceId)
	s.Require().Contains(imageReferenceResp.ImageReference.ResourceId, fmt.Sprintf("/versions/%s", expectedImageVersion))
	// check backward compatibility
	s.Require().Equal(expectedImageVersion, imageReferenceResp.ExactImageVersion)                                                                         //nolint:staticcheck
	s.Require().Regexp(regexp.MustCompile(`Microsoft\.Compute\/galleries\/[\w.]+/images/[\w-]+\/versions\/\d+\.\d+\.\d+`), imageReferenceResp.ResourceId) //nolint:staticcheck
	s.Require().Contains(imageReferenceResp.ResourceId, fmt.Sprintf("/versions/%s", expectedImageVersion))                                                //nolint:staticcheck

	s.T().Logf("[%s] GET image details for key {%s, %d, %s}", s.testCaseTitle, imageSource, imageId, imageVersion)
	imageDetailsResp, err := s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        owner,
		ImageSource:  imageSource,
		ImageId:      imageId,
		ImageVersion: imageVersion,
	})
	s.Require().NoError(err)
	s.Require().NotNil(imageDetailsResp)
	s.Require().NotNil(imageDetailsResp.ImageDetails)

	s.Require().Equal(expectedImageDefinition.Id, imageDetailsResp.ImageDetails.Id)
	s.Require().Equal(imageSource, imageDetailsResp.ImageDetails.Source)
	s.Require().Equal(expectedImageDefinition.Name, imageDetailsResp.ImageDetails.Name)
	s.Require().Equal(expectedImageDefinition.OsType, imageDetailsResp.ImageDetails.OsType)
	s.Require().Equal(expectedImageDefinition.Architecture, imageDetailsResp.ImageDetails.Architecture)
	s.Require().Equal(expectedImageDefinition.Enabled, imageDetailsResp.ImageDetails.Enabled)
	s.Require().Equal(s.ExpectedImageSizeGB, imageDetailsResp.ImageDetails.SizeGb)
}
