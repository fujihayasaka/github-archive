package e2e

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/wrapperspb"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
)

type InternalApiE2ETestSuite struct {
	BaseE2ETestSuite
}

func TestInternalApiE2ETestSuite(t *testing.T) {
	t.Parallel()
	suite.Run(t, new(InternalApiE2ETestSuite))
}

func (s *InternalApiE2ETestSuite) Test_InternalApiForCuratedAndCustomerImages() {
	var (
		testActor              = &sharedapi.Actor{GlobalId: "test-actor"}
		curatedImageDefinition = &adminapi.ImageDefinition{
			Name:                       fmt.Sprintf("%s-internalapi-curated-1", s.uniquePrefix),
			OsType:                     sharedapi.OsType_Linux,
			Architecture:               sharedapi.Architecture_X64,
			Enabled:                    true,
			OwnerId:                    models.GithubOwnerId,
			IsImageGenerationSupported: true,
		}
		customerImageOwner      = &sharedapi.Actor{GlobalId: fmt.Sprintf("O_%s_internalapi_test", s.uniquePrefix)}
		customerImageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-internalapi-customer-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
		}
		imageVersion = "1.0.0"
	)

	s.T().Log("GET image details with unknown source")

	_, err := s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        testActor,
		ImageSource:  "test-source",
		ImageId:      1,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "unsupported image type")

	s.T().Log("GET image reference with unknown source")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "test-source",
		ImageId:      1,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "unsupported image type")

	s.T().Log("CREATE curated image definition via Admin API")

	curatedImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:                       curatedImageDefinition.Name,
		OsType:                     curatedImageDefinition.OsType,
		Architecture:               curatedImageDefinition.Architecture,
		Enabled:                    curatedImageDefinition.Enabled,
		OwnerId:                    curatedImageDefinition.OwnerId,
		IsImageGenerationSupported: curatedImageDefinition.IsImageGenerationSupported,
	})
	s.Require().NoError(err)
	s.Require().True(curatedImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)
	curatedImageDefinition.Id = curatedImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE customer image definition via Customer API")

	customerImageDefinitionResp, err := s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:         customerImageOwner,
		Name:          customerImageDefinition.Name,
		OsType:        customerImageDefinition.OsType,
		Architecture:  customerImageDefinition.Architecture,
		RunnerGroupId: wrapperspb.UInt64(uint64(2)),
	})
	s.Require().NoError(err)
	customerImageDefinition.Id = customerImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET image details with incorrect source")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        testActor,
		ImageSource:  "Customer",
		ImageId:      curatedImageDefinition.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition is not found")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        testActor,
		ImageSource:  "Curated",
		ImageId:      customerImageDefinition.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image reference with incorrect source")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Customer",
		ImageId:      curatedImageDefinition.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition is not found")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Curated",
		ImageId:      customerImageDefinition.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image details for 'latest' when curated image definition has no versions")

	s.validateImageDetails(
		"Curated",
		curatedImageDefinition.Id,
		"latest",
		testActor,
		curatedImageDefinition,
		true,
	)

	s.T().Log("GET image details for 'latest' when customer image definition has no versions")

	s.validateImageDetails(
		"Customer",
		customerImageDefinition.Id,
		"latest",
		customerImageOwner,
		customerImageDefinition,
		true,
	)

	s.T().Log("GET image details for 'latest' for customer image definition with incorrect customer")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        &sharedapi.Actor{GlobalId: "invalid-actor"},
		ImageSource:  "Customer",
		ImageId:      customerImageDefinition.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image details for non-existing image version")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        customerImageOwner,
		ImageSource:  "Customer",
		ImageId:      customerImageDefinition.Id,
		ImageVersion: "3.0.0",
	})
	s.Require().ErrorContains(err, "image version is not found")

	s.T().Log("GET image reference for 'latest' when curated image definition has no versions")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinition.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for 'latest' when customer image definition has no versions")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Customer",
		ImageId:      customerImageDefinition.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for non existing image version")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinition.Id,
		ImageVersion: "3.0.0",
	})
	s.Require().ErrorContains(err, "image version is not found")

	s.T().Log("CREATE image versions for curated and customer image definitions")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: curatedImageDefinition.Id,
		Version:           imageVersion,
		Enabled:           true,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().NoError(err)

	_, err = s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{
		Owner:             customerImageOwner,
		ImageDefinitionId: customerImageDefinition.Id,
		Version:           imageVersion,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().NoError(err)

	s.waitForAdminImageVersionProvisionFailed(curatedImageDefinition.Id, imageVersion)
	s.waitForCustomerImageVersionProvisionFailed(customerImageOwner, customerImageDefinition.Id, imageVersion)

	s.T().Log("GET image details for 'latest' when at least one version exists for curated image definition")

	s.validateImageDetails(
		"Curated",
		curatedImageDefinition.Id,
		"latest",
		testActor,
		curatedImageDefinition,
		true,
	)

	s.T().Log("GET image details for 'latest' when at least one version exists for customer image definition")

	s.validateImageDetails(
		"Customer",
		customerImageDefinition.Id,
		"latest",
		customerImageOwner,
		customerImageDefinition,
		true,
	)

	s.T().Log("GET image details for 'latest' for customer image definition with incorrect user")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        &sharedapi.Actor{GlobalId: "invalid-actor"},
		ImageSource:  "Customer",
		ImageId:      customerImageDefinition.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image details for specific image version for curated image definition")

	s.validateImageDetails(
		"Curated",
		curatedImageDefinition.Id,
		"1.0.0",
		testActor,
		curatedImageDefinition,
		true,
	)

	s.T().Log("GET image details for specific image version for customer image definition")

	s.validateImageDetails(
		"Customer",
		customerImageDefinition.Id,
		"1.0.0",
		customerImageOwner,
		customerImageDefinition,
		true,
	)

	s.T().Log("GET image details for specific image version for customer image definition with incorrect user")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        &sharedapi.Actor{GlobalId: "invalid-actor"},
		ImageSource:  "Customer",
		ImageId:      customerImageDefinition.Id,
		ImageVersion: "1.0.0",
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image reference for 'latest' when at least one version exists for curated image definition")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinition.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for 'latest' when at least one version exists for customer image definition")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Customer",
		ImageId:      customerImageDefinition.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for specific image version")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinition.Id,
		ImageVersion: "1.0.0",
	})
	s.Require().ErrorContains(err, "requested image version is not ready to use")

	s.T().Log("Disable curated image definition")

	updateImageDefinition, err := s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId:          curatedImageDefinition.Id,
		Name:                       curatedImageDefinition.Name,
		Enabled:                    false,
		IsImageGenerationSupported: false,
	})
	s.Require().NoError(err)
	s.Require().False(updateImageDefinition.ImageDefinition.IsImageGenerationSupported)
	s.T().Log("GET image details for 'latest' when image definition is disabled")

	s.validateImageDetails(
		"Curated",
		curatedImageDefinition.Id,
		"latest",
		testActor,
		curatedImageDefinition,
		false,
	)

	s.T().Log("GET image details for '1.0.0' when image definition is disabled")

	s.validateImageDetails(
		"Curated",
		curatedImageDefinition.Id,
		"1.0.0",
		customerImageOwner,
		curatedImageDefinition,
		false,
	)

	s.T().Log("DELETE image versions for image definitions")

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: curatedImageDefinition.Id,
		Version:           imageVersion,
	})
	s.Require().NoError(err)

	_, err = s.customerTwirpClient.DeleteCustomerImageVersion(s.ctx, &imagesapi.DeleteCustomerImageVersionRequest{
		Owner:             customerImageOwner,
		ImageDefinitionId: customerImageDefinition.Id,
		Version:           imageVersion,
	})
	s.Require().NoError(err)

	s.waitForAdminImageVersionDeletion(curatedImageDefinition.Id, imageVersion)
	s.waitForCustomerImageVersionDeletion(customerImageOwner, customerImageDefinition.Id, imageVersion)

	s.T().Log("DELETE curated image definition")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: curatedImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE customer image definition")

	_, err = s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             customerImageOwner,
		ImageDefinitionId: customerImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Log("Wait for image definition deletion via Customer API")

	s.waitForCustomerImageDefinitionDeletion(customerImageOwner, customerImageDefinition.Id)
	s.Require().NoError(err)

	// This test doesn't cover positive path for GetImageReference method because it requires image in Ready state
	// This test case is covered by ImagesUploadingE2ETestSuite
}

