package e2e

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/suite"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
)

type CuratedLatestImagesE2ETestSuite struct {
	BaseE2ETestSuite
}

func TestCuratedLatestImagesE2ETestSuite(t *testing.T) {
	t.Parallel()
	suite.Run(t, new(CuratedLatestImagesE2ETestSuite))
}

func (s *CuratedLatestImagesE2ETestSuite) Test_ImageDefinitionPointersForGitHubOwner() {
	var (
		imageDefinitionWithVersions = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-ptr-create-def-1", s.uniquePrefix),
			OwnerId:      models.GithubOwnerId,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
		}
		imageDefinitionWithoutVersions = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-ptr-create-def-2", s.uniquePrefix),
			OwnerId:      models.GithubOwnerId,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
		}
		pointerImageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-ptr-create-pointer", s.uniquePrefix),
			OwnerId:      models.GithubOwnerId,
			Enabled:      true,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			State:        sharedapi.ImageDefinitionState_ImageDefinitionReady,
		}
		imageVersion = "1.0.0"
		user         = &sharedapi.Actor{GlobalId: "user-1"}
	)
	s.T().Log("CREATE curated image definition 1 via Admin API")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinitionWithVersions.Name,
		OwnerId:      imageDefinitionWithVersions.OwnerId,
		OsType:       imageDefinitionWithVersions.OsType,
		Architecture: imageDefinitionWithVersions.Architecture,
		Enabled:      imageDefinitionWithVersions.Enabled,
	})
	s.Require().NoError(err)
	imageDefinitionWithVersions.Id = createImageDefinitionResp.ImageDefinition.Id
	pointerImageDefinition.PointsToImageDefinitionId = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE curated image definition pointer 1 via Admin API")

	createCuratedImageDefinitionPointerResp, err := s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      pointerImageDefinition.Name,
		OwnerId:                   pointerImageDefinition.OwnerId,
		Enabled:                   pointerImageDefinition.Enabled,
		PointsToImageDefinitionId: pointerImageDefinition.PointsToImageDefinitionId,
	})
	pointerImageDefinition.Id = createCuratedImageDefinitionPointerResp.ImageDefinition.Id
	s.Require().NoError(err)

	s.T().Log("CREATE image version for image definition 1 via Admin API")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinitionWithVersions.Id,
		Version:           imageVersion,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
		Enabled:           true,
	})
	s.Require().NoError(err)

	s.T().Log("GET image definition pointer via Admin API")

	getAdminImageDefinitionResp, err := s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(pointerImageDefinition.Id, getAdminImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(pointerImageDefinition.Name, getAdminImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(pointerImageDefinition.OwnerId, getAdminImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal(pointerImageDefinition.OsType, getAdminImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(pointerImageDefinition.Architecture, getAdminImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(pointerImageDefinition.Enabled, getAdminImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(pointerImageDefinition.State, getAdminImageDefinitionResp.ImageDefinition.State)
	s.Require().Equal("", getAdminImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getAdminImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(int32(0), getAdminImageDefinitionResp.ImageDefinition.ImageVersionsCount)

	s.T().Log("LIST image definition pointer via Admin API")

	listAdminImageDefinitionResp, err := s.adminTwirpClient.ListCuratedImageDefinitions(s.ctx, &adminapi.ListCuratedImageDefinitionsRequest{})
	s.Require().NoError(err)
	listedAdminImageDefinitions := utils.FilterFunc(s.filterTestCuratedImageDefinitions(listAdminImageDefinitionResp.ImageDefinitions), func(imDef *adminapi.ImageDefinition) bool { return imDef.PointsToImageDefinitionId > 0 })
	s.Require().Equal(1, len(listedAdminImageDefinitions))
	s.Require().Equal(pointerImageDefinition.Id, listedAdminImageDefinitions[0].Id)
	s.Require().Equal(pointerImageDefinition.Name, listedAdminImageDefinitions[0].Name)
	s.Require().Equal(pointerImageDefinition.OwnerId, listedAdminImageDefinitions[0].OwnerId)
	s.Require().Equal(pointerImageDefinition.OsType, listedAdminImageDefinitions[0].OsType)
	s.Require().Equal(pointerImageDefinition.Architecture, listedAdminImageDefinitions[0].Architecture)
	s.Require().Equal(pointerImageDefinition.Enabled, listedAdminImageDefinitions[0].Enabled)
	s.Require().Equal(pointerImageDefinition.State, listedAdminImageDefinitions[0].State)
	s.Require().Equal("", listedAdminImageDefinitions[0].LatestVersion)
	s.Require().Equal(int32(0), listedAdminImageDefinitions[0].LatestVersionSizeGb)
	s.Require().Equal(int32(0), listedAdminImageDefinitions[0].ImageVersionsCount)

	s.T().Log("GET image definition pointer via Customer API")

	getImageDefinitionResp, err := s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             user,
		ImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(pointerImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(pointerImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(pointerImageDefinition.OwnerId, getImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal(pointerImageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(pointerImageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(pointerImageDefinition.Enabled, getImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(pointerImageDefinition.State, getImageDefinitionResp.ImageDefinition.State)
	s.Require().Equal("", getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)

	s.T().Log("LIST image definition pointer via Customer API")

	listImageDefinitionResp, err := s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{Owner: user})
	s.Require().NoError(err)
	listedImageDefinitions := utils.FilterFunc(s.filterTestCustomerImageDefinitions(listImageDefinitionResp.ImageDefinitions), func(imDef *imagesapi.ImageDefinition) bool { return imDef.Id == pointerImageDefinition.Id })
	s.Require().Equal(1, len(listedImageDefinitions))
	s.Require().Equal(pointerImageDefinition.Id, listedImageDefinitions[0].Id)
	s.Require().Equal(pointerImageDefinition.Name, listedImageDefinitions[0].Name)
	s.Require().Equal(pointerImageDefinition.OwnerId, listedImageDefinitions[0].OwnerId)
	s.Require().Equal(pointerImageDefinition.OsType, listedImageDefinitions[0].OsType)
	s.Require().Equal(pointerImageDefinition.Architecture, listedImageDefinitions[0].Architecture)
	s.Require().Equal(pointerImageDefinition.Enabled, listedImageDefinitions[0].Enabled)
	s.Require().Equal(pointerImageDefinition.State, listedImageDefinitions[0].State)
	s.Require().Equal("", listedImageDefinitions[0].LatestVersion)
	s.Require().Equal(int32(0), listedImageDefinitions[0].LatestVersionSizeGb)
	s.Require().Equal(int32(0), listedImageDefinitions[0].ImageVersionsCount)

	s.T().Log("GET image version for image definition pointer via Customer API")

	getImageVersionResp, err := s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
		Owner:             user,
		ImageDefinitionId: pointerImageDefinition.Id,
		Version:           imageVersion,
	})
	s.Require().NoError(err)
	s.Require().Equal(imageVersion, getImageVersionResp.ImageVersion.Version)

	s.T().Log("LIST image versions for image definition pointer via Customer API")

	listImageVersionsForPointerResp, err := s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             user,
		ImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(1, len(listImageVersionsForPointerResp.ImageVersions))
	s.Require().Equal(imageVersion, listImageVersionsForPointerResp.ImageVersions[0].Version)

	s.T().Log("CREATE curated image definition 2 via Admin API")

	createImageDefinitionResp, err = s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinitionWithoutVersions.Name,
		OsType:       imageDefinitionWithoutVersions.OsType,
		Architecture: imageDefinitionWithoutVersions.Architecture,
		Enabled:      imageDefinitionWithoutVersions.Enabled,
		OwnerId:      imageDefinitionWithoutVersions.OwnerId,
	})
	s.Require().NoError(err)
	imageDefinitionWithoutVersions.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("UPDATE curated image definition pointer 1 via Admin API")

	updateImageDefinitionResp, err := s.adminTwirpClient.UpdateCuratedImageDefinitionPointer(s.ctx, &adminapi.UpdateCuratedImageDefinitionPointerRequest{
		ImageDefinitionId:         pointerImageDefinition.Id,
		Name:                      pointerImageDefinition.Name,
		Enabled:                   pointerImageDefinition.Enabled,
		PointsToImageDefinitionId: imageDefinitionWithoutVersions.Id,
	})
	s.Require().NoError(err)
	pointerImageDefinition.PointsToImageDefinitionId = updateImageDefinitionResp.ImageDefinition.PointsToImageDefinitionId

	s.T().Log("LIST image versions after update pointer to image definition 2 via Customer API")

	listImageVersionsForPointerResp, err = s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             user,
		ImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(0, len(listImageVersionsForPointerResp.ImageVersions))

	s.T().Log("DELETE curated image definition pointer 1 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image version for image definition 1 via Admin API")

	s.waitForAdminImageVersionProvisionFailed(imageDefinitionWithVersions.Id, imageVersion)

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinitionWithVersions.Id,
		Version:           imageVersion,
	})
	s.Require().NoError(err)

	s.waitForAdminImageVersionDeletion(imageDefinitionWithVersions.Id, imageVersion)

	s.T().Log("DELETE curated image definition 1 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitionWithVersions.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image definition 2 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitionWithoutVersions.Id,
	})
	s.Require().NoError(err)
}

func (s *CuratedLatestImagesE2ETestSuite) Test_ImageDefinitionPointersForPartnerOwner() {
	var (
		imageDefinitionWithVersions = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-ptr-create-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
			OwnerId:      models.PartnerOwnerId,
		}
		imageDefinitionWithoutVersions = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-ptr-create-def-2", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
			OwnerId:      models.PartnerOwnerId,
		}
		pointerImageDefinition = &adminapi.ImageDefinition{
			Name:    fmt.Sprintf("%s-curated-ptr-create-pointer", s.uniquePrefix),
			OwnerId: models.PartnerOwnerId,
			Enabled: true,
		}
		imageVersion = "1.0.0"
		user         = &sharedapi.Actor{GlobalId: "user-1"}
	)
	s.T().Log("CREATE curated image definition 1 via Admin API")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinitionWithVersions.Name,
		OsType:       imageDefinitionWithVersions.OsType,
		Architecture: imageDefinitionWithVersions.Architecture,
		Enabled:      imageDefinitionWithVersions.Enabled,
		OwnerId:      imageDefinitionWithVersions.OwnerId,
	})
	s.Require().NoError(err)
	imageDefinitionWithVersions.Id = createImageDefinitionResp.ImageDefinition.Id
	pointerImageDefinition.PointsToImageDefinitionId = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE curated image definition pointer 1 via Admin API")

	createCuratedImageDefinitionPointerResp, err := s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      pointerImageDefinition.Name,
		OwnerId:                   pointerImageDefinition.OwnerId,
		Enabled:                   pointerImageDefinition.Enabled,
		PointsToImageDefinitionId: pointerImageDefinition.PointsToImageDefinitionId,
	})
	pointerImageDefinition.Id = createCuratedImageDefinitionPointerResp.ImageDefinition.Id
	s.Require().NoError(err)

	s.T().Log("CREATE image version for image definition 1 via Admin API")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinitionWithVersions.Id,
		Version:           imageVersion,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
		Enabled:           true,
	})
	s.Require().NoError(err)

	s.T().Log("GET image version for image definition pointer via Customer API")

	getImageVersionResp, err := s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
		Owner:             user,
		ImageDefinitionId: pointerImageDefinition.Id,
		Version:           imageVersion,
	})
	s.Require().NoError(err)
	s.Require().Equal(imageVersion, getImageVersionResp.ImageVersion.Version)

	s.T().Log("LIST image versions for image definition pointer via Customer API")

	listImageVersionsForPointerResp, err := s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             user,
		ImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(1, len(listImageVersionsForPointerResp.ImageVersions))
	s.Require().Equal(imageVersion, listImageVersionsForPointerResp.ImageVersions[0].Version)

	s.T().Log("CREATE curated image definition 2 via Admin API")

	createImageDefinitionResp, err = s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinitionWithoutVersions.Name,
		OsType:       imageDefinitionWithoutVersions.OsType,
		Architecture: imageDefinitionWithoutVersions.Architecture,
		Enabled:      imageDefinitionWithoutVersions.Enabled,
		OwnerId:      imageDefinitionWithoutVersions.OwnerId,
	})
	s.Require().NoError(err)
	imageDefinitionWithoutVersions.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("UPDATE curated image definition pointer 1 via Admin API")

	updateImageDefinitionResp, err := s.adminTwirpClient.UpdateCuratedImageDefinitionPointer(s.ctx, &adminapi.UpdateCuratedImageDefinitionPointerRequest{
		ImageDefinitionId:         pointerImageDefinition.Id,
		Name:                      pointerImageDefinition.Name,
		Enabled:                   pointerImageDefinition.Enabled,
		PointsToImageDefinitionId: imageDefinitionWithoutVersions.Id,
	})
	s.Require().NoError(err)
	pointerImageDefinition.PointsToImageDefinitionId = updateImageDefinitionResp.ImageDefinition.PointsToImageDefinitionId

	s.T().Log("LIST image versions after update pointer to image definition 2 via Admin API")

	listImageVersionsForPointerResp, err = s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             user,
		ImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(0, len(listImageVersionsForPointerResp.ImageVersions))

	s.T().Log("DELETE curated image definition pointer 1 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image version for image definition 1 via Admin API")

	s.waitForAdminImageVersionProvisionFailed(imageDefinitionWithVersions.Id, imageVersion)

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinitionWithVersions.Id,
		Version:           imageVersion,
	})
	s.Require().NoError(err)

	s.waitForAdminImageVersionDeletion(imageDefinitionWithVersions.Id, imageVersion)

	s.T().Log("DELETE curated image definition 1 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitionWithVersions.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image definition 2 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitionWithoutVersions.Id,
	})
	s.Require().NoError(err)
}

