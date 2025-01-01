package e2e

import (
	"fmt"
	"regexp"
	"testing"
	"time"

	"github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/suite"
)

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

type CustomerImagesUploadingE2ETestSuite struct {
	BaseE2ETestSuite
	OsType                sharedapi.OsType
	Architecture          sharedapi.Architecture
	ImageVhdName          string
	ImageVersionsToUpload int32
	ExpectedImageSizeGB   int32
}

func (s *CustomerImagesUploadingE2ETestSuite) Test_ValidateCustomerImageUploading() {
	testCaseTitle := fmt.Sprintf("Customer %v, %v", s.OsType, s.Architecture)
	owner := &sharedapi.Actor{GlobalId: fmt.Sprintf("O_%s_e2e_uploading", s.uniquePrefix)}

	s.T().Logf("[%s] GET source vhd url for: %s", testCaseTitle, s.ImageVhdName)

	sourceVhdUrl, err := utils.GenerateImageVhdUrl(s.ImageVhdName)
	s.Require().NoError(err)

	s.T().Logf("[%s] CREATE image definition", testCaseTitle)

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

	s.T().Logf("[%s] WAIT for image versions provisioning", testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < int(s.ImageVersionsToUpload); imageVersionIndex++ {
		imageVersion := s.waitForImageVersionProvisioning(testCaseTitle, owner, createImageDefinitionResp.ImageDefinition.Id, queuedImageVersions[imageVersionIndex].Version)
		s.T().Logf("[%s] Image uploading finished. Image state: %s (%s)", testCaseTitle, imageVersion.State, imageVersion.StateDetails)
		s.Assert().Equal(imageVersion.SizeGb, s.ExpectedImageSizeGB)
		s.Require().Equal(sharedapi.ImageVersionState_Ready, imageVersion.State)
	}

	s.T().Logf("[%s] GET image definition using Customers API", testCaseTitle)

	getImageDefinitionResp, err := s.customerTwirpClient.GetCustomerImageDefinition(s.ctx, &imagesapi.GetCustomerImageDefinitionRequest{
		Owner:             owner,
		ImageDefinitionId: imageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(latestUploadedVersion, getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(s.ImageVersionsToUpload, getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(s.ExpectedImageSizeGB, getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(s.ExpectedImageSizeGB*s.ImageVersionsToUpload, getImageDefinitionResp.ImageDefinition.TotalImageVersionsSizeGb)

	for imageVersionIndex := 0; imageVersionIndex < int(s.ImageVersionsToUpload); imageVersionIndex++ {
		s.T().Logf("[%s] VALIDATE internal API for image version '%s'", testCaseTitle, queuedImageVersions[imageVersionIndex].Version)

		s.validateInternalApiRequests(
			testCaseTitle,
			owner,
			&internalapi.ImageKey{
				Source:  "Customer",
				Id:      imageDefinition.Id,
				Version: queuedImageVersions[imageVersionIndex].Version,
			},
			imageDefinition,
			fmt.Sprintf("%d.0.0", imageVersionIndex+1),
		)
	}

	s.T().Logf("[%s] VALIDATE internal API for image version 'latest'", testCaseTitle)

	s.validateInternalApiRequests(
		testCaseTitle,
		owner,
		&internalapi.ImageKey{
			Source:  "Customer",
			Id:      imageDefinition.Id,
			Version: "latest",
		},
		imageDefinition,
		fmt.Sprintf("%d.0.0", s.ImageVersionsToUpload),
	)

	s.T().Logf("[%s] DELETE image versions", testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < int(s.ImageVersionsToUpload); imageVersionIndex++ {
		_, err = s.customerTwirpClient.DeleteCustomerImageVersion(s.ctx, &imagesapi.DeleteCustomerImageVersionRequest{
			Owner:             owner,
			ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
			Version:           queuedImageVersions[imageVersionIndex].Version,
		})
		s.Require().NoError(err)
	}

	for imageVersionIndex := 0; imageVersionIndex < int(s.ImageVersionsToUpload); imageVersionIndex++ {
		s.waitForCustomerImageVersionDeletion(owner, createImageDefinitionResp.ImageDefinition.Id, queuedImageVersions[imageVersionIndex].Version)
	}

	s.T().Logf("[%s] DELETE image definition", testCaseTitle)

	_, err = s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             owner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
}

func (s *CustomerImagesUploadingE2ETestSuite) waitForImageVersionProvisioning(testCaseTitle string, owner *sharedapi.Actor, imageDefinitionId uint64, version string) *imagesapi.ImageVersion {
	getImageVersionRequest := &imagesapi.GetCustomerImageVersionRequest{
		Owner:             owner,
		ImageDefinitionId: imageDefinitionId,
		Version:           version,
	}

	imageVersionResponse, err := s.customerTwirpClient.GetCustomerImageVersion(s.ctx, getImageVersionRequest)
	s.Require().NoError(err)

	for imageVersionResponse.ImageVersion.State != sharedapi.ImageVersionState_Ready && imageVersionResponse.ImageVersion.State != sharedapi.ImageVersionState_ProvisionFailed {
		s.T().Logf("[%s] Waiting for image uploading...", testCaseTitle)
		s.T().Logf("[%s] Current state is %s (%s)", testCaseTitle, imageVersionResponse.ImageVersion.State, imageVersionResponse.ImageVersion.StateDetails)
		time.Sleep(10 * time.Second)

		imageVersionResponse, err = s.customerTwirpClient.GetCustomerImageVersion(s.ctx, getImageVersionRequest)
		s.Require().NoError(err)
	}

	return imageVersionResponse.ImageVersion
}

func (s *CustomerImagesUploadingE2ETestSuite) validateInternalApiRequests(testCaseTitle string, owner *sharedapi.Actor, imageKey *internalapi.ImageKey, expectedImageDefinition *images_api.ImageDefinition, expectedImageVersion string) {
	s.T().Logf("[%s] GET image reference for key {%v}", testCaseTitle, imageKey)

	imageReferenceResp, err := s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{ImageKey: imageKey})
	s.Require().NoError(err)
	s.Require().Equal(expectedImageVersion, imageReferenceResp.ExactImageVersion)
	s.Require().Regexp(regexp.MustCompile(`Microsoft\.Compute\/galleries\/\w+/images/[\w-]+\/versions\/\d+\.\d+\.\d+`), imageReferenceResp.ImageReference.Id)
	s.Require().Contains(imageReferenceResp.ImageReference.Id, fmt.Sprintf("/versions/%s", expectedImageVersion))

	s.T().Logf("[%s] GET image details for key {%v}", testCaseTitle, imageKey)
	imageDetailsResp, err := s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    owner,
		ImageKey: imageKey,
	})
	s.Require().NoError(err)
	s.Require().NotNil(imageDetailsResp)
	s.Require().NotNil(imageDetailsResp.ImageDetails)

	s.Require().Equal(expectedImageDefinition.Id, imageDetailsResp.ImageDetails.Id)
	s.Require().Equal(imageKey.Source, imageDetailsResp.ImageDetails.Source)
	s.Require().Equal(expectedImageDefinition.Name, imageDetailsResp.ImageDetails.Name)
	s.Require().Equal(expectedImageDefinition.OsType, imageDetailsResp.ImageDetails.OsType)
	s.Require().Equal(expectedImageDefinition.Architecture, imageDetailsResp.ImageDetails.Architecture)
	s.Require().Equal(expectedImageDefinition.Enabled, imageDetailsResp.ImageDetails.Enabled)
	s.Require().Equal(s.ExpectedImageSizeGB, imageDetailsResp.ImageDetails.SizeGb)
}
