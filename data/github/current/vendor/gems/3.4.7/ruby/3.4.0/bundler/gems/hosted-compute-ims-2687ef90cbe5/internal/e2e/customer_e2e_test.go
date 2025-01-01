package e2e

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/wrapperspb"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
)

type CustomerImagesE2ETestSuite struct {
	BaseE2ETestSuite
}

func TestCustomerImagesE2ETestSuite(t *testing.T) {
	// tests within suite will run in sequential order unless t.Parallel() is called within individual tests
	// for now, only suites will run in parallel
	t.Parallel()
	suite.Run(t, new(CustomerImagesE2ETestSuite))
}

func (s *CustomerImagesE2ETestSuite) Test_CreateImageDefinitionsAndVersions() {
	var (
		imageOwner           = &sharedapi.Actor{GlobalId: fmt.Sprintf("O_%s_customer_create", s.uniquePrefix)}
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
		addedImageVersions  = []string{"7.0.0", "13.0.1", "4.2.1", "7.0.1"}
		sortedImageVersions = []string{"13.0.1", "7.0.1", "7.0.0", "4.2.1"}
	)

	s.T().Log("CREATE image definition with RunnerGroupId via Customer API")

	createImageDefinitionResp, err := s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:         imageOwner,
		Name:          addedImageDefinition.Name,
		OsType:        addedImageDefinition.OsType,
		Architecture:  addedImageDefinition.Architecture,
		RunnerGroupId: wrapperspb.UInt64(uint64(1)),
	})
	s.Require().NoError(err)
	addedImageDefinition.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET image definition with RunnerGroupId via Customer API")

	getImageDefinitionResp, err := s.customerTwirpClient.GetCustomerImageDefinition(s.ctx, &imagesapi.GetCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(addedImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(addedImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(addedImageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(addedImageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.TotalImageVersionsSizeGb)
	s.Require().Equal("", getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(uint64(1), getImageDefinitionResp.ImageDefinition.RunnerGroupId.Value)

	s.T().Log("CREATE image definition without RunnerGroupId via Customer API")

	createImageDefinitionResp, err = s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:        imageOwner,
		Name:         addedImageDefinition2.Name,
		OsType:       addedImageDefinition2.OsType,
		Architecture: addedImageDefinition2.Architecture,
	})
	s.Require().NoError(err)
	addedImageDefinition2.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET image definition without RunnerGroupId via Customer API")

	getImageDefinitionResp, err = s.customerTwirpClient.GetCustomerImageDefinition(s.ctx, &imagesapi.GetCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition2.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(addedImageDefinition2.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(addedImageDefinition2.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(addedImageDefinition2.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(addedImageDefinition2.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.TotalImageVersionsSizeGb)
	s.Require().Equal("", getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Nil(getImageDefinitionResp.ImageDefinition.RunnerGroupId)

	s.T().Log("LIST image definitions via Customer API")

	listImageDefinitionsResp, err := s.customerTwirpClient.ListCustomerImageDefinitions(s.ctx, &imagesapi.ListCustomerImageDefinitionsRequest{
		Owner: imageOwner,
	})
	s.Require().NoError(err)
	s.Require().Equal(2, len(listImageDefinitionsResp.ImageDefinitions))
	s.Require().Equal(addedImageDefinition.Id, listImageDefinitionsResp.ImageDefinitions[0].Id)
	s.Require().Equal(addedImageDefinition.Name, listImageDefinitionsResp.ImageDefinitions[0].Name)
	s.Require().Equal(addedImageDefinition.OsType, listImageDefinitionsResp.ImageDefinitions[0].OsType)
	s.Require().Equal(addedImageDefinition.Architecture, listImageDefinitionsResp.ImageDefinitions[0].Architecture)
	s.Require().Equal(int32(0), listImageDefinitionsResp.ImageDefinitions[0].ImageVersionsCount)
	s.Require().Equal(int32(0), listImageDefinitionsResp.ImageDefinitions[0].TotalImageVersionsSizeGb)
	s.Require().Equal("", listImageDefinitionsResp.ImageDefinitions[0].LatestVersion)
	s.Require().Equal(int32(0), listImageDefinitionsResp.ImageDefinitions[0].LatestVersionSizeGb)

	s.T().Log("CREATE multiple image versions via Customer API")

	for _, version := range addedImageVersions {
		_, err = s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{
			Owner:             imageOwner,
			ImageDefinitionId: addedImageDefinition.Id,
			Version:           version,
			SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
		})
		s.Require().NoError(err)
	}

	for _, version := range addedImageVersions {
		s.waitForCustomerImageVersionProvisionFailed(imageOwner, addedImageDefinition.Id, version)
	}

	s.T().Log("GET image versions via Customer API")

	for _, version := range addedImageVersions {
		getImageVersionResp, err := s.customerTwirpClient.GetCustomerImageVersion(s.ctx, &imagesapi.GetCustomerImageVersionRequest{
			Owner:             imageOwner,
			ImageDefinitionId: addedImageDefinition.Id,
			Version:           version,
		})
		s.Require().NoError(err)
		s.Require().Equal(version, getImageVersionResp.ImageVersion.Version)
	}

	s.T().Log("LIST image versions via Customer API")

	listImageVersionsResp, err := s.customerTwirpClient.ListCustomerImageVersions(s.ctx, &imagesapi.ListCustomerImageVersionsRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(len(sortedImageVersions), len(listImageVersionsResp.ImageVersions))
	for ind := 0; ind < len(sortedImageVersions); ind++ {
		s.Require().Equal(sortedImageVersions[ind], listImageVersionsResp.ImageVersions[ind].Version)
	}

	s.T().Log("GET image definition via Customer API with image versions metadata")

	getImageDefinitionResp, err = s.customerTwirpClient.GetCustomerImageDefinition(s.ctx, &imagesapi.GetCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(addedImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(addedImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(addedImageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(addedImageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(int32(4), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.TotalImageVersionsSizeGb)
	s.Require().Equal("", getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)

	s.T().Log("LIST image definition via Customer API with image versions metadata")

	listImageDefinitionsResp, err = s.customerTwirpClient.ListCustomerImageDefinitions(s.ctx, &imagesapi.ListCustomerImageDefinitionsRequest{
		Owner: imageOwner,
	})
	s.Require().NoError(err)
	s.Require().Equal(2, len(listImageDefinitionsResp.ImageDefinitions))
	s.Require().Equal(addedImageDefinition.Id, listImageDefinitionsResp.ImageDefinitions[0].Id)
	s.Require().Equal(addedImageDefinition.Name, listImageDefinitionsResp.ImageDefinitions[0].Name)
	s.Require().Equal(addedImageDefinition.OsType, listImageDefinitionsResp.ImageDefinitions[0].OsType)
	s.Require().Equal(addedImageDefinition.Architecture, listImageDefinitionsResp.ImageDefinitions[0].Architecture)
	s.Require().Equal(int32(4), listImageDefinitionsResp.ImageDefinitions[0].ImageVersionsCount)
	s.Require().Equal(int32(0), listImageDefinitionsResp.ImageDefinitions[0].TotalImageVersionsSizeGb)
	s.Require().Equal("", listImageDefinitionsResp.ImageDefinitions[0].LatestVersion)
	s.Require().Equal(int32(0), listImageDefinitionsResp.ImageDefinitions[0].LatestVersionSizeGb)

	s.T().Log("DELETE image versions via Customer API")

	for _, version := range sortedImageVersions {
		deleteImageVersionResponse, err := s.customerTwirpClient.DeleteCustomerImageVersion(s.ctx, &imagesapi.DeleteCustomerImageVersionRequest{
			Owner:             imageOwner,
			ImageDefinitionId: addedImageDefinition.Id,
			Version:           version,
		})
		s.Require().NoError(err)
		s.Require().NotNil(deleteImageVersionResponse)
		s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)
	}

	for _, version := range sortedImageVersions {
		s.waitForCustomerImageVersionDeletion(imageOwner, addedImageDefinition.Id, version)
	}

	s.T().Log("DELETE image definitions with RunnerGroupId via Customer API")

	deleteImageDefinitionResponse, err := s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageDefinitionResponse)
	s.Require().Equal(sharedapi.ImageDefinitionState_ImageDefinitionDeleting, deleteImageDefinitionResponse.ImageDefinition.State)

	s.T().Log("Wait for image definition deletion via Customer API")

	s.waitForCustomerImageDefinitionDeletion(imageOwner, addedImageDefinition.Id)
	s.Require().NoError(err)

	s.T().Log("DELETE image definitions without RunnerGroupId via Customer API")

	deleteImageDefinitionResponse, err = s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition2.Id,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageDefinitionResponse)
	s.Require().Equal(sharedapi.ImageDefinitionState_ImageDefinitionDeleting, deleteImageDefinitionResponse.ImageDefinition.State)

	s.T().Log("Wait for image definition deletion via Customer API")

	s.waitForCustomerImageDefinitionDeletion(imageOwner, addedImageDefinition2.Id)
	s.Require().NoError(err)

	s.T().Log("LIST image definitions via Customer API")

	listImageDefinitionsResp, err = s.customerTwirpClient.ListCustomerImageDefinitions(s.ctx, &imagesapi.ListCustomerImageDefinitionsRequest{
		Owner: imageOwner,
	})
	s.Require().NoError(err)
	s.Require().Equal(0, len(listImageDefinitionsResp.ImageDefinitions))
}

func (s *CustomerImagesE2ETestSuite) Test_UpdateImageDefinitionsAndVersions() {
	var (
		imageOwner           = &sharedapi.Actor{GlobalId: fmt.Sprintf("O_%s_customer_update", s.uniquePrefix)}
		addedImageDefinition = &imagesapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}
		newImageDefinitionName = fmt.Sprintf("%s-def-2", s.uniquePrefix)
	)

	s.T().Log("CREATE image definition via Customer API")

	createImageDefinitionResp, err := s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:         imageOwner,
		Name:          addedImageDefinition.Name,
		OsType:        addedImageDefinition.OsType,
		Architecture:  addedImageDefinition.Architecture,
		RunnerGroupId: wrapperspb.UInt64(uint64(3)),
	})
	s.Require().NoError(err)
	addedImageDefinition.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET image definition via Customer API")

	getImageDefinitionResp, err := s.customerTwirpClient.GetCustomerImageDefinition(s.ctx, &imagesapi.GetCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(addedImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(addedImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(addedImageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(addedImageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.TotalImageVersionsSizeGb)

	s.T().Log("UPDATE image definition via Customer API")

	_, err = s.customerTwirpClient.UpdateCustomerImageDefinition(s.ctx, &imagesapi.UpdateCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
		Name:              wrapperspb.String(newImageDefinitionName),
	})
	s.Require().NoError(err)

	s.T().Log("UPDATE image definition with RunnerGroupId via Customer API")

	_, err = s.customerTwirpClient.UpdateCustomerImageDefinition(s.ctx, &imagesapi.UpdateCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
		RunnerGroupId:     wrapperspb.UInt64(uint64(2)),
	})
	s.Require().NoError(err)

	s.T().Log("GET image definition via Customer API")

	getImageDefinitionResp, err = s.customerTwirpClient.GetCustomerImageDefinition(s.ctx, &imagesapi.GetCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(addedImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(newImageDefinitionName, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(addedImageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(addedImageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.TotalImageVersionsSizeGb)
	s.Require().Equal(uint64(2), getImageDefinitionResp.ImageDefinition.RunnerGroupId.Value)

	s.T().Log("DELETE image definitions via Customer API")

	deleteImageDefinitionResponse, err := s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: addedImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageDefinitionResponse)
	s.Require().Equal(sharedapi.ImageDefinitionState_ImageDefinitionDeleting, deleteImageDefinitionResponse.ImageDefinition.State)

	s.T().Log("Wait for image definition deletion via Customer API")

	s.waitForCustomerImageDefinitionDeletion(imageOwner, addedImageDefinition.Id)
	s.Require().NoError(err)
}

func (s *CustomerImagesE2ETestSuite) Test_MultipleOwners() {
	var (
		imageOwner1             = &sharedapi.Actor{GlobalId: fmt.Sprintf("O_%s_customer_multiowner_owner1", s.uniquePrefix)}
		imageOwner2             = &sharedapi.Actor{GlobalId: fmt.Sprintf("O_%s_customer_multiowner_owner2", s.uniquePrefix)}
		imageDefinitionOfOwner1 = &imagesapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}
		imageDefinitionOfOwner2 = &imagesapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
		}
		imageVersionOfOwner1 = "1.0.0"
		imageVersionOfOwner2 = "2.0.0"
	)

	s.T().Log("CREATE image definition for owner 1")

	createImageDefinitionResp, err := s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:         imageOwner1,
		Name:          imageDefinitionOfOwner1.Name,
		OsType:        imageDefinitionOfOwner1.OsType,
		Architecture:  imageDefinitionOfOwner1.Architecture,
		RunnerGroupId: wrapperspb.UInt64(uint64(2)),
	})
	s.Require().NoError(err)
	imageDefinitionOfOwner1.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE image definition for owner 2")

	createImageDefinitionResp, err = s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:         imageOwner2,
		Name:          imageDefinitionOfOwner2.Name,
		OsType:        imageDefinitionOfOwner2.OsType,
		Architecture:  imageDefinitionOfOwner2.Architecture,
		RunnerGroupId: wrapperspb.UInt64(uint64(3)),
	})
	s.Require().NoError(err)
	imageDefinitionOfOwner2.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE image versions for both owners")

	_, err = s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{
		Owner:             imageOwner1,
		ImageDefinitionId: imageDefinitionOfOwner1.Id,
		Version:           imageVersionOfOwner1,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().NoError(err)

	_, err = s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{
		Owner:             imageOwner2,
		ImageDefinitionId: imageDefinitionOfOwner2.Id,
		Version:           imageVersionOfOwner2,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().NoError(err)

	s.waitForCustomerImageVersionProvisionFailed(imageOwner1, imageDefinitionOfOwner1.Id, imageVersionOfOwner1)
	s.waitForCustomerImageVersionProvisionFailed(imageOwner2, imageDefinitionOfOwner2.Id, imageVersionOfOwner2)

	s.T().Log("LIST image definitions")

	listImageDefinitionsResp, err := s.customerTwirpClient.ListCustomerImageDefinitions(s.ctx, &imagesapi.ListCustomerImageDefinitionsRequest{
		Owner: imageOwner1,
	})
	s.Require().NoError(err)
	s.Require().Equal(1, len(listImageDefinitionsResp.ImageDefinitions))
	s.Require().Equal(imageDefinitionOfOwner1.Id, listImageDefinitionsResp.ImageDefinitions[0].Id)

	listImageDefinitionsResp, err = s.customerTwirpClient.ListCustomerImageDefinitions(s.ctx, &imagesapi.ListCustomerImageDefinitionsRequest{
		Owner: imageOwner2,
	})
	s.Require().NoError(err)
	s.Require().Equal(1, len(listImageDefinitionsResp.ImageDefinitions))
	s.Require().Equal(imageDefinitionOfOwner2.Id, listImageDefinitionsResp.ImageDefinitions[0].Id)

	s.T().Log("GET image definition with incorrect owner")

	_, err = s.customerTwirpClient.GetCustomerImageDefinition(s.ctx, &imagesapi.GetCustomerImageDefinitionRequest{
		Owner:             imageOwner1,
		ImageDefinitionId: imageDefinitionOfOwner2.Id,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	_, err = s.customerTwirpClient.GetCustomerImageDefinition(s.ctx, &imagesapi.GetCustomerImageDefinitionRequest{
		Owner:             imageOwner2,
		ImageDefinitionId: imageDefinitionOfOwner1.Id,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("LIST image versions with incorrect owner")

	_, err = s.customerTwirpClient.ListCustomerImageVersions(s.ctx, &imagesapi.ListCustomerImageVersionsRequest{
		Owner:             imageOwner1,
		ImageDefinitionId: imageDefinitionOfOwner2.Id,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	_, err = s.customerTwirpClient.ListCustomerImageVersions(s.ctx, &imagesapi.ListCustomerImageVersionsRequest{
		Owner:             imageOwner2,
		ImageDefinitionId: imageDefinitionOfOwner1.Id,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image version with incorrect owner")

	_, err = s.customerTwirpClient.GetCustomerImageVersion(s.ctx, &imagesapi.GetCustomerImageVersionRequest{
		Owner:             imageOwner1,
		ImageDefinitionId: imageDefinitionOfOwner1.Id,
		Version:           imageVersionOfOwner2,
	})
	s.Require().ErrorContains(err, "image version is not found")

	_, err = s.customerTwirpClient.GetCustomerImageVersion(s.ctx, &imagesapi.GetCustomerImageVersionRequest{
		Owner:             imageOwner1,
		ImageDefinitionId: imageDefinitionOfOwner2.Id,
		Version:           imageVersionOfOwner1,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	_, err = s.customerTwirpClient.GetCustomerImageVersion(s.ctx, &imagesapi.GetCustomerImageVersionRequest{
		Owner:             imageOwner2,
		ImageDefinitionId: imageDefinitionOfOwner1.Id,
		Version:           imageVersionOfOwner1,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("CREATE image version with incorrect owner")

	_, err = s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{
		Owner:             imageOwner1,
		ImageDefinitionId: imageDefinitionOfOwner2.Id,
		Version:           "5.0.0",
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("DELETE image version with incorrect owner")

	_, err = s.customerTwirpClient.DeleteCustomerImageVersion(s.ctx, &imagesapi.DeleteCustomerImageVersionRequest{
		Owner:             imageOwner1,
		ImageDefinitionId: imageDefinitionOfOwner2.Id,
		Version:           imageVersionOfOwner1,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("DELETE image versions")

	deleteImageVersionResponse, err := s.customerTwirpClient.DeleteCustomerImageVersion(s.ctx, &imagesapi.DeleteCustomerImageVersionRequest{
		Owner:             imageOwner1,
		ImageDefinitionId: imageDefinitionOfOwner1.Id,
		Version:           imageVersionOfOwner1,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageVersionResponse)
	s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)

	deleteImageVersionResponse, err = s.customerTwirpClient.DeleteCustomerImageVersion(s.ctx, &imagesapi.DeleteCustomerImageVersionRequest{
		Owner:             imageOwner2,
		ImageDefinitionId: imageDefinitionOfOwner2.Id,
		Version:           imageVersionOfOwner2,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageVersionResponse)
	s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)

	s.waitForCustomerImageVersionDeletion(imageOwner1, imageDefinitionOfOwner1.Id, imageVersionOfOwner1)
	s.waitForCustomerImageVersionDeletion(imageOwner2, imageDefinitionOfOwner2.Id, imageVersionOfOwner2)

	s.T().Log("DELETE image definitions")

	deleteImageDefinitionResponse, err := s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             imageOwner1,
		ImageDefinitionId: imageDefinitionOfOwner1.Id,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageDefinitionResponse)
	s.Require().Equal(sharedapi.ImageDefinitionState_ImageDefinitionDeleting, deleteImageDefinitionResponse.ImageDefinition.State)

	deleteImageDefinitionResponse, err = s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             imageOwner2,
		ImageDefinitionId: imageDefinitionOfOwner2.Id,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageDefinitionResponse)
	s.Require().Equal(sharedapi.ImageDefinitionState_ImageDefinitionDeleting, deleteImageDefinitionResponse.ImageDefinition.State)

	s.T().Log("Wait for image definitions deletion via Customer API")

	s.waitForCustomerImageDefinitionDeletion(imageOwner1, imageDefinitionOfOwner1.Id)
	s.Require().NoError(err)

	s.waitForCustomerImageDefinitionDeletion(imageOwner2, imageDefinitionOfOwner2.Id)
	s.Require().NoError(err)
}

func (s *CustomerImagesE2ETestSuite) Test_Validations() {
	var (
		imageOwner                 = &sharedapi.Actor{GlobalId: fmt.Sprintf("O_%s_customer_validate", s.uniquePrefix)}
		invalidImageDefinitionName = fmt.Sprintf("%s Invalid Name", s.uniquePrefix)
		validImageDefinitionName   = fmt.Sprintf("%s-curated-validation-def-1", s.uniquePrefix)
	)

	s.T().Log("CREATE image definition without name and owner id")

	_, err := s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
	})
	s.Require().ErrorContains(err, "owner: value is required")
	s.Require().ErrorContains(err, "name: value is required")

	s.T().Log("CREATE image definition with invalid name")

	_, err = s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:        imageOwner,
		Name:         invalidImageDefinitionName,
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
	})
	s.Require().ErrorContains(err, "name: value does not match regex pattern")

	s.T().Log("CREATE image definition with correct params")

	createImageDefinitionResp, err := s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:         imageOwner,
		Name:          validImageDefinitionName,
		OsType:        sharedapi.OsType_Linux,
		Architecture:  sharedapi.Architecture_X64,
		RunnerGroupId: wrapperspb.UInt64(uint64(3)),
	})
	s.Require().NoError(err)

	s.T().Log("CREATE image definition with existing name")

	_, err = s.customerTwirpClient.CreateCustomerImageDefinition(s.ctx, &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:         imageOwner,
		Name:          validImageDefinitionName,
		OsType:        sharedapi.OsType_Linux,
		Architecture:  sharedapi.Architecture_X64,
		RunnerGroupId: wrapperspb.UInt64(uint64(3)),
	})
	s.Require().ErrorContains(err, "image definition with this name already exists")

	s.T().Log("UPDATE image definition name without owner id, image definition id and name")

	_, err = s.customerTwirpClient.UpdateCustomerImageDefinition(s.ctx, &imagesapi.UpdateCustomerImageDefinitionRequest{})
	s.Require().ErrorContains(err, "owner: value is required")
	s.Require().ErrorContains(err, "image_definition_id: value is required")

	s.T().Log("UPDATE image definition name to invalid")

	_, err = s.customerTwirpClient.UpdateCustomerImageDefinition(s.ctx, &imagesapi.UpdateCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Name:              wrapperspb.String(invalidImageDefinitionName),
	})
	s.Require().ErrorContains(err, "name: value does not match regex pattern")

	s.T().Log("UPDATE image definition via Admin API")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Name:              validImageDefinitionName,
		Enabled:           false,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("CREATE image version without owner id, image definition id, version, source vhd url")

	_, err = s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{})
	s.Require().ErrorContains(err, "owner: value is required")
	s.Require().ErrorContains(err, "image_definition_id: value is required")
	s.Require().ErrorContains(err, "source_vhd_url: value is required")

	s.T().Log("CREATE curated image version with invalid version format")

	_, err = s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.x.d",
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().ErrorContains(err, "version: value does not match regex pattern")

	s.T().Log("CREATE curated image version with invalid source vhd url")

	_, err = s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
		SourceVhdUrl:      "www.github.com/invalid url/",
	})
	s.Require().ErrorContains(err, "source_vhd_url: value must be a valid URI")

	s.T().Log("CREATE customer image version via Admin API")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("CREATE image version with correct params via Customer API")

	_, err = s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().NoError(err)

	s.waitForCustomerImageVersionProvisionFailed(imageOwner, createImageDefinitionResp.ImageDefinition.Id, "1.2.3")

	s.T().Log("CREATE image version with existing version")

	_, err = s.customerTwirpClient.CreateCustomerImageVersion(s.ctx, &imagesapi.CreateCustomerImageVersionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().ErrorContains(err, "image version with this version already exists")

	s.T().Log("DELETE customer image version via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("DELETE customer image version via Customer API")

	deleteImageVersionResponse, err := s.customerTwirpClient.DeleteCustomerImageVersion(s.ctx, &imagesapi.DeleteCustomerImageVersionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageVersionResponse)
	s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)

	s.waitForCustomerImageVersionDeletion(imageOwner, createImageDefinitionResp.ImageDefinition.Id, "1.2.3")

	s.T().Log("DELETE customer image definition via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("DELETE customer image definition via Customer API")

	deleteImageDefinitionResponse, err := s.customerTwirpClient.DeleteCustomerImageDefinition(s.ctx, &imagesapi.DeleteCustomerImageDefinitionRequest{
		Owner:             imageOwner,
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageDefinitionResponse)
	s.Require().Equal(sharedapi.ImageDefinitionState_ImageDefinitionDeleting, deleteImageDefinitionResponse.ImageDefinition.State)

	s.T().Log("Wait for image definition deletion via Customer API")

	s.waitForCustomerImageDefinitionDeletion(imageOwner, createImageDefinitionResp.ImageDefinition.Id)
	s.Require().NoError(err)
}