func (s *CuratedLatestImagesE2ETestSuite) Test_Validations() {
	var (
		imageDefinitionWithVersions = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-validation-ptr-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
			OwnerId:      models.GithubOwnerId,
		}
		imageDefinitionWithoutVersions = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-validation-ptr-def-2", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
			OwnerId:      models.GithubOwnerId,
		}
		pointerImageDefinitionWithGitHubOwner = &adminapi.ImageDefinition{
			Name:    fmt.Sprintf("%s-curated-validation-ptr-def-4", s.uniquePrefix),
			OwnerId: models.GithubOwnerId,
			Enabled: true,
		}
		pointerImageDefinitionWithPartnerOwner = &adminapi.ImageDefinition{
			Name:    fmt.Sprintf("%s-curated-validation-ptr-def-5", s.uniquePrefix),
			OwnerId: models.PartnerOwnerId,
			Enabled: true,
		}
		validImageDefinitionName   = fmt.Sprintf("%s-curated-validation-ptr-def-5 Ubuntu Latest (22.04) ", s.uniquePrefix)
		invalidImageDefinitionName = fmt.Sprintf("%s invalid name!", s.uniquePrefix)
		imageVersion               = "1.0.0"
	)

	s.T().Log("CREATE curated image definition pointer without name")

	_, err := s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Enabled: true,
	})
	s.Require().ErrorContains(err, "name: value is required")
	s.Require().ErrorContains(err, "points_to_image_definition_id: value is required")

	s.T().Log("CREATE curated image definition pointer with invalid name")

	_, err = s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      invalidImageDefinitionName,
		Enabled:                   true,
		PointsToImageDefinitionId: pointerImageDefinitionWithGitHubOwner.Id,
	})
	s.Require().ErrorContains(err, "name: value does not match regex pattern")

	s.T().Log("CREATE image definition 1 via Admin API")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinitionWithVersions.Name,
		OsType:       imageDefinitionWithVersions.OsType,
		Architecture: imageDefinitionWithVersions.Architecture,
		Enabled:      imageDefinitionWithVersions.Enabled,
		OwnerId:      imageDefinitionWithVersions.OwnerId,
	})
	s.Require().NoError(err)
	imageDefinitionWithVersions.Id = createImageDefinitionResp.ImageDefinition.Id
	pointerImageDefinitionWithGitHubOwner.PointsToImageDefinitionId = createImageDefinitionResp.ImageDefinition.Id
	pointerImageDefinitionWithPartnerOwner.PointsToImageDefinitionId = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE curated image definition pointer with github owner via Admin API")

	createCuratedImageDefinitionPointerResp, err := s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      pointerImageDefinitionWithGitHubOwner.Name,
		OwnerId:                   pointerImageDefinitionWithGitHubOwner.OwnerId,
		Enabled:                   pointerImageDefinitionWithGitHubOwner.Enabled,
		PointsToImageDefinitionId: pointerImageDefinitionWithGitHubOwner.PointsToImageDefinitionId,
	})
	s.Require().NoError(err)
	pointerImageDefinitionWithGitHubOwner.Id = createCuratedImageDefinitionPointerResp.ImageDefinition.Id

	s.T().Log("CREATE curated image definition pointer with partner owner via Admin API")

	createCuratedImageDefinitionPointerResp, err = s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      pointerImageDefinitionWithPartnerOwner.Name,
		OwnerId:                   pointerImageDefinitionWithPartnerOwner.OwnerId,
		Enabled:                   pointerImageDefinitionWithPartnerOwner.Enabled,
		PointsToImageDefinitionId: pointerImageDefinitionWithPartnerOwner.PointsToImageDefinitionId,
	})
	s.Require().NoError(err)
	pointerImageDefinitionWithPartnerOwner.Id = createCuratedImageDefinitionPointerResp.ImageDefinition.Id

	s.T().Log("CREATE curated image definition pointer on a pointer")

	_, err = s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      validImageDefinitionName,
		OwnerId:                   models.GithubOwnerId,
		Enabled:                   true,
		PointsToImageDefinitionId: pointerImageDefinitionWithGitHubOwner.Id,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("CREATE image version to a pointer")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: pointerImageDefinitionWithGitHubOwner.Id,
		Version:           imageVersion,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
		Enabled:           true,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("UPDATE image version to a pointer")

	_, err = s.adminTwirpClient.UpdateCuratedImageVersion(s.ctx, &adminapi.UpdateCuratedImageVersionRequest{
		ImageDefinitionId: pointerImageDefinitionWithGitHubOwner.Id,
		Version:           "1.0.0",
		Enabled:           false,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("DELETE image version to a pointer")

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: pointerImageDefinitionWithGitHubOwner.Id,
		Version:           imageVersion,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("CREATE curated image definition 2 via Admin API")

	createImageDefinitionResp, err = s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinitionWithoutVersions.Name,
		OsType:       imageDefinitionWithoutVersions.OsType,
		Architecture: imageDefinitionWithoutVersions.Architecture,
		Enabled:      imageDefinitionWithoutVersions.Enabled,
		OwnerId:      imageDefinitionWithoutVersions.OwnerId,
	})
	s.Require().NoError(err)
	imageDefinitionWithoutVersions.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("UPDATE curated image defintion pointer 1 using UpdateCreatedImageDefinition")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId: pointerImageDefinitionWithGitHubOwner.Id,
		Name:              validImageDefinitionName,
		Enabled:           false,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("UPDATE curated image definition 1 using UpdateCuratedImageDefinitionPointer")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinitionPointer(s.ctx, &adminapi.UpdateCuratedImageDefinitionPointerRequest{
		ImageDefinitionId:         imageDefinitionWithVersions.Id,
		Name:                      validImageDefinitionName,
		Enabled:                   false,
		PointsToImageDefinitionId: pointerImageDefinitionWithGitHubOwner.PointsToImageDefinitionId,
	})
	s.Require().ErrorContains(err, "image definition is not a pointer")

	s.T().Log("UPDATE curated image defintion pointer 1 with missed image definition id, name, and points_to_image_definition_id")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinitionPointer(s.ctx, &adminapi.UpdateCuratedImageDefinitionPointerRequest{
		Enabled: false,
	})
	s.Require().ErrorContains(err, "image_definition_id: value is required")
	s.Require().ErrorContains(err, "name: value is required")
	s.Require().ErrorContains(err, "points_to_image_definition_id: value is required")

	s.T().Log("DELETE curated image definition pointer 1 without ImageDefinitionId")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{})
	s.Require().ErrorContains(err, "image_definition_id: value is required")

	s.T().Log("DELETE curated image definition pointer 1 using DeleteCuratedImageDefinition")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: pointerImageDefinitionWithGitHubOwner.Id,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("DELETE curated image definition 2 using DeleteCuratedImageDefinitionPointer")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: imageDefinitionWithoutVersions.Id,
	})
	s.Require().ErrorContains(err, "image definition is not a pointer")

	s.T().Log("DELETE curated image definition 1 using DeleteCuratedImageDefinition")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitionWithVersions.Id,
	})

	s.Require().ErrorContains(err, "failed to delete image definition because it is referenced by pointer. Delete pointer first.")

	s.T().Log("DELETE curated image definition pointer with github owner via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: pointerImageDefinitionWithGitHubOwner.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image definition pointer with partner owner via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: pointerImageDefinitionWithPartnerOwner.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image definition 1 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitionWithVersions.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image definition 2 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitionWithoutVersions.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image definition 3 via Admin API")
}

