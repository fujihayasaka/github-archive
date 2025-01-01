package e2e

import (
	"fmt"
	"regexp"
	"testing"

	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/suite"
)

type ImagesGenerationCustomerImagesE2ETestSuite struct {
	BaseE2ETestSuite
	testCaseTitle string
}

func TestImagesGenerationCustomerImagesE2ETestSuite(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	t.Parallel()
	suite.Run(t, new(ImagesGenerationCustomerImagesE2ETestSuite))
}

func (s *ImagesGenerationCustomerImagesE2ETestSuite) SetupSuite() {
	s.BaseE2ETestSuite.SetupSuite()
	s.testCaseTitle = "Customer, ImageGeneration"
}

func (s *ImagesGenerationCustomerImagesE2ETestSuite) Test_ImageGeneration() {
	var (
		imageOwner           = &sharedapi.Actor{GlobalId: fmt.Sprintf("O_%s_e2e_image_generation", s.uniquePrefix)}
		addedImageDefinition = &imagesapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}
		imageVhdName        = "test-e2e-ubuntu-18-04-x64.vhd"
		expectedImageSizeGB = int32(30)
		testCaseTitle       = fmt.Sprintf("ImageGeneration %v, %v", addedImageDefinition.OsType, addedImageDefinition.Architecture)
	)

	s.T().Logf("[%s] GET source vhd url for: Linux X64", s.testCaseTitle)

	sourceVhdUrl, err := utils.GenerateImageVhdUrl(imageVhdName)
	s.Require().NoError(err)

	s.T().Logf("[%s] CREATE image definition via Customer API", s.testCaseTitle)

	createImageDefinitionResp, err := s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:        imageOwner,
		Name:         addedImageDefinition.Name,
		OsType:       addedImageDefinition.OsType,
		Architecture: addedImageDefinition.Architecture,
	})
	s.Require().NoError(err)
	s.Require().NotNil(createImageDefinitionResp)
	addedImageDefinition.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Logf("[%s] START image version generation via Internal API version 1.0.0", s.testCaseTitle)
	generatedImageVersionResp, err := s.internalTwirpClient.StartImageVersionGeneration(s.ctx, &internalapi.StartImageVersionGenerationRequest{
		Owner:             imageOwner,
		ImageSource:       "Customer",
		ImageId:           addedImageDefinition.Id,
		ImageVersion:      "1.0.0",
		VmGeneration:      sharedapi.VmGeneration_Gen1,
		AgentUser:         "",
		AzurePurchasePlan: "",
	})
	s.Require().NoError(err)
	s.Require().NotNil(generatedImageVersionResp)

	s.T().Logf("[%s] UPDATE image version generation via Internal API fixed version", s.testCaseTitle)
	updateImageVersionResp, err := s.internalTwirpClient.UpdateImageVersionGenerationStatus(s.ctx, &internalapi.UpdateImageVersionGenerationStatusRequest{
		Owner:        imageOwner,
		ImageSource:  "Customer",
		ImageId:      addedImageDefinition.Id,
		ImageVersion: "1.0.0",
		StateDetails: "25%",
	})
	s.Require().NoError(err)
	s.Require().NotNil(updateImageVersionResp)

	s.T().Logf("[%s] FINISH image version generation via Internal API fixed version", s.testCaseTitle)
	finishImageVersionResp, err := s.internalTwirpClient.FinishImageVersionGeneration(s.ctx, &internalapi.FinishImageVersionGenerationRequest{
		Owner:           imageOwner,
		ImageSource:     "Customer",
		ImageId:         addedImageDefinition.Id,
		ImageVersion:    "1.0.0",
		Success:         true,
		SourceVhdUrl:    sourceVhdUrl,
		WorkflowOwnerId: "test-workflow-owner-id",
	})
	s.Require().NoError(err)
	s.Require().NotNil(finishImageVersionResp)

	s.T().Logf("[%s] START image version generation via Internal API version with auto-increment", s.testCaseTitle)
	generatedImageVersionResp, err = s.internalTwirpClient.StartImageVersionGeneration(s.ctx, &internalapi.StartImageVersionGenerationRequest{
		Owner:             imageOwner,
		ImageSource:       "Customer",
		ImageId:           addedImageDefinition.Id,
		ImageVersion:      "",
		VmGeneration:      sharedapi.VmGeneration_Gen2,
		OsState:           sharedapi.OsState_Specialized,
		AgentUser:         "Test Agent User",
		AzurePurchasePlan: "test_publisher:test_product:test_name",
	})
	s.Require().NoError(err)
	s.Require().NotNil(generatedImageVersionResp)

	s.T().Logf("[%s] UPDATE image version generation via Internal API fixed version", s.testCaseTitle)
	updateImageVersionResp, err = s.internalTwirpClient.UpdateImageVersionGenerationStatus(s.ctx, &internalapi.UpdateImageVersionGenerationStatusRequest{
		Owner:        imageOwner,
		ImageSource:  "Customer",
		ImageId:      addedImageDefinition.Id,
		ImageVersion: "1.1.0",
		StateDetails: "25%",
	})
	s.Require().NoError(err)
	s.Require().NotNil(updateImageVersionResp)

	s.T().Logf("[%s] FINISH image version generation via Internal API fixed version", s.testCaseTitle)
	finishImageVersionResp, err = s.internalTwirpClient.FinishImageVersionGeneration(s.ctx, &internalapi.FinishImageVersionGenerationRequest{
		Owner:           imageOwner,
		ImageSource:     "Customer",
		ImageId:         addedImageDefinition.Id,
		ImageVersion:    "1.1.0",
		Success:         true,
		SourceVhdUrl:    sourceVhdUrl,
		WorkflowOwnerId: "test-workflow-owner-id",
	})
	s.Require().NoError(err)
	s.Require().NotNil(finishImageVersionResp)

	listImageVersionsResp, err := s.customerTwirpClient.ListCustomerImageVersions(s.ctx, &imagesapi.ListCustomerImageVersionsRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(2, len(listImageVersionsResp.ImageVersions))
	s.Require().Equal("1.1.0", listImageVersionsResp.ImageVersions[0].Version)
	s.Require().Equal("1.0.0", listImageVersionsResp.ImageVersions[1].Version)

	s.T().Logf("[%s] WAIT for image versions provisioning", s.testCaseTitle)

	for imageVersionIndex := 0; imageVersionIndex < 2; imageVersionIndex++ {
		imageVersion := s.waitForCustomerImageVersionProvisioning(testCaseTitle, imageOwner, createImageDefinitionResp.ImageDefinition.Id, listImageVersionsResp.ImageVersions[imageVersionIndex].Version)
		s.T().Logf("[%s] Image uploading finished. Image state: %s (%s)", testCaseTitle, imageVersion.State, imageVersion.StateDetails)
		s.Assert().Equal(imageVersion.SizeGb, expectedImageSizeGB)
		s.Require().Equal(sharedapi.ImageVersionState_Ready, imageVersion.State)
	}

	latestAddedImageVersion := "1.1.0"

	s.T().Logf("[%s] GET image reference for latest version", s.testCaseTitle)
	s.validateGetImageReferenceRequests(
		"Customer",
		addedImageDefinition.Id,
		"latest",
		latestAddedImageVersion,
		sharedapi.OsState_Specialized,
		"Test Agent User",
		"test_publisher:test_product:test_name",
	)

	s.T().Logf("[%s] GET image reference for version 1.1.0", s.testCaseTitle)
	s.validateGetImageReferenceRequests(
		"Customer",
		addedImageDefinition.Id,
		"1.1.0",
		"1.1.0",
		sharedapi.OsState_Specialized,
		"Test Agent User",
		"test_publisher:test_product:test_name",
	)

	s.T().Logf("[%s] GET image reference for version 1.0.0", s.testCaseTitle)
	s.validateGetImageReferenceRequests(
		"Customer",
		addedImageDefinition.Id,
		"1.0.0",
		"1.0.0",
		sharedapi.OsState_Generalized,
		"",
		"",
	)

	s.T().Logf("[%s] GET image definition using Customers API", testCaseTitle)

	getImageDefinitionResp, err := s.customerTwirpClient.GetCustomerImageDefinition(s.ctx, &imagesapi.GetCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(addedImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(addedImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(addedImageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(addedImageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(latestAddedImageVersion, getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(2), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Greater(getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb, int32(10))
	s.Require().Greater(getImageDefinitionResp.ImageDefinition.TotalImageVersionsSizeGb, int32(10))

	s.T().Logf("[%s] LIST image definition using Customers API", testCaseTitle)

	listImageDefinitionResp, err := s.customerTwirpClient.ListCustomerImageDefinitions(s.ctx, &imagesapi.ListCustomerImageDefinitionsRequest{
		Owner: imageOwner,
	})
	s.Require().NoError(err)
	s.Require().Equal(1, len(listImageDefinitionResp.ImageDefinitions))
	s.Require().Equal(addedImageDefinition.Id, listImageDefinitionResp.ImageDefinitions[0].Id)
	s.Require().Equal(addedImageDefinition.Name, listImageDefinitionResp.ImageDefinitions[0].Name)
	s.Require().Equal(addedImageDefinition.OsType, listImageDefinitionResp.ImageDefinitions[0].OsType)
	s.Require().Equal(addedImageDefinition.Architecture, listImageDefinitionResp.ImageDefinitions[0].Architecture)
	s.Require().Equal(latestAddedImageVersion, listImageDefinitionResp.ImageDefinitions[0].LatestVersion)
	s.Require().Equal(int32(2), listImageDefinitionResp.ImageDefinitions[0].ImageVersionsCount)
	s.Require().Greater(listImageDefinitionResp.ImageDefinitions[0].LatestVersionSizeGb, int32(10))
	s.Require().Greater(listImageDefinitionResp.ImageDefinitions[0].TotalImageVersionsSizeGb, int32(10))

	s.T().Logf("[%s] DELETE image definitions via Customer API", s.testCaseTitle)

	_, err = s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Logf("[%s] Wait for image definition deletion via Customer API", s.testCaseTitle)

	s.waitForCustomerImageDefinitionDeletion(imageOwner, addedImageDefinition.Id)
	s.Require().NoError(err)

	s.T().Logf("[%s] LIST image definitions via Customer API", s.testCaseTitle)

	listImageDefinitionsResp, err := s.customerTwirpClient.ListCustomerImageDefinitions(s.ctx, &imagesapi.ListCustomerImageDefinitionsRequest{
		Owner: imageOwner,
	})
	s.Require().NoError(err)
	s.Require().Equal(0, len(listImageDefinitionsResp.ImageDefinitions))
}

func (s *ImagesGenerationCustomerImagesE2ETestSuite) validateGetImageReferenceRequests(imageSource string, imageId uint64, imageVersion string, expectedImageVersion string, expectedOsState sharedapi.OsState, expectedAgentUser string, expectedAzurePurchasePlan string) {
	imageReferenceResp, err := s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  imageSource,
		ImageId:      imageId,
		ImageVersion: imageVersion,
	})
	s.Require().NoError(err)
	s.Require().Equal(expectedImageVersion, imageReferenceResp.ImageReference.ExactImageVersion)
	s.Require().Regexp(regexp.MustCompile(`Microsoft\.Compute\/galleries\/[\w.]+/images/[\w-]+\/versions\/\d+\.\d+\.\d+`), imageReferenceResp.ImageReference.ResourceId)
	s.Require().Contains(imageReferenceResp.ImageReference.ResourceId, fmt.Sprintf("/versions/%s", expectedImageVersion))
	s.Require().Equal(expectedOsState, imageReferenceResp.ImageReference.OsState)
	s.Require().Equal(expectedAgentUser, imageReferenceResp.ImageReference.AgentUser)
	s.Require().Equal(expectedAzurePurchasePlan, imageReferenceResp.ImageReference.AzurePurchasePlan)
	// check backward compatibility
	s.Require().Equal(expectedImageVersion, imageReferenceResp.ExactImageVersion)                                                                         //nolint:staticcheck
	s.Require().Regexp(regexp.MustCompile(`Microsoft\.Compute\/galleries\/[\w.]+/images/[\w-]+\/versions\/\d+\.\d+\.\d+`), imageReferenceResp.ResourceId) //nolint:staticcheck
	s.Require().Contains(imageReferenceResp.ResourceId, fmt.Sprintf("/versions/%s", expectedImageVersion))                                                //nolint:staticcheck
	s.Require().Equal(expectedOsState, imageReferenceResp.OsState)                                                                                        //nolint:staticcheck
	s.Require().Equal(expectedAgentUser, imageReferenceResp.AgentUser)                                                                                    //nolint:staticcheck
	s.Require().Equal(expectedAzurePurchasePlan, imageReferenceResp.AzurePurchasePlan)                                                                    //nolint:staticcheck
}