func (s *InternalApiE2ETestSuite) Test_InternalApiForCuratedImagesPointers() {
	var (
		testActor              = &sharedapi.Actor{GlobalId: "test-actor"}
		curatedImageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-internalapi-curatedpointer-1", s.uniquePrefix),
			OwnerId:      models.GithubOwnerId,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
		}
		curatedImageDefinitionPointer = &adminapi.ImageDefinition{
			Name:    fmt.Sprintf("%s-internalapi-curatedpointer-2", s.uniquePrefix),
			OwnerId: models.GithubOwnerId,
			Enabled: true,
		}
		imageVersion = "1.0.0"
	)

	s.T().Log("CREATE curated image definition via Admin API")

	curatedImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         curatedImageDefinition.Name,
		OsType:       curatedImageDefinition.OsType,
		Architecture: curatedImageDefinition.Architecture,
		Enabled:      curatedImageDefinition.Enabled,
		OwnerId:      curatedImageDefinition.OwnerId,
	})
	s.Require().NoError(err)
	curatedImageDefinition.Id = curatedImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE curated image definition pointer via Admin API")

	curatedImageDefinitionPointerResp, err := s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      curatedImageDefinitionPointer.Name,
		OwnerId:                   curatedImageDefinitionPointer.OwnerId,
		PointsToImageDefinitionId: curatedImageDefinition.Id,
		Enabled:                   curatedImageDefinitionPointer.Enabled,
	})
	s.Require().NoError(err)
	curatedImageDefinitionPointer.Id = curatedImageDefinitionPointerResp.ImageDefinition.Id

	s.T().Log("GET image details for 'latest' using image definition pointer when image definition has no versions")

	s.validateImageDetails(
		"Curated",
		curatedImageDefinitionPointer.Id,
		"latest",
		testActor,
		curatedImageDefinitionPointer,
		true,
	)

	s.T().Log("GET image details for non-existing version using image definition pointer")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        testActor,
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinitionPointer.Id,
		ImageVersion: "3.0.0",
	})
	s.Require().ErrorContains(err, "image version is not found")

	s.T().Log("GET image reference for 'latest' using image definition pointer when image definition has no versions")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinitionPointer.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for non-existing version using image definition pointer")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinitionPointer.Id,
		ImageVersion: "3.0.0",
	})
	s.Require().ErrorContains(err, "image version is not found")

	s.T().Log("CREATE image version for image definition")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: curatedImageDefinition.Id,
		Version:           imageVersion,
		Enabled:           true,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().NoError(err)
	s.waitForAdminImageVersionProvisionFailed(curatedImageDefinition.Id, imageVersion)

	s.T().Log("GET image details for 'latest' using image definition pointer when image definition has no versions")

	s.validateImageDetails(
		"Curated",
		curatedImageDefinitionPointer.Id,
		"latest",
		testActor,
		curatedImageDefinitionPointer,
		true,
	)

	s.T().Log("GET image details for '1.0.0' using image definition pointer")

	s.validateImageDetails(
		"Curated",
		curatedImageDefinitionPointer.Id,
		"1.0.0",
		testActor,
		curatedImageDefinitionPointer,
		true,
	)

	s.T().Log("GET image reference for 'latest' using image definition pointer when image definition has at least one version")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinitionPointer.Id,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for specific image version using image definition pointer")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinitionPointer.Id,
		ImageVersion: "1.0.0",
	})
	s.Require().ErrorContains(err, "requested image version is not ready to use")

	s.T().Log("DELETE image versions for image definitions")

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: curatedImageDefinition.Id,
		Version:           imageVersion,
	})
	s.Require().NoError(err)
	s.waitForAdminImageVersionDeletion(curatedImageDefinition.Id, imageVersion)

	s.T().Log("DELETE curated image definition pointer")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: curatedImageDefinitionPointer.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image definition")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: curatedImageDefinition.Id,
	})
	s.Require().NoError(err)
}