func (s *CuratedLatestImagesE2ETestSuite) Test_ValidationsUpdateCompatibility() {
	var (
		imageDefinitionDefault = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-validation2-ptr-def-default", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
			OwnerId:      models.GithubOwnerId,
		}
		imageDefinitionOsTypeWindows = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-validation2-ptr-def-win", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
			OwnerId:      models.GithubOwnerId,
		}
		imageDefinitionArchArm = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-validation2-ptr-def-arm", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_Arm64,
			Enabled:      true,
			OwnerId:      models.GithubOwnerId,
		}
		pointerImageDefinition = &adminapi.ImageDefinition{
			Name:    fmt.Sprintf("%s-curated-validation2-ptr-def-0", s.uniquePrefix),
			OwnerId: models.GithubOwnerId,
			Enabled: true,
		}
		allImageDefinitionsToCreate = []*adminapi.ImageDefinition{imageDefinitionDefault, imageDefinitionOsTypeWindows, imageDefinitionArchArm}
	)

	for _, imageDefinition := range allImageDefinitionsToCreate {
		s.T().Logf("CREATE curated image definition (%s) via Admin API", imageDefinition.Name)

		createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
			Name:         imageDefinition.Name,
			OsType:       imageDefinition.OsType,
			Architecture: imageDefinition.Architecture,
			Enabled:      imageDefinition.Enabled,
			OwnerId:      imageDefinition.OwnerId,
		})
		s.Require().NoError(err)
		imageDefinition.Id = createImageDefinitionResp.ImageDefinition.Id
	}

	s.T().Log("CREATE curated image definition pointer via Admin API")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      pointerImageDefinition.Name,
		OwnerId:                   pointerImageDefinition.OwnerId,
		Enabled:                   pointerImageDefinition.Enabled,
		PointsToImageDefinitionId: imageDefinitionDefault.Id,
	})
	s.Require().NoError(err)
	pointerImageDefinition.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("UPDATE curated image definition pointer 1 to point to curated image definition with different os type")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinitionPointer(s.ctx, &adminapi.UpdateCuratedImageDefinitionPointerRequest{
		ImageDefinitionId:         pointerImageDefinition.Id,
		Name:                      pointerImageDefinition.Name,
		Enabled:                   pointerImageDefinition.Enabled,
		PointsToImageDefinitionId: imageDefinitionOsTypeWindows.Id,
	})
	s.Require().ErrorContains(err, "os_type of new pointer target is not equal to previous pointer target")

	s.T().Log("UPDATE curated image definition pointer 1 to point to curated image definition with different arch")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinitionPointer(s.ctx, &adminapi.UpdateCuratedImageDefinitionPointerRequest{
		ImageDefinitionId:         pointerImageDefinition.Id,
		Name:                      pointerImageDefinition.Name,
		Enabled:                   pointerImageDefinition.Enabled,
		PointsToImageDefinitionId: imageDefinitionArchArm.Id,
	})
	s.Require().ErrorContains(err, "architecture of new pointer target is not equal to previous pointer target")

	s.T().Log("DELETE curated image definition pointer via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().NoError(err)

	for _, imageDefinition := range allImageDefinitionsToCreate {
		s.T().Logf("DELETE curated image definition (%s) via Admin API", imageDefinition.Name)

		_, err := s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
			ImageDefinitionId: imageDefinition.Id,
		})
		s.Require().NoError(err)
	}
}

