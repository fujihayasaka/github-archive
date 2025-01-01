package e2e

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/suite"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/featureflags"
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
			Name:         fmt.Sprintf("%s-internalapi-curated-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
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
		Owner:    testActor,
		ImageKey: &internalapi.ImageKey{Source: "test-source", Id: 1, Version: "latest"},
	})
	s.Require().ErrorContains(err, "unsupported image type")

	s.T().Log("GET image reference with unknown source")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "test-source", Id: 1, Version: "latest"},
	})
	s.Require().ErrorContains(err, "unsupported image type")

	s.T().Log("CREATE curated image definition via Admin API")

	curatedImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         curatedImageDefinition.Name,
		OsType:       curatedImageDefinition.OsType,
		Architecture: curatedImageDefinition.Architecture,
		Enabled:      curatedImageDefinition.Enabled,
	})
	s.Require().NoError(err)
	curatedImageDefinition.Id = curatedImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE customer image definition via Customer API")

	customerImageDefinitionResp, err := s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:        customerImageOwner,
		Name:         customerImageDefinition.Name,
		OsType:       customerImageDefinition.OsType,
		Architecture: customerImageDefinition.Architecture,
	})
	s.Require().NoError(err)
	customerImageDefinition.Id = customerImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET image details with incorrect source")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    testActor,
		ImageKey: &internalapi.ImageKey{Source: "Customer", Id: curatedImageDefinition.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition is not found")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    testActor,
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: customerImageDefinition.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image reference with incorrect source")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Customer", Id: curatedImageDefinition.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition is not found")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: customerImageDefinition.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image details for 'latest' when curated image definition has no versions")

	s.validateImageDetails(
		&internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinition.Id, Version: "latest"},
		testActor,
		curatedImageDefinition,
		true,
	)

	s.T().Log("GET image details for 'latest' when customer image definition has no versions")

	s.validateImageDetails(
		&internalapi.ImageKey{Source: "Customer", Id: customerImageDefinition.Id, Version: "latest"},
		customerImageOwner,
		customerImageDefinition,
		true,
	)

	s.T().Log("GET image details for 'latest' for customer image definition with incorrect customer")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    &sharedapi.Actor{GlobalId: "invalid-actor"},
		ImageKey: &internalapi.ImageKey{Source: "Customer", Id: customerImageDefinition.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image details for non-existing image version")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    customerImageOwner,
		ImageKey: &internalapi.ImageKey{Source: "Customer", Id: customerImageDefinition.Id, Version: "3.0.0"},
	})
	s.Require().ErrorContains(err, "image version is not found")

	s.T().Log("GET image reference for 'latest' when curated image definition has no versions")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinition.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for 'latest' when customer image definition has no versions")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Customer", Id: customerImageDefinition.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for non existing image version")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinition.Id, Version: "3.0.0"},
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
		&internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinition.Id, Version: "latest"},
		testActor,
		curatedImageDefinition,
		true,
	)

	s.T().Log("GET image details for 'latest' when at least one version exists for customer image definition")

	s.validateImageDetails(
		&internalapi.ImageKey{Source: "Customer", Id: customerImageDefinition.Id, Version: "latest"},
		customerImageOwner,
		customerImageDefinition,
		true,
	)

	s.T().Log("GET image details for 'latest' for customer image definition with incorrect user")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    &sharedapi.Actor{GlobalId: "invalid-actor"},
		ImageKey: &internalapi.ImageKey{Source: "Customer", Id: customerImageDefinition.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image details for specific image version for curated image definition")

	s.validateImageDetails(
		&internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinition.Id, Version: "1.0.0"},
		testActor,
		curatedImageDefinition,
		true,
	)

	s.T().Log("GET image details for specific image version for customer image definition")

	s.validateImageDetails(
		&internalapi.ImageKey{Source: "Customer", Id: customerImageDefinition.Id, Version: "1.0.0"},
		customerImageOwner,
		customerImageDefinition,
		true,
	)

	s.T().Log("GET image details for specific image version for customer image definition with incorrect user")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    &sharedapi.Actor{GlobalId: "invalid-actor"},
		ImageKey: &internalapi.ImageKey{Source: "Customer", Id: customerImageDefinition.Id, Version: "1.0.0"},
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image reference for 'latest' when at least one version exists for curated image definition")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinition.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for 'latest' when at least one version exists for customer image definition")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Customer", Id: customerImageDefinition.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for specific image version")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinition.Id, Version: "1.0.0"},
	})
	s.Require().ErrorContains(err, "requested image version is not ready to use")

	s.T().Log("Disable curated image definition")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId: curatedImageDefinition.Id,
		Name:              curatedImageDefinition.Name,
		Enabled:           false,
	})
	s.Require().NoError(err)

	s.T().Log("GET image details for 'latest' when image definition is disabled")

	s.validateImageDetails(
		&internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinition.Id, Version: "latest"},
		testActor,
		curatedImageDefinition,
		false,
	)

	s.T().Log("GET image details for '1.0.0' when image definition is disabled")

	s.validateImageDetails(
		&internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinition.Id, Version: "1.0.0"},
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

	// This test doesn't cover positive path for GetImageReference method because it requires image in Ready state
	// This test case is covered by ImagesUploadingE2ETestSuite
}