func (s *InternalApiE2ETestSuite) Test_InternalApiForCuratedImagesWithFeatureFlag() {
	var (
		testActor                             = &sharedapi.Actor{GlobalId: "test-actor"}
		curatedImageDefinitionWithFeatureFlag = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-internalapi-curated-2", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			FeatureFlag:  string(featureflags.TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner),
			OwnerId:      models.GithubOwnerId,
		}
	)

	s.T().Log("CREATE curated image definition via Admin API")

	curatedImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         curatedImageDefinitionWithFeatureFlag.Name,
		OsType:       curatedImageDefinitionWithFeatureFlag.OsType,
		Architecture: curatedImageDefinitionWithFeatureFlag.Architecture,
		FeatureFlag:  curatedImageDefinitionWithFeatureFlag.FeatureFlag,
		OwnerId:      curatedImageDefinitionWithFeatureFlag.OwnerId,
	})
	s.Require().NoError(err)
	curatedImageDefinitionWithFeatureFlag.Id = curatedImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET image details for actor with disabled feature flag")

	imageDetailsResp, err := s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        testActor,
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinitionWithFeatureFlag.Id,
		ImageVersion: "latest",
	})
	s.Require().NoError(err)
	s.Require().Equal(curatedImageDefinitionWithFeatureFlag.Id, imageDetailsResp.ImageDetails.Id)
	s.Require().Equal(false, imageDetailsResp.ImageDetails.Enabled)

	s.T().Log("GET image details for actor with enabled feature flag")

	imageDetailsResp, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        &sharedapi.Actor{GlobalId: featureflags.TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID},
		ImageSource:  "Curated",
		ImageId:      curatedImageDefinitionWithFeatureFlag.Id,
		ImageVersion: "latest",
	})
	s.Require().NoError(err)
	s.Require().Equal(curatedImageDefinitionWithFeatureFlag.Id, imageDetailsResp.ImageDetails.Id)
	s.Require().Equal(true, imageDetailsResp.ImageDetails.Enabled)

	s.T().Log("DELETE curated image definition")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: curatedImageDefinitionWithFeatureFlag.Id,
	})
	s.Require().NoError(err)
}

