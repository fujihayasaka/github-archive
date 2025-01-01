package e2e

import (
	"fmt"
	"regexp"
	"testing"
	"time"

	"github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/suite"
)

func TestImagesUploadingLinuxX64(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(ImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Linux
	s.Architecture = sharedapi.Architecture_X64
	s.ImageVhdName = "test-e2e-ubuntu-18-04-x64.vhd"
	s.ImageVersionsToUpload = 2

	suite.Run(t, s)
}

func TestImagesUploadingLinuxArm64(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(ImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Linux
	s.Architecture = sharedapi.Architecture_Arm64
	s.ImageVhdName = "test-e2e-ubuntu-18.04-arm64.vhd"
	s.ImageVersionsToUpload = 1

	suite.Run(t, s)
}

func TestImagesUploadingWindowsX64(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(ImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Windows
	s.Architecture = sharedapi.Architecture_X64
	s.ImageVhdName = "test-e2e-windows-server-2022-x64.vhd"
	s.ImageVersionsToUpload = 1

	suite.Run(t, s)
}

func TestImagesUploadingWindowsArm64(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(ImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Windows
	s.Architecture = sharedapi.Architecture_Arm64
	s.ImageVhdName = "test-e2e-windows-11-preview-arm64.vhd"
	s.ImageVersionsToUpload = 1

	suite.Run(t, s)
}

type ImagesUploadingE2ETestSuite struct {
	BaseE2ETestSuite
	OsType                sharedapi.OsType
	Architecture          sharedapi.Architecture
	ImageVhdName          string
	ImageVersionsToUpload int
}

func (s *ImagesUploadingE2ETestSuite) Test_ValidateImageUploading() {
	testCaseTitle := fmt.Sprintf("%v, %v", s.OsType, s.Architecture)

	s.T().Logf("[%s] GET source vhd url for: %s", testCaseTitle, s.ImageVhdName)

	sourceVhdUrl, err := utils.GenerateImageVhdUrl(s.ImageVhdName)
	s.Require().NoError(err)

	s.T().Logf("[%s] CREATE image definition", testCaseTitle)

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         fmt.Sprintf("%s-uploading-def-%d-%d", s.uniquePrefix, s.OsType, s.Architecture),
		OsType:       s.OsType,
		Architecture: s.Architecture,
		Enabled:      true,
	})
	s.Require().NoError(err)

	imageDefinition := createImageDefinitionResp.ImageDefinition

	s.T().Logf("[%s] CREATE image definition pointer", testCaseTitle)

	createImageDefinitionPointerResp, err := s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      fmt.Sprintf("%s-uploading-def-pointer-%d-%d", s.uniquePrefix, s.OsType, s.Architecture),
		Enabled:                   true,
		PointsToImageDefinitionId: imageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Logf("[%s] CREATE %d version(s) for image definition (id:name) (%d:%s)", testCaseTitle, s.ImageVersionsToUpload, imageDefinition.Id, imageDefinition.Name)

	queuedImageVersions := make([]*adminapi.ImageVersion, 0)

	latestUploadedVersion := ""

	for imageVersionIndex := 0; imageVersionIndex < s.ImageVersionsToUpload; imageVersionIndex++ {
		version := fmt.Sprintf("%d.0.0", imageVersionIndex+1)
		latestUploadedVersion = version

		createImageVersionResp, err := s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
			Version:           version,
			Enabled:           true,
			SourceVhdUrl:      sourceVhdUrl,
		})
		s.Require().NoError(err)

		s.Require().Equal(version, createImageVersionResp.ImageVersion.Version)
		s.Require().Contains([]sharedapi.ImageVersionState{sharedapi.ImageVersionState_Pending, sharedapi.ImageVersionState_Provisioning}, createImageVersionResp.ImageVersion.State)

		queuedImageVersions = append(queuedImageVersions, createImageVersionResp.ImageVersion)
	}

	s.T().Logf("[%s] WAIT for image versions provisioning", testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < s.ImageVersionsToUpload; imageVersionIndex++ {
		imageVersion := s.waitForImageVersionProvisioning(testCaseTitle, createImageDefinitionResp.ImageDefinition.Id, queuedImageVersions[imageVersionIndex].Version)
		s.T().Logf("[%s] Image uploading finished. Image state: %s (%s)", testCaseTitle, imageVersion.State, imageVersion.StateDetails)
		s.Assert().Greater(imageVersion.SizeGb, int32(10))
		s.Require().Equal(sharedapi.ImageVersionState_Ready, imageVersion.State)
	}

	s.T().Logf("[%s] GET image definition using Customers API", testCaseTitle)

	getImageDefinitionResp, err := s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "test"},
		ImageDefinitionId: imageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(latestUploadedVersion, getImageDefinitionResp.ImageDefinition.LatestVersion)

	s.T().Logf("[%s] VALIDATE internal API for image definition", testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < s.ImageVersionsToUpload; imageVersionIndex++ {
		s.T().Logf("[%s] VALIDATE internal API for image version '%s'", testCaseTitle, queuedImageVersions[imageVersionIndex].Version)

		s.validateInternalApiRequests(
			testCaseTitle,
			&internalapi.ImageKey{
				Source:  "Curated",
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
		&internalapi.ImageKey{
			Source:  "Curated",
			Id:      imageDefinition.Id,
			Version: "latest",
		},
		imageDefinition,
		fmt.Sprintf("%d.0.0", s.ImageVersionsToUpload),
	)

	s.T().Logf("[%s] VALIDATE internal API for image definition pointer", testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < s.ImageVersionsToUpload; imageVersionIndex++ {
		s.T().Logf("[%s] VALIDATE internal API for image version '%s' using image definition pointer", testCaseTitle, queuedImageVersions[imageVersionIndex].Version)

		s.validateInternalApiRequests(
			testCaseTitle,
			&internalapi.ImageKey{
				Source:  "Curated",
				Id:      createImageDefinitionPointerResp.ImageDefinition.Id,
				Version: queuedImageVersions[imageVersionIndex].Version,
			},
			createImageDefinitionPointerResp.ImageDefinition,
			fmt.Sprintf("%d.0.0", imageVersionIndex+1),
		)
	}

	s.T().Logf("[%s] VALIDATE internal API for image version 'latest' using image definition pointer", testCaseTitle)

	s.validateInternalApiRequests(
		testCaseTitle,
		&internalapi.ImageKey{
			Source:  "Curated",
			Id:      createImageDefinitionPointerResp.ImageDefinition.Id,
			Version: "latest",
		},
		createImageDefinitionPointerResp.ImageDefinition,
		fmt.Sprintf("%d.0.0", s.ImageVersionsToUpload),
	)

	s.T().Logf("[%s] DELETE image versions", testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < s.ImageVersionsToUpload; imageVersionIndex++ {
		_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
			Version:           queuedImageVersions[imageVersionIndex].Version,
		})
		s.Require().NoError(err)
	}

	for imageVersionIndex := 0; imageVersionIndex < s.ImageVersionsToUpload; imageVersionIndex++ {
		s.waitForAdminImageVersionDeletion(createImageDefinitionResp.ImageDefinition.Id, queuedImageVersions[imageVersionIndex].Version)
	}

	s.T().Logf("[%s] DELETE image definition pointer", testCaseTitle)
	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: createImageDefinitionPointerResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Logf("[%s] DELETE image definition", testCaseTitle)

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
}

func (s *ImagesUploadingE2ETestSuite) waitForImageVersionProvisioning(testCaseTitle string, imageDefinitionId uint64, version string) *adminapi.ImageVersion {
	getImageVersionRequest := &adminapi.GetCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinitionId,
		Version:           version,
	}

	imageVersionResponse, err := s.adminTwirpClient.GetCuratedImageVersion(s.ctx, getImageVersionRequest)
	s.Require().NoError(err)

	for imageVersionResponse.ImageVersion.State != sharedapi.ImageVersionState_Ready && imageVersionResponse.ImageVersion.State != sharedapi.ImageVersionState_ProvisionFailed {
		s.T().Logf("[%s] Waiting for image uploading...", testCaseTitle)
		s.T().Logf("[%s] Current state is %s (%s)", testCaseTitle, imageVersionResponse.ImageVersion.State, imageVersionResponse.ImageVersion.StateDetails)
		time.Sleep(10 * time.Second)

		imageVersionResponse, err = s.adminTwirpClient.GetCuratedImageVersion(s.ctx, getImageVersionRequest)
		s.Require().NoError(err)
	}

	return imageVersionResponse.ImageVersion
}

func (s *ImagesUploadingE2ETestSuite) validateInternalApiRequests(testCaseTitle string, imageKey *internalapi.ImageKey, expectedImageDefinition *admin_api.ImageDefinition, expectedImageVersion string) {
	s.T().Logf("[%s] GET image reference for key {%v}", testCaseTitle, imageKey)

	imageReferenceResp, err := s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{ImageKey: imageKey})
	s.Require().NoError(err)
	s.Require().Equal(expectedImageVersion, imageReferenceResp.ExactImageVersion)
	s.Require().Regexp(regexp.MustCompile(`Microsoft\.Compute\/galleries\/\w+/images/[\w-]+\/versions\/\d+\.\d+\.\d+`), imageReferenceResp.ImageReference.Id)
	s.Require().Contains(imageReferenceResp.ImageReference.Id, fmt.Sprintf("/versions/%s", expectedImageVersion))

	s.T().Logf("[%s] GET image details for key {%v}", testCaseTitle, imageKey)
	imageDetailsResp, err := s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    &sharedapi.Actor{GlobalId: "test"},
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
	s.Require().Greater(imageDetailsResp.ImageDetails.SizeGb, int32(0))
}
