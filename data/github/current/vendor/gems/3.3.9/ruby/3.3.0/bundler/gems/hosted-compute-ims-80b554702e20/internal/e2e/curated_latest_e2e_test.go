package e2e

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/suite"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/featureflags"
)

type CuratedLatestImagesE2ETestSuite struct {
	BaseE2ETestSuite
}

func TestCuratedLatestImagesE2ETestSuite(t *testing.T) {
	t.Parallel()
	suite.Run(t, new(CuratedLatestImagesE2ETestSuite))
}

func (s *CuratedLatestImagesE2ETestSuite) Test_CreateImageDefinitionPointers() {
	var (
		imageDefinitionWithVersions = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-ptr-create-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
		}
		imageDefinitionWithoutVersions = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-ptr-create-def-2", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
		}
		pointerImageDefinition = &adminapi.ImageDefinition{
			Name:    fmt.Sprintf("%s-curated-ptr-create-pointer", s.uniquePrefix),
			Enabled: true,
		}
		imageVersion = "1.0.0"
	)
	s.T().Log("CREATE curated image definition 1 via Admin API")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinitionWithVersions.Name,
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

	s.T().Log("GET image version for image definition pointer via Admin API")

	getImageVersionResp, err := s.adminTwirpClient.GetCuratedImageVersion(s.ctx, &adminapi.GetCuratedImageVersionRequest{
		ImageDefinitionId: pointerImageDefinition.Id,
		Version:           imageVersion,
	})
	s.Require().NoError(err)
	s.Require().Equal(imageVersion, getImageVersionResp.ImageVersion.Version)

	s.T().Log("LIST image version for image definition pointer via Admin API")

	listImageVersionsForPointerResp, err := s.adminTwirpClient.ListCuratedImageVersions(s.ctx, &adminapi.ListCuratedImageVersionsRequest{
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

	s.T().Log("LIST image version after update pointer to image definition 2 via Admin API")

	listImageVersionsForPointerResp, err = s.adminTwirpClient.ListCuratedImageVersions(s.ctx, &adminapi.ListCuratedImageVersionsRequest{
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
		}
		imageDefinitionWithoutVersions = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-validation-ptr-def-2", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
		}
		imageDefinitionOsTypeWindows = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-validation-ptr-def-3", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
		}
		pointerImageDefinition = &adminapi.ImageDefinition{
			Name:    fmt.Sprintf("%s-curated-validation-ptr-def-4", s.uniquePrefix),
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
		PointsToImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().ErrorContains(err, "name: value does not match regex pattern")

	s.T().Log("CREATE image definition 1 via Admin API")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinitionWithVersions.Name,
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
		Enabled:                   pointerImageDefinition.Enabled,
		PointsToImageDefinitionId: pointerImageDefinition.PointsToImageDefinitionId,
	})
	s.Require().NoError(err)
	pointerImageDefinition.Id = createCuratedImageDefinitionPointerResp.ImageDefinition.Id

	s.T().Log("UPDATE curated image definition pointer name to be equal to definition 1")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinitionPointer(s.ctx, &adminapi.UpdateCuratedImageDefinitionPointerRequest{
		ImageDefinitionId:         pointerImageDefinition.Id,
		Name:                      imageDefinitionWithVersions.Name,
		PointsToImageDefinitionId: pointerImageDefinition.PointsToImageDefinitionId,
		Enabled:                   true,
	})
	s.Require().ErrorContains(err, "image definition with this name already exists")

	s.T().Log("CREATE curated image definition pointer on a pointer")

	_, err = s.adminTwirpClient.CreateCuratedImageDefinitionPointer(s.ctx, &adminapi.CreateCuratedImageDefinitionPointerRequest{
		Name:                      validImageDefinitionName,
		Enabled:                   true,
		PointsToImageDefinitionId: pointerImageDefinition.Id,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("CREATE image version to a pointer")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: pointerImageDefinition.Id,
		Version:           imageVersion,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
		Enabled:           true,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("UPDATE image version to a pointer")

	_, err = s.adminTwirpClient.UpdateCuratedImageVersion(s.ctx, &adminapi.UpdateCuratedImageVersionRequest{
		ImageDefinitionId: pointerImageDefinition.Id,
		Version:           "1.0.0",
		Enabled:           false,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("DELETE image version to a pointer")

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: pointerImageDefinition.Id,
		Version:           imageVersion,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("CREATE curated image definition 2 via Admin API")

	createImageDefinitionResp, err = s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinitionWithoutVersions.Name,
		OsType:       imageDefinitionWithoutVersions.OsType,
		Architecture: imageDefinitionWithoutVersions.Architecture,
		Enabled:      imageDefinitionWithoutVersions.Enabled,
	})
	s.Require().NoError(err)
	imageDefinitionWithoutVersions.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE curated image definition 3 via Admin API")

	createImageDefinitionResp, err = s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinitionOsTypeWindows.Name,
		OsType:       imageDefinitionOsTypeWindows.OsType,
		Architecture: imageDefinitionOsTypeWindows.Architecture,
		Enabled:      imageDefinitionOsTypeWindows.Enabled,
	})
	s.Require().NoError(err)
	imageDefinitionOsTypeWindows.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("UPDATE curated image definition pointer 1 to point to curated image definition 2")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinitionPointer(s.ctx, &adminapi.UpdateCuratedImageDefinitionPointerRequest{
		ImageDefinitionId:         pointerImageDefinition.Id,
		Name:                      pointerImageDefinition.Name,
		Enabled:                   pointerImageDefinition.Enabled,
		PointsToImageDefinitionId: imageDefinitionOsTypeWindows.Id,
	})
	s.Require().ErrorContains(err, "os_type of new pointer target is not equal to previous pointer target")

	s.T().Log("UPDATE curated image defintion pointer 1 using UpdateCreatedImageDefinition")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId: pointerImageDefinition.Id,
		Name:              validImageDefinitionName,
		Enabled:           false,
	})
	s.Require().ErrorContains(err, "image definition pointer is not allowed for this operation")

	s.T().Log("UPDATE curated image definition 1 using UpdateCuratedImageDefinitionPointer")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinitionPointer(s.ctx, &adminapi.UpdateCuratedImageDefinitionPointerRequest{
		ImageDefinitionId:         imageDefinitionWithVersions.Id,
		Name:                      validImageDefinitionName,
		Enabled:                   false,
		PointsToImageDefinitionId: pointerImageDefinition.PointsToImageDefinitionId,
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
		ImageDefinitionId: pointerImageDefinition.Id,
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

	s.T().Log("DELETE curated image definition pointer 1 via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinitionPointer(s.ctx, &adminapi.DeleteCuratedImageDefinitionPointerRequest{
		ImageDefinitionId: pointerImageDefinition.Id,
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

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitionOsTypeWindows.Id,
	})
	s.Require().NoError(err)
}

func (s *CuratedLatestImagesE2ETestSuite) Test_FeatureFlag() {
	var (
		pointerImageDefinitions = []*adminapi.ImageDefinition{
			{
				Name:        fmt.Sprintf("%s-curated-ptr-feature-flag-pointer-1", s.uniquePrefix),
				Enabled:     true,
				FeatureFlag: string(featureflags.FeatureFlag_E2E_TestFlag_GloballyEnabled),
			},
			{
				Name:        fmt.Sprintf("%s-curated-ptr-feature-flag-pointer-2", s.uniquePrefix),
				Enabled:     true,
				FeatureFlag: string(featureflags.FeatureFlag_E2E_TestFlag_GloballyDisabled),
			},
			{
				Name:        fmt.Sprintf("%s-curated-ptr-feature-flag-pointer-3", s.uniquePrefix),
				Enabled:     true,
				FeatureFlag: string(featureflags.FeatureFlag_E2E_TestFlag_EnabledPerOwner),
			},
		}
		imageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-feature-flag-test-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
			Enabled:      false,
		}
	)
	s.T().Log("CREATE curated image definition 1 via Admin API")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinition.Name,
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