func (s *InternalApiE2ETestSuite) Test_InternalApiForImageGeneration() {
	var (
		imageOwner           = &sharedapi.Actor{GlobalId: fmt.Sprintf("O_%s_internal_generation", s.uniquePrefix)}
		addedImageDefinition = &imagesapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}
		addedImageDefinition2 = &imagesapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-def-2", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}
	)

	s.T().Log("CREATE image definition via Customer API")

	createImageDefinitionResp, err := s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:         imageOwner,
		Name:          addedImageDefinition.Name,
		OsType:        addedImageDefinition.OsType,
		Architecture:  addedImageDefinition.Architecture,
		RunnerGroupId: wrapperspb.UInt64(uint64(2)),
	})
	s.Require().NoError(err)
	addedImageDefinition.Id = createImageDefinitionResp.ImageDefinition.Id
	s.Require().Equal(uint64(2), createImageDefinitionResp.ImageDefinition.RunnerGroupId.Value)

	s.T().Log("CREATE image definition without Runner Group ID via Customer API")

	createImageDefinitionResp, err = s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:        imageOwner,
		Name:         addedImageDefinition2.Name,
		OsType:       addedImageDefinition2.OsType,
		Architecture: addedImageDefinition2.Architecture,
	})
	s.Require().NoError(err)
	addedImageDefinition2.Id = createImageDefinitionResp.ImageDefinition.Id
	s.Require().Nil(createImageDefinitionResp.ImageDefinition.RunnerGroupId)

	s.T().Log("START image version generation via Internal API empty version")
	generatedImageVersionResp, err := s.internalTwirpClient.StartImageVersionGeneration(s.ctx, &internalapi.StartImageVersionGenerationRequest{
		Owner:             imageOwner,
		ImageSource:       "Customer",
		ImageId:           addedImageDefinition.Id,
		ImageVersion:      "",
		VmGeneration:      sharedapi.VmGeneration_Gen1,
		OsState:           sharedapi.OsState_Generalized,
		AgentUser:         "",
		AzurePurchasePlan: "",
	})
	s.Require().NoError(err)
	s.Require().NotNil(generatedImageVersionResp)

	s.T().Log("START image version generation via Internal API empty version again")
	generatedImageVersionResp, err = s.internalTwirpClient.StartImageVersionGeneration(s.ctx, &internalapi.StartImageVersionGenerationRequest{
		Owner:             imageOwner,
		ImageSource:       "Customer",
		ImageId:           addedImageDefinition.Id,
		ImageVersion:      "",
		VmGeneration:      sharedapi.VmGeneration_Gen2,
		OsState:           sharedapi.OsState_Specialized,
		AgentUser:         "",
		AzurePurchasePlan: "",
	})
	s.Require().NoError(err)
	s.Require().NotNil(generatedImageVersionResp)

	s.T().Log("START image version generation via Internal API fixed version")
	generatedImageVersionResp, err = s.internalTwirpClient.StartImageVersionGeneration(s.ctx, &internalapi.StartImageVersionGenerationRequest{
		Owner:             imageOwner,
		ImageSource:       "Customer",
		ImageId:           addedImageDefinition.Id,
		ImageVersion:      "5.2.3",
		VmGeneration:      sharedapi.VmGeneration_Gen2,
		OsState:           sharedapi.OsState_Generalized,
		AgentUser:         "",
		AzurePurchasePlan: "",
	})
	s.Require().NoError(err)
	s.Require().NotNil(generatedImageVersionResp)

	s.T().Log("UPDATE image version generation via Internal API fixed version")
	updateImageVersionResp, err := s.internalTwirpClient.UpdateImageVersionGenerationStatus(s.ctx, &internalapi.UpdateImageVersionGenerationStatusRequest{
		Owner:        imageOwner,
		ImageSource:  "Customer",
		ImageId:      addedImageDefinition.Id,
		ImageVersion: "5.2.3",
		StateDetails: "25%",
	})
	s.Require().NoError(err)
	s.Require().NotNil(updateImageVersionResp)

	s.T().Log("FINISH image version generation via Internal API fixed version")
	finishImageVersionResp, err := s.internalTwirpClient.FinishImageVersionGeneration(s.ctx, &internalapi.FinishImageVersionGenerationRequest{
		Owner:           imageOwner,
		ImageSource:     "Customer",
		ImageId:         addedImageDefinition.Id,
		ImageVersion:    "5.2.3",
		Success:         true,
		SourceVhdUrl:    s.sourceVhdUrlForQuickFail,
		WorkflowOwnerId: "test-workflow-owner-id",
	})
	s.Require().NoError(err)
	s.Require().NotNil(finishImageVersionResp)

	s.T().Log("START image version generation via Internal API original version with not success")
	finishImageVersionResp, err = s.internalTwirpClient.FinishImageVersionGeneration(s.ctx, &internalapi.FinishImageVersionGenerationRequest{
		Owner:           imageOwner,
		ImageSource:     "Customer",
		ImageId:         addedImageDefinition.Id,
		ImageVersion:    "1.0.0",
		Success:         false,
		SourceVhdUrl:    s.sourceVhdUrlForQuickFail,
		WorkflowOwnerId: "test-workflow-owner-id",
		StateDetails:    "failed",
	})
	s.Require().NoError(err)
	s.Require().NotNil(finishImageVersionResp)

	s.waitForCustomerImageVersionProvisionFailed(imageOwner, addedImageDefinition.Id, "1.0.0")
	// don't wait for version 1.1.0 because it is in "Generating" state
	s.waitForCustomerImageVersionProvisionFailed(imageOwner, addedImageDefinition.Id, "5.2.3")

	listImageVersionsResp, err := s.customerTwirpClient.ListCustomerImageVersions(s.ctx, &imagesapi.ListCustomerImageVersionsRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(3, len(listImageVersionsResp.ImageVersions))
	s.Require().Equal("5.2.3", listImageVersionsResp.ImageVersions[0].Version)
	s.Require().Equal(sharedapi.ImageVersionState_ProvisionFailed, listImageVersionsResp.ImageVersions[0].State)
	s.Require().Equal("Source VHD URL is invalid", listImageVersionsResp.ImageVersions[0].StateDetails)
	s.Require().Equal("1.1.0", listImageVersionsResp.ImageVersions[1].Version)
	s.Require().Equal(sharedapi.ImageVersionState_Generating, listImageVersionsResp.ImageVersions[1].State)
	s.Require().Equal("", listImageVersionsResp.ImageVersions[1].StateDetails)
	s.Require().Equal("1.0.0", listImageVersionsResp.ImageVersions[2].Version)
	s.Require().Equal(sharedapi.ImageVersionState_ProvisionFailed, listImageVersionsResp.ImageVersions[2].State)
	s.Require().Equal("failed", listImageVersionsResp.ImageVersions[2].StateDetails)

	s.T().Log("DELETE image versions via Customer API")

	for _, imageVersion := range listImageVersionsResp.ImageVersions {
		_, err = s.customerTwirpClient.DeleteCustomerImageVersion(s.ctx, &imagesapi.DeleteCustomerImageVersionRequest{
			Owner:             imageOwner,
			ImageDefinitionId: addedImageDefinition.Id,
			Version:           imageVersion.Version,
		})
		s.Require().NoError(err)
	}

	for _, imageVersion := range listImageVersionsResp.ImageVersions {
		s.waitForCustomerImageVersionDeletion(imageOwner, addedImageDefinition.Id, imageVersion.Version)
	}

	s.T().Log("DELETE image definitions via Customer API")

	_, err = s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Log("Wait for image definition deletion via Customer API")

	s.waitForCustomerImageDefinitionDeletion(imageOwner, addedImageDefinition.Id)
	s.Require().NoError(err)

	s.T().Log("DELETE image definition without Runner Group Id via Customer API")

	_, err = s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition2.Id,
	})
	s.Require().NoError(err)

	s.T().Log("Wait for image definition deletion via Customer API")

	s.waitForCustomerImageDefinitionDeletion(imageOwner, addedImageDefinition2.Id)
	s.Require().NoError(err)
}