func (s *InternalApiE2ETestSuite) Test_InternalApiForCuratedImagesPointers() {
	var (
		testActor              = &sharedapi.Actor{GlobalId: "test-actor"}
		curatedImageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-internalapi-curatedpointer-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
		}
		curatedImageDefinitionPointer = &adminapi.ImageDefinition{
			Name:    fmt.Sprintf("%s-internalapi-curatedpointer-2", s.uniquePrefix),
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
	})
	s.Require().NoError(err)
	curatedImageDefinition.Id = curatedImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE curated image definition pointer via Admin API")

	curatedImageDefinitionPointerResp, err := s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      curatedImageDefinitionPointer.Name,
		PointsToImageDefinitionId: curatedImageDefinition.Id,
		Enabled:                   curatedImageDefinitionPointer.Enabled,
	})
	s.Require().NoError(err)
	curatedImageDefinitionPointer.Id = curatedImageDefinitionPointerResp.ImageDefinition.Id

	s.T().Log("GET image details for 'latest' using image definition pointer when image definition has no versions")

	s.validateImageDetails(
		&internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinitionPointer.Id, Version: "latest"},
		testActor,
		curatedImageDefinitionPointer,
		true,
	)

	s.T().Log("GET image details for non-existing version using image definition pointer")

	_, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    testActor,
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinitionPointer.Id, Version: "3.0.0"},
	})
	s.Require().ErrorContains(err, "image version is not found")

	s.T().Log("GET image reference for 'latest' using image definition pointer when image definition has no versions")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinitionPointer.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for non-existing version using image definition pointer")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinitionPointer.Id, Version: "3.0.0"},
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
		&internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinitionPointer.Id, Version: "latest"},
		testActor,
		curatedImageDefinitionPointer,
		true,
	)

	s.T().Log("GET image details for '1.0.0' using image definition pointer")

	s.validateImageDetails(
		&internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinitionPointer.Id, Version: "1.0.0"},
		testActor,
		curatedImageDefinitionPointer,
		true,
	)

	s.T().Log("GET image reference for 'latest' using image definition pointer when image definition has at least one version")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinitionPointer.Id, Version: "latest"},
	})
	s.Require().ErrorContains(err, "image definition does not have enabled versions in ready state")

	s.T().Log("GET image reference for specific image version using image definition pointer")

	_, err = s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinitionPointer.Id, Version: "1.0.0"},
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
			FeatureFlag:  string(featureflags.FeatureFlag_E2E_TestFlag_EnabledPerOwner),
		}
	)

	s.T().Log("CREATE curated image definition via Admin API")

	curatedImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         curatedImageDefinitionWithFeatureFlag.Name,
		OsType:       curatedImageDefinitionWithFeatureFlag.OsType,
		Architecture: curatedImageDefinitionWithFeatureFlag.Architecture,
		FeatureFlag:  curatedImageDefinitionWithFeatureFlag.FeatureFlag,
	})
	s.Require().NoError(err)
	curatedImageDefinitionWithFeatureFlag.Id = curatedImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET image details for actor with disabled feature flag")

	imageDetailsResp, err := s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    testActor,
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinitionWithFeatureFlag.Id, Version: "latest"},
	})
	s.Require().NoError(err)
	s.Require().Equal(curatedImageDefinitionWithFeatureFlag.Id, imageDetailsResp.ImageDetails.Id)
	s.Require().Equal(false, imageDetailsResp.ImageDetails.Enabled)

	s.T().Log("GET image details for actor with enabled feature flag")

	imageDetailsResp, err = s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    &sharedapi.Actor{GlobalId: featureflags.FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID},
		ImageKey: &internalapi.ImageKey{Source: "Curated", Id: curatedImageDefinitionWithFeatureFlag.Id, Version: "latest"},
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

func (s *InternalApiE2ETestSuite) validateImageDetails(imageKey *internalapi.ImageKey, actor *sharedapi.Actor, expectedImageDefinition *adminapi.ImageDefinition, expectedEnabled bool) {
	imageDetailsResp, err := s.internalTwirpClient.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:    actor,
		ImageKey: imageKey,
	})
	s.Require().NoError(err)
	s.Require().Equal(expectedImageDefinition.Id, imageDetailsResp.ImageDetails.Id)
	s.Require().Equal(imageKey.Id, imageDetailsResp.ImageDetails.Id)
	s.Require().Equal(imageKey.Source, imageDetailsResp.ImageDetails.Source)
	s.Require().Equal(expectedImageDefinition.Name, imageDetailsResp.ImageDetails.Name)
	s.Require().Equal(expectedImageDefinition.OsType, imageDetailsResp.ImageDetails.OsType)
	s.Require().Equal(expectedImageDefinition.Architecture, imageDetailsResp.ImageDetails.Architecture)
	s.Require().Equal(expectedEnabled, imageDetailsResp.ImageDetails.Enabled)
	s.Require().Equal(int32(0), imageDetailsResp.ImageDetails.SizeGb) // this test suite doesn't upload real images, so size will be 0 always
}