func (s *CuratedLatestImagesE2ETestSuite) Test_FeatureFlag() {
	var (
		pointerImageDefinitions = []*adminapi.ImageDefinition{
			{
				Name:        fmt.Sprintf("%s-curated-ptr-feature-flag-pointer-1", s.uniquePrefix),
				OwnerId:     models.GithubOwnerId,
				Enabled:     true,
				FeatureFlag: string(featureflags.TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled),
			},
			{
				Name:        fmt.Sprintf("%s-curated-ptr-feature-flag-pointer-2", s.uniquePrefix),
				OwnerId:     models.GithubOwnerId,
				Enabled:     true,
				FeatureFlag: string(featureflags.TEST_FeatureFlag_E2E_TestFlag_GloballyDisabled),
			},
			{
				Name:        fmt.Sprintf("%s-curated-ptr-feature-flag-pointer-3", s.uniquePrefix),
				OwnerId:     models.GithubOwnerId,
				Enabled:     true,
				FeatureFlag: string(featureflags.TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner),
			},
		}
		imageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-feature-flag-test-def-1", s.uniquePrefix),
			OwnerId:      models.GithubOwnerId,
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
			Enabled:      false,
		}
	)
	s.T().Log("CREATE curated image definition 1 via Admin API")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinition.Name,
		OwnerId:      imageDefinition.OwnerId,
		OsType:       imageDefinition.OsType,
		Architecture: imageDefinition.Architecture,
		Enabled:      imageDefinition.Enabled,
	})
	s.Require().NoError(err)
	imageDefinition.Id = createImageDefinitionResp.ImageDefinition.Id
	pointerImageDefinitions[0].PointsToImageDefinitionId = imageDefinition.Id

	s.T().Log("CREATE curated image definition pointer 1 with Feature Flag Enabled via Admin API")

	createCuratedImageDefinitionPointerResp, err := s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      pointerImageDefinitions[0].Name,
		OwnerId:                   pointerImageDefinitions[0].OwnerId,
		Enabled:                   pointerImageDefinitions[0].Enabled,
		PointsToImageDefinitionId: imageDefinition.Id,
		FeatureFlag:               pointerImageDefinitions[0].FeatureFlag,
	})
	pointerImageDefinitions[0].Id = createCuratedImageDefinitionPointerResp.ImageDefinition.Id
	s.Require().NoError(err)

	s.T().Log("GET curated image definition pointer 1 via Admin API")

	getCuratedImageDefinitionPointerResp, err := s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: pointerImageDefinitions[0].Id,
	})

	s.Require().NoError(err)
	s.Require().Equal(pointerImageDefinitions[0].Id, getCuratedImageDefinitionPointerResp.ImageDefinition.Id)
	s.Require().Equal(pointerImageDefinitions[0].Name, getCuratedImageDefinitionPointerResp.ImageDefinition.Name)
	s.Require().Equal(pointerImageDefinitions[0].Enabled, getCuratedImageDefinitionPointerResp.ImageDefinition.Enabled)
	s.Require().Equal(pointerImageDefinitions[0].FeatureFlag, getCuratedImageDefinitionPointerResp.ImageDefinition.FeatureFlag)

	s.T().Log("LIST image versions for image definition 1 pointer via Admin API")

	listImageVersionsResp, err := s.adminTwirpClient.ListCuratedImageVersions(s.ctx, &adminapi.ListCuratedImageVersionsRequest{
		ImageDefinitionId: pointerImageDefinitions[0].Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(0, len(listImageVersionsResp.ImageVersions))

	s.T().Log("CREATE curated image definition pointer 2 with Feature Flag Disabled via Admin API")

	createCuratedImageDefinitionPointerResp, err = s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      pointerImageDefinitions[1].Name,
		OwnerId:                   pointerImageDefinitions[1].OwnerId,
		Enabled:                   pointerImageDefinitions[1].Enabled,
		PointsToImageDefinitionId: imageDefinition.Id,
		FeatureFlag:               pointerImageDefinitions[1].FeatureFlag,
	})
	pointerImageDefinitions[1].Id = createCuratedImageDefinitionPointerResp.ImageDefinition.Id
	s.Require().NoError(err)

	s.T().Log("GET curated image definition pointer 2 via Admin API")

	getCuratedImageDefinitionPointerResp, err = s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: pointerImageDefinitions[1].Id,
	})

	s.Require().NoError(err)
	s.Require().Equal(pointerImageDefinitions[1].Id, getCuratedImageDefinitionPointerResp.ImageDefinition.Id)
	s.Require().Equal(pointerImageDefinitions[1].Name, getCuratedImageDefinitionPointerResp.ImageDefinition.Name)
	s.Require().Equal(pointerImageDefinitions[1].Enabled, getCuratedImageDefinitionPointerResp.ImageDefinition.Enabled)
	s.Require().Equal(pointerImageDefinitions[1].FeatureFlag, getCuratedImageDefinitionPointerResp.ImageDefinition.FeatureFlag)

	s.T().Log("LIST image versions for image definition 2 pointer via Admin API")

	listImageVersionsResp, err = s.adminTwirpClient.ListCuratedImageVersions(s.ctx, &adminapi.ListCuratedImageVersionsRequest{
		ImageDefinitionId: pointerImageDefinitions[1].Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(0, len(listImageVersionsResp.ImageVersions))

	s.T().Log("CREATE curated image definition pointer 3 with Feature Flag Disabled via Admin API")

	createCuratedImageDefinitionPointerResp, err = s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      pointerImageDefinitions[2].Name,
		OwnerId:                   pointerImageDefinitions[2].OwnerId,
		Enabled:                   pointerImageDefinitions[2].Enabled,
		PointsToImageDefinitionId: imageDefinition.Id,
		FeatureFlag:               pointerImageDefinitions[2].FeatureFlag,
	})
	pointerImageDefinitions[2].Id = createCuratedImageDefinitionPointerResp.ImageDefinition.Id
	s.Require().NoError(err)

	s.T().Log("GET curated image definition pointer 3 via Admin API")

	getCuratedImageDefinitionPointerResp, err = s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: pointerImageDefinitions[2].Id,
	})

	s.Require().NoError(err)
	s.Require().Equal(pointerImageDefinitions[2].Id, getCuratedImageDefinitionPointerResp.ImageDefinition.Id)
	s.Require().Equal(pointerImageDefinitions[2].Name, getCuratedImageDefinitionPointerResp.ImageDefinition.Name)
	s.Require().Equal(pointerImageDefinitions[2].Enabled, getCuratedImageDefinitionPointerResp.ImageDefinition.Enabled)
	s.Require().Equal(pointerImageDefinitions[2].FeatureFlag, getCuratedImageDefinitionPointerResp.ImageDefinition.FeatureFlag)

	s.T().Log("LIST image versions for image definition 2 pointer via Admin API")

	listImageVersionsResp, err = s.adminTwirpClient.ListCuratedImageVersions(s.ctx, &adminapi.ListCuratedImageVersionsRequest{
		ImageDefinitionId: pointerImageDefinitions[2].Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(0, len(listImageVersionsResp.ImageVersions))

	s.T().Log("LIST curated image definitions")

	listImageDefinitionsResp, err := s.adminTwirpClient.ListCuratedImageDefinitions(s.ctx, &adminapi.ListCuratedImageDefinitionsRequest{})
	s.Require().NoError(err)
	listedImageDefinitions := s.filterTestCuratedImageDefinitions(listImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(4, len(listedImageDefinitions))

	s.T().Log("DELETE curated image definition pointer 1 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: pointerImageDefinitions[0].Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image definition pointer 2 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: pointerImageDefinitions[1].Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image definition pointer 3 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: pointerImageDefinitions[2].Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE curated image definition via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinition.Id,
	})
	s.Require().NoError(err)
}