func (s *InternalApiE2ETestSuite) validateImageDetails(imageSource string, imageId uint64, imageVersion string, actor *sharedapi.Actor, expectedImageDefinition *adminapi.ImageDefinition, expectedEnabled bool) {
	imageDetailsResp, err := s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        actor,
		ImageSource:  imageSource,
		ImageId:      imageId,
		ImageVersion: imageVersion,
	})
	s.Require().NoError(err)
	s.Require().Equal(expectedImageDefinition.Id, imageDetailsResp.ImageDetails.Id)
	s.Require().Equal(imageId, imageDetailsResp.ImageDetails.Id)
	s.Require().Equal(imageSource, imageDetailsResp.ImageDetails.Source)
	s.Require().Equal(expectedImageDefinition.Name, imageDetailsResp.ImageDetails.Name)
	s.Require().Equal(expectedImageDefinition.OsType, imageDetailsResp.ImageDetails.OsType)
	s.Require().Equal(expectedImageDefinition.Architecture, imageDetailsResp.ImageDetails.Architecture)
	s.Require().Equal(expectedEnabled, imageDetailsResp.ImageDetails.Enabled)
	s.Require().Equal(int32(0), imageDetailsResp.ImageDetails.SizeGb) // this test suite doesn't upload real images, so size will be 0 always
}
