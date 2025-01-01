package e2e

import (
	"fmt"
	"regexp"
	"testing"

	"github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/suite"
)

type CuratedImagesUploadingE2ETestSuite struct {
	BaseE2ETestSuite
	OsType                sharedapi.OsType
	Architecture          sharedapi.Architecture
	VMGeneration          sharedapi.VmGeneration
	OsState               sharedapi.OsState
	AzurePurchasePlan     string
	AgentUser             string
	OwnerId               string
	ImageVhdName          string
	ImageVersionsToUpload int
	testCaseTitle         string
}

func (s *CuratedImagesUploadingE2ETestSuite) SetupSuite() {
	s.BaseE2ETestSuite.SetupSuite()

	s.testCaseTitle = fmt.Sprintf("Curated %v, %v, %v, %v", s.OsType, s.Architecture, s.VMGeneration, s.OsState)
	if s.AzurePurchasePlan != "" {
		s.testCaseTitle += ", AzurePurchasePlan"
	}
	if s.AgentUser != "" {
		s.testCaseTitle += ", AgentUser"
	}
}

func TestCuratedImagesUploadingLinuxX64(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(CuratedImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Linux
	s.Architecture = sharedapi.Architecture_X64
	s.VMGeneration = sharedapi.VmGeneration_Gen1
	s.OsState = sharedapi.OsState_Generalized
	s.OwnerId = models.GithubOwnerId
	s.ImageVhdName = "test-e2e-ubuntu-18-04-x64.vhd"
	s.ImageVersionsToUpload = 2

	suite.Run(t, s)
}

func TestCuratedImagesUploadingLinuxArm64(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(CuratedImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Linux
	s.Architecture = sharedapi.Architecture_Arm64
	s.VMGeneration = sharedapi.VmGeneration_Gen1
	s.OsState = sharedapi.OsState_Generalized
	s.OwnerId = models.PartnerOwnerId
	s.ImageVhdName = "test-e2e-ubuntu-18.04-arm64.vhd"
	s.ImageVersionsToUpload = 1

	suite.Run(t, s)
}

func TestCuratedImagesUploadingWindowsX64(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(CuratedImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Windows
	s.Architecture = sharedapi.Architecture_X64
	s.VMGeneration = sharedapi.VmGeneration_Gen1
	s.OsState = sharedapi.OsState_Generalized
	s.OwnerId = models.PartnerOwnerId
	s.ImageVhdName = "test-e2e-windows-server-2022-x64.vhd"
	s.ImageVersionsToUpload = 1

	suite.Run(t, s)
}

func TestCuratedImagesUploadingWindowsArm64(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(CuratedImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Windows
	s.Architecture = sharedapi.Architecture_Arm64
	s.VMGeneration = sharedapi.VmGeneration_Gen1
	s.OsState = sharedapi.OsState_Generalized
	s.OwnerId = models.GithubOwnerId
	s.ImageVhdName = "test-e2e-windows-11-preview-arm64.vhd"
	s.ImageVersionsToUpload = 1

	suite.Run(t, s)
}

func TestCuratedImagesUploadingWithSpecializedImage(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(CuratedImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Linux
	s.Architecture = sharedapi.Architecture_X64
	s.VMGeneration = sharedapi.VmGeneration_Gen1
	s.OsState = sharedapi.OsState_Specialized
	s.OwnerId = models.GithubOwnerId
	s.ImageVhdName = "test-e2e-ubuntu-18-04-x64.vhd"
	s.ImageVersionsToUpload = 1

	suite.Run(t, s)
}

func TestCuratedImagesUploadingWithGen2Image(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(CuratedImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Linux
	s.Architecture = sharedapi.Architecture_X64
	s.VMGeneration = sharedapi.VmGeneration_Gen2
	s.OsState = sharedapi.OsState_Generalized
	s.OwnerId = models.GithubOwnerId
	s.ImageVhdName = "test-e2e-ubuntu-18-04-x64.vhd"
	s.ImageVersionsToUpload = 1

	suite.Run(t, s)
}

func TestCuratedImagesUploadingWithAzurePlanAndAgentUser(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()

	s := new(CuratedImagesUploadingE2ETestSuite)
	s.OsType = sharedapi.OsType_Linux
	s.Architecture = sharedapi.Architecture_X64
	s.VMGeneration = sharedapi.VmGeneration_Gen1
	s.OsState = sharedapi.OsState_Generalized
	s.AzurePurchasePlan = "arm:github_arm:gh-plan"
	s.AgentUser = "root"
	s.OwnerId = models.GithubOwnerId
	s.ImageVhdName = "test-e2e-ubuntu-18-04-x64.vhd"
	s.ImageVersionsToUpload = 1

	suite.Run(t, s)
}

func (s *CuratedImagesUploadingE2ETestSuite) Test_ValidateCuratedImageUploading() {
	s.T().Logf("[%s] GET source vhd url for: %s", s.testCaseTitle, s.ImageVhdName)

	sourceVhdUrl, err := utils.GenerateImageVhdUrl(s.ImageVhdName)
	s.Require().NoError(err)

	s.T().Logf("[%s] CREATE image definition", s.testCaseTitle)

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         fmt.Sprintf("%s-uploading-def-%d-%d", s.uniquePrefix, s.OsType, s.Architecture),
		OwnerId:      s.OwnerId,
		OsType:       s.OsType,
		Architecture: s.Architecture,
		Enabled:      true,
	})
	s.Require().NoError(err)

	imageDefinition := createImageDefinitionResp.ImageDefinition

	s.T().Logf("[%s] CREATE image definition pointer", s.testCaseTitle)

	createImageDefinitionPointerResp, err := s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      fmt.Sprintf("%s-uploading-def-pointer-%d-%d", s.uniquePrefix, s.OsType, s.Architecture),
		OwnerId:                   s.OwnerId,
		Enabled:                   true,
		PointsToImageDefinitionId: imageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Logf("[%s] CREATE %d version(s) for image definition (id:name) (%d:%s)", s.testCaseTitle, s.ImageVersionsToUpload, imageDefinition.Id, imageDefinition.Name)

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
			VmGeneration:      s.VMGeneration,
			OsState:           s.OsState,
			AzurePurchasePlan: s.AzurePurchasePlan,
			AgentUser:         s.AgentUser,
		})
		s.Require().NoError(err)

		s.Require().Equal(version, createImageVersionResp.ImageVersion.Version)
		s.Require().Contains([]sharedapi.ImageVersionState{sharedapi.ImageVersionState_Pending, sharedapi.ImageVersionState_Provisioning}, createImageVersionResp.ImageVersion.State)

		queuedImageVersions = append(queuedImageVersions, createImageVersionResp.ImageVersion)
	}

	s.T().Logf("[%s] WAIT for image versions provisioning", s.testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < s.ImageVersionsToUpload; imageVersionIndex++ {
		imageVersion := s.waitForAdminImageVersionProvisioning(s.testCaseTitle, createImageDefinitionResp.ImageDefinition.Id, queuedImageVersions[imageVersionIndex].Version)
		s.T().Logf("[%s] Image uploading finished. Image state: %s (%s)", s.testCaseTitle, imageVersion.State, imageVersion.StateDetails)
		s.Assert().Greater(imageVersion.SizeGb, int32(10))
		s.Require().Equal(sharedapi.ImageVersionState_Ready, imageVersion.State)
	}

	s.validateAdminImageDefinitionsApi(imageDefinition, createImageDefinitionPointerResp.ImageDefinition, latestUploadedVersion)
	s.validateAdminImageVersionsApi(imageDefinition, queuedImageVersions)
	s.validateCustomerImageDefinitionsApi(imageDefinition, createImageDefinitionPointerResp.ImageDefinition, latestUploadedVersion)
	s.validateCustomerImageVersionsApi(imageDefinition, createImageDefinitionPointerResp.ImageDefinition, queuedImageVersions)

	s.T().Logf("[%s] VALIDATE internal API for image definition", s.testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < s.ImageVersionsToUpload; imageVersionIndex++ {
		s.T().Logf("[%s] VALIDATE internal API for image version '%s'", s.testCaseTitle, queuedImageVersions[imageVersionIndex].Version)

		s.validateInternalApiRequests(
			"Curated",
			imageDefinition.Id,
			queuedImageVersions[imageVersionIndex].Version,
			imageDefinition,
			fmt.Sprintf("%d.0.0", imageVersionIndex+1),
		)
	}

	s.T().Logf("[%s] VALIDATE internal API for image version 'latest'", s.testCaseTitle)

	s.validateInternalApiRequests(
		"Curated",
		imageDefinition.Id,
		"latest",
		imageDefinition,
		fmt.Sprintf("%d.0.0", s.ImageVersionsToUpload),
	)

	s.T().Logf("[%s] VALIDATE internal API for image definition pointer", s.testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < s.ImageVersionsToUpload; imageVersionIndex++ {
		s.T().Logf("[%s] VALIDATE internal API for image version '%s' using image definition pointer", s.testCaseTitle, queuedImageVersions[imageVersionIndex].Version)

		s.validateInternalApiRequests(
			"Curated",
			createImageDefinitionPointerResp.ImageDefinition.Id,
			queuedImageVersions[imageVersionIndex].Version,
			createImageDefinitionPointerResp.ImageDefinition,
			fmt.Sprintf("%d.0.0", imageVersionIndex+1),
		)
	}

	s.T().Logf("[%s] VALIDATE internal API for image version 'latest' using image definition pointer", s.testCaseTitle)

	s.validateInternalApiRequests(
		"Curated",
		createImageDefinitionPointerResp.ImageDefinition.Id,
		"latest",
		createImageDefinitionPointerResp.ImageDefinition,
		fmt.Sprintf("%d.0.0", s.ImageVersionsToUpload),
	)

	s.T().Logf("[%s] DELETE image versions", s.testCaseTitle)

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

	s.T().Logf("[%s] DELETE image definition pointer", s.testCaseTitle)
	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: createImageDefinitionPointerResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Logf("[%s] DELETE image definition", s.testCaseTitle)

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
}

func (s *CuratedImagesUploadingE2ETestSuite) validateInternalApiRequests(imageSource string, imageId uint64, imageVersion string, expectedImageDefinition *admin_api.ImageDefinition, expectedImageVersion string) {
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
	s.Require().Equal(s.OsState, imageReferenceResp.ImageReference.OsState)
	s.Require().Equal(s.AzurePurchasePlan, imageReferenceResp.ImageReference.AzurePurchasePlan)
	s.Require().Equal(s.AgentUser, imageReferenceResp.ImageReference.AgentUser)
	// check backward compatibility
	s.Require().Equal(expectedImageVersion, imageReferenceResp.ExactImageVersion)                                                                         //nolint:staticcheck
	s.Require().Regexp(regexp.MustCompile(`Microsoft\.Compute\/galleries\/[\w.]+/images/[\w-]+\/versions\/\d+\.\d+\.\d+`), imageReferenceResp.ResourceId) //nolint:staticcheck
	s.Require().Contains(imageReferenceResp.ResourceId, fmt.Sprintf("/versions/%s", expectedImageVersion))                                                //nolint:staticcheck
	s.Require().Equal(s.OsState, imageReferenceResp.OsState)                                                                                              //nolint:staticcheck
	s.Require().Equal(s.AzurePurchasePlan, imageReferenceResp.AzurePurchasePlan)                                                                          //nolint:staticcheck
	s.Require().Equal(s.AgentUser, imageReferenceResp.AgentUser)                                                                                          //nolint:staticcheck

	s.T().Logf("[%s] GET image details for key {%s, %d, %s}", s.testCaseTitle, imageSource, imageId, imageVersion)
	imageDetailsResp, err := s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        &sharedapi.Actor{GlobalId: "test"},
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
	s.Require().Greater(imageDetailsResp.ImageDetails.SizeGb, int32(0))
}

func (s *CuratedImagesUploadingE2ETestSuite) validateAdminImageDefinitionsApi(createdImageDefinition *adminapi.ImageDefinition, createdImageDefinitionPointer *adminapi.ImageDefinition, latestUploadedVersion string) {
	s.T().Logf("[%s] GET image definition using Admin API", s.testCaseTitle)

	getAdminImageDefinitionResp, err := s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{ImageDefinitionId: createdImageDefinition.Id})
	s.Require().NoError(err)
	s.Require().Equal(createdImageDefinition.Id, getAdminImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(createdImageDefinition.Name, getAdminImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(s.OwnerId, getAdminImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal(s.OsType, getAdminImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(s.Architecture, getAdminImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(true, getAdminImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(latestUploadedVersion, getAdminImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Greater(getAdminImageDefinitionResp.ImageDefinition.LatestVersionSizeGb, int32(10))
	s.Require().Equal(s.ImageVersionsToUpload, int(getAdminImageDefinitionResp.ImageDefinition.ImageVersionsCount))

	s.T().Logf("[%s] GET image definition pointer using Admin API", s.testCaseTitle)

	getAdminImageDefinitionResp, err = s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{ImageDefinitionId: createdImageDefinitionPointer.Id})
	s.Require().NoError(err)
	s.Require().Equal(createdImageDefinitionPointer.Id, getAdminImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(createdImageDefinitionPointer.Name, getAdminImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(s.OwnerId, getAdminImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal(s.OsType, getAdminImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(s.Architecture, getAdminImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(true, getAdminImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal("", getAdminImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getAdminImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(int32(0), getAdminImageDefinitionResp.ImageDefinition.ImageVersionsCount)

	s.T().Logf("[%s] LIST image definition using Admin API", s.testCaseTitle)

	listAdminImageDefinitionResp, err := s.adminTwirpClient.ListCuratedImageDefinitions(s.ctx, &adminapi.ListCuratedImageDefinitionsRequest{})
	s.Require().NoError(err)
	listedAdminImageDefinitions := s.filterTestCuratedImageDefinitions(listAdminImageDefinitionResp.ImageDefinitions)
	s.Require().Equal(2, len(listedAdminImageDefinitions))
	s.Require().Equal(createdImageDefinition.Id, listedAdminImageDefinitions[0].Id)
	s.Require().Equal(createdImageDefinition.Name, listedAdminImageDefinitions[0].Name)
	s.Require().Equal(s.OwnerId, listedAdminImageDefinitions[0].OwnerId)
	s.Require().Equal(s.OsType, listedAdminImageDefinitions[0].OsType)
	s.Require().Equal(s.Architecture, listedAdminImageDefinitions[0].Architecture)
	s.Require().Equal(true, listedAdminImageDefinitions[0].Enabled)
	s.Require().Equal(latestUploadedVersion, listedAdminImageDefinitions[0].LatestVersion)
	s.Require().Greater(listedAdminImageDefinitions[0].LatestVersionSizeGb, int32(10))
	s.Require().Equal(s.ImageVersionsToUpload, int(listedAdminImageDefinitions[0].ImageVersionsCount))
	s.Require().Equal(createdImageDefinitionPointer.Id, listedAdminImageDefinitions[1].Id)
	s.Require().Equal(createdImageDefinitionPointer.Name, listedAdminImageDefinitions[1].Name)
	s.Require().Equal(s.OwnerId, listedAdminImageDefinitions[1].OwnerId)
	s.Require().Equal(s.OsType, listedAdminImageDefinitions[1].OsType)
	s.Require().Equal(s.Architecture, listedAdminImageDefinitions[1].Architecture)
	s.Require().Equal(true, listedAdminImageDefinitions[1].Enabled)
}

func (s *CuratedImagesUploadingE2ETestSuite) validateAdminImageVersionsApi(createdImageDefinition *adminapi.ImageDefinition, queuedImageVersions []*adminapi.ImageVersion) {
	s.T().Logf("[%s] GET image version using Admin API", s.testCaseTitle)

	assertImageVersion := func(actualImageVersion *adminapi.ImageVersion, expectedImageVersion *adminapi.ImageVersion) {
		s.Require().Equal(expectedImageVersion.Id, actualImageVersion.Id)
		s.Require().Equal(expectedImageVersion.Version, actualImageVersion.Version)
		s.Require().Equal(true, actualImageVersion.Enabled)
		s.Require().Equal(createdImageDefinition.Id, actualImageVersion.ImageDefinitionId)
		s.Require().Greater(actualImageVersion.SizeGb, int32(0))
		s.Require().Regexp(regexp.MustCompile(`Microsoft\.Compute\/galleries\/[\w.]+/images/[\w-]+\/versions\/\d+\.\d+\.\d+`), actualImageVersion.ResourceId)
		s.Require().Equal(s.VMGeneration, actualImageVersion.VmGeneration)
		s.Require().Equal(s.OsState, actualImageVersion.OsState)
		s.Require().Equal(s.AzurePurchasePlan, actualImageVersion.AzurePurchasePlan)
		s.Require().Equal(s.AgentUser, actualImageVersion.AgentUser)
	}

	for _, queuedImageVersion := range queuedImageVersions {
		getAdminImageVersionResp, err := s.adminTwirpClient.GetCuratedImageVersion(s.ctx, &adminapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: createdImageDefinition.Id,
			Version:           queuedImageVersion.Version,
		})
		s.Require().NoError(err)
		assertImageVersion(getAdminImageVersionResp.ImageVersion, queuedImageVersion)
	}

	s.T().Logf("[%s] LIST image versions using Admin API", s.testCaseTitle)

	listAdminImageVersions, err := s.adminTwirpClient.ListCuratedImageVersions(s.ctx, &adminapi.ListCuratedImageVersionsRequest{
		ImageDefinitionId: createdImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(s.ImageVersionsToUpload, len(listAdminImageVersions.ImageVersions))
	for index := 0; index < len(listAdminImageVersions.ImageVersions); index++ {
		actualImageVersion := listAdminImageVersions.ImageVersions[index]
		expectedImageVersion := queuedImageVersions[s.ImageVersionsToUpload-index-1]
		assertImageVersion(actualImageVersion, expectedImageVersion)
	}
}

func (s *CuratedImagesUploadingE2ETestSuite) validateCustomerImageDefinitionsApi(createdImageDefinition *adminapi.ImageDefinition, createdImageDefinitionPointer *adminapi.ImageDefinition, latestUploadedVersion string) {
	s.T().Logf("[%s] GET image definition using Customers API", s.testCaseTitle)

	getImageDefinitionResp, err := s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "test"},
		ImageDefinitionId: createdImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(createdImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(createdImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(s.OwnerId, getImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal(s.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(s.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(true, getImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(latestUploadedVersion, getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Greater(getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb, int32(10))
	// CustomerAPI returns 0 for Curated images for ImageVersionsCount and TotalImageVersionsSizeGb.
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.TotalImageVersionsSizeGb)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)

	s.T().Logf("[%s] GET image definition pointer using Customers API", s.testCaseTitle)

	getImageDefinitionPointerResp, err := s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "test"},
		ImageDefinitionId: createdImageDefinitionPointer.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(createdImageDefinitionPointer.Id, getImageDefinitionPointerResp.ImageDefinition.Id)
	s.Require().Equal(createdImageDefinitionPointer.Name, getImageDefinitionPointerResp.ImageDefinition.Name)
	s.Require().Equal(s.OwnerId, getImageDefinitionPointerResp.ImageDefinition.OwnerId)
	s.Require().Equal(s.OsType, getImageDefinitionPointerResp.ImageDefinition.OsType)
	s.Require().Equal(s.Architecture, getImageDefinitionPointerResp.ImageDefinition.Architecture)
	s.Require().Equal(true, getImageDefinitionPointerResp.ImageDefinition.Enabled)
	s.Require().Equal(latestUploadedVersion, getImageDefinitionPointerResp.ImageDefinition.LatestVersion)
	s.Require().Greater(getImageDefinitionPointerResp.ImageDefinition.LatestVersionSizeGb, int32(10))
	// CustomerAPI returns 0 for Curated images for ImageVersionsCount and TotalImageVersionsSizeGb.
	s.Require().Equal(int32(0), getImageDefinitionPointerResp.ImageDefinition.TotalImageVersionsSizeGb)
	s.Require().Equal(int32(0), getImageDefinitionPointerResp.ImageDefinition.ImageVersionsCount)

	s.T().Logf("[%s] LIST image definitions using Customers API", s.testCaseTitle)

	listImageDefinitionPointerResp, err := s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner: &sharedapi.Actor{GlobalId: "test"},
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions := s.filterTestCustomerImageDefinitions(listImageDefinitionPointerResp.ImageDefinitions)
	s.Require().Equal(2, len(listedCustomerImageDefinitions))
	s.Require().Equal(createdImageDefinition.Id, listedCustomerImageDefinitions[0].Id)
	s.Require().Equal(createdImageDefinition.Name, listedCustomerImageDefinitions[0].Name)
	s.Require().Equal(s.OwnerId, listedCustomerImageDefinitions[0].OwnerId)
	s.Require().Equal(s.OsType, listedCustomerImageDefinitions[0].OsType)
	s.Require().Equal(s.Architecture, listedCustomerImageDefinitions[0].Architecture)
	s.Require().Equal(true, listedCustomerImageDefinitions[0].Enabled)
	s.Require().Equal(latestUploadedVersion, listedCustomerImageDefinitions[0].LatestVersion)
	s.Require().Greater(listedCustomerImageDefinitions[0].LatestVersionSizeGb, int32(10))
	s.Require().Equal(createdImageDefinitionPointer.Id, listedCustomerImageDefinitions[1].Id)
	s.Require().Equal(createdImageDefinitionPointer.Name, listedCustomerImageDefinitions[1].Name)
	s.Require().Equal(s.OwnerId, listedCustomerImageDefinitions[1].OwnerId)
	s.Require().Equal(s.OsType, listedCustomerImageDefinitions[1].OsType)
	s.Require().Equal(s.Architecture, listedCustomerImageDefinitions[1].Architecture)
	s.Require().Equal(true, listedCustomerImageDefinitions[1].Enabled)
	s.Require().Equal(latestUploadedVersion, listedCustomerImageDefinitions[1].LatestVersion)
	s.Require().Greater(listedCustomerImageDefinitions[1].LatestVersionSizeGb, int32(10))
	// CustomerAPI returns 0 for Curated images for ImageVersionsCount and TotalImageVersionsSizeGb.
	s.Require().Equal(int32(0), listedCustomerImageDefinitions[0].TotalImageVersionsSizeGb)
	s.Require().Equal(int32(0), listedCustomerImageDefinitions[0].ImageVersionsCount)
	s.Require().Equal(int32(0), listedCustomerImageDefinitions[1].TotalImageVersionsSizeGb)
	s.Require().Equal(int32(0), listedCustomerImageDefinitions[1].ImageVersionsCount)
}

func (s *CuratedImagesUploadingE2ETestSuite) validateCustomerImageVersionsApi(createdImageDefinition *adminapi.ImageDefinition, createdImageDefinitionPointer *adminapi.ImageDefinition, queuedImageVersions []*adminapi.ImageVersion) {
	assertImageVersion := func(actualImageVersion *imagesapi.ImageVersion, expectedImageVersion *adminapi.ImageVersion) {
		s.Require().Equal(expectedImageVersion.Version, actualImageVersion.Version)
		s.Require().Equal(createdImageDefinition.Id, actualImageVersion.ImageDefinitionId)
		s.Require().Greater(actualImageVersion.SizeGb, int32(0))
	}

	s.T().Logf("[%s] GET image version using Customer API", s.testCaseTitle)

	for _, queuedImageVersion := range queuedImageVersions {
		getCustomerImageVersionResp, err := s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: "test"},
			ImageDefinitionId: createdImageDefinition.Id,
			Version:           queuedImageVersion.Version,
		})
		s.Require().NoError(err)
		assertImageVersion(getCustomerImageVersionResp.ImageVersion, queuedImageVersion)
	}

	s.T().Logf("[%s] LIST image versions using Customer API", s.testCaseTitle)

	listAdminImageVersions, err := s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             &sharedapi.Actor{GlobalId: "test"},
		ImageDefinitionId: createdImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(s.ImageVersionsToUpload, len(listAdminImageVersions.ImageVersions))
	for index := 0; index < len(listAdminImageVersions.ImageVersions); index++ {
		actualImageVersion := listAdminImageVersions.ImageVersions[index]
		expectedImageVersion := queuedImageVersions[s.ImageVersionsToUpload-index-1]
		assertImageVersion(actualImageVersion, expectedImageVersion)
	}

	s.T().Logf("[%s] GET image version from pointer using Customer API", s.testCaseTitle)

	for _, queuedImageVersion := range queuedImageVersions {
		getCustomerImageVersionResp, err := s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: "test"},
			ImageDefinitionId: createdImageDefinitionPointer.Id,
			Version:           queuedImageVersion.Version,
		})
		s.Require().NoError(err)
		assertImageVersion(getCustomerImageVersionResp.ImageVersion, queuedImageVersion)
	}

	s.T().Logf("[%s] LIST image versions from pointer using Customer API", s.testCaseTitle)

	listAdminImageVersions, err = s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             &sharedapi.Actor{GlobalId: "test"},
		ImageDefinitionId: createdImageDefinitionPointer.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(s.ImageVersionsToUpload, len(listAdminImageVersions.ImageVersions))
	for index := 0; index < len(listAdminImageVersions.ImageVersions); index++ {
		actualImageVersion := listAdminImageVersions.ImageVersions[index]
		expectedImageVersion := queuedImageVersions[s.ImageVersionsToUpload-index-1]
		assertImageVersion(actualImageVersion, expectedImageVersion)
	}
}
