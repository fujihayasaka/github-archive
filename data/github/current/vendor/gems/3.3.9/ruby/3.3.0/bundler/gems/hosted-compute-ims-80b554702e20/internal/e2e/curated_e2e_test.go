package e2e

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/suite"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/featureflags"
)

type CuratedImagesE2ETestSuite struct {
	BaseE2ETestSuite
}

func TestCuratedImagesE2ETestSuite(t *testing.T) {
	// tests within suite will run in sequential order unless t.Parallel() is called within individual tests
	// for now, only suites will run in parallel
	t.Parallel()
	suite.Run(t, new(CuratedImagesE2ETestSuite))
}

func (s *CuratedImagesE2ETestSuite) Test_CreateImageDefinitionsAndVersions() {
	var (
		enabledImageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-create-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
		}
		disabledImageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-create-def-2", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
			Enabled:      false,
		}
		addedImageVersions = []*adminapi.ImageVersion{
			{
				Version: "1.0.0",
				Enabled: true,
			},
			{
				Version: "3.2.0",
				Enabled: true,
			},
			{
				Version: "2.0.5",
				Enabled: false,
			},
		}
		sortedImageVersions                    = []string{"3.2.0", "2.0.5", "1.0.0"}
		sortedEnabledImageVersions             = []string{"3.2.0", "1.0.0"}
		imageVersionForDisabledImageDefinition = "4.0.0"
	)

	s.T().Log("CREATE enabled curated image definition via Admin API")

	enabledImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         enabledImageDefinition.Name,
		OsType:       enabledImageDefinition.OsType,
		Architecture: enabledImageDefinition.Architecture,
		Enabled:      enabledImageDefinition.Enabled,
	})
	s.Require().NoError(err)
	enabledImageDefinition.Id = enabledImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET enabled curated image definitions via Admin API")

	getImageDefinitionResp, err := s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(enabledImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(enabledImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(enabledImageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(enabledImageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(enabledImageDefinition.Enabled, getImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("CREATE disabled curated image definition via Admin API")

	disabledImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         disabledImageDefinition.Name,
		OsType:       disabledImageDefinition.OsType,
		Architecture: disabledImageDefinition.Architecture,
		Enabled:      disabledImageDefinition.Enabled,
	})
	s.Require().NoError(err)
	disabledImageDefinition.Id = disabledImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET disabled curated image definitions via Admin API")

	getImageDefinitionResp, err = s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(disabledImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(disabledImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(disabledImageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(disabledImageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(disabledImageDefinition.Enabled, getImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("LIST curated image definitions")

	listImageDefinitionsResp, err := s.adminTwirpClient.ListCuratedImageDefinitions(s.ctx, &adminapi.ListCuratedImageDefinitionsRequest{})
	s.Require().NoError(err)
	listedImageDefinitions := s.filterTestCuratedImageDefinitions(listImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(2, len(listedImageDefinitions))
	s.Require().Equal(enabledImageDefinition.Id, listedImageDefinitions[0].Id)
	s.Require().Equal(disabledImageDefinition.Id, listedImageDefinitions[1].Id)

	s.T().Log("CREATE multiple image versions for enabled image definition via Admin API")

	for _, iv := range addedImageVersions {
		_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: enabledImageDefinition.Id,
			Version:           iv.Version,
			Enabled:           iv.Enabled,
			SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
		})
		s.Require().NoError(err)
	}

	s.T().Log("GET image versions for enabled image definition via Admin API")

	for _, iv := range addedImageVersions {
		getImageVersionResp, err := s.adminTwirpClient.GetCuratedImageVersion(s.ctx, &adminapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: enabledImageDefinition.Id,
			Version:           iv.Version,
		})
		s.Require().NoError(err)
		s.Require().Equal(iv.Version, getImageVersionResp.ImageVersion.Version)
		s.Require().Equal(iv.Enabled, getImageVersionResp.ImageVersion.Enabled)
	}

	s.T().Log("LIST image versions for enabled image definition via Admin API")

	listImageVersionsResp, err := s.adminTwirpClient.ListCuratedImageVersions(s.ctx, &adminapi.ListCuratedImageVersionsRequest{
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(len(sortedImageVersions), len(listImageVersionsResp.ImageVersions))
	for ind := 0; ind < len(sortedImageVersions); ind++ {
		s.Require().Equal(sortedImageVersions[ind], listImageVersionsResp.ImageVersions[ind].Version)
	}

	s.T().Log("CREATE image version for disabled image definition via Admin API")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: disabledImageDefinition.Id,
		Version:           imageVersionForDisabledImageDefinition,
		Enabled:           true,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().NoError(err)

	s.T().Log("GET image versions for disabled image definition via Admin API")

	getImageVersionResp, err := s.adminTwirpClient.GetCuratedImageVersion(s.ctx, &adminapi.GetCuratedImageVersionRequest{
		ImageDefinitionId: disabledImageDefinition.Id,
		Version:           imageVersionForDisabledImageDefinition,
	})
	s.Require().NoError(err)
	s.Require().Equal(imageVersionForDisabledImageDefinition, getImageVersionResp.ImageVersion.Version)
	s.Require().Equal(true, getImageVersionResp.ImageVersion.Enabled)

	s.T().Log("LIST image versions for disabled image definition via Admin API")

	listImageVersionsResp, err = s.adminTwirpClient.ListCuratedImageVersions(s.ctx, &adminapi.ListCuratedImageVersionsRequest{
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(1, len(listImageVersionsResp.ImageVersions))
	s.Require().Equal(imageVersionForDisabledImageDefinition, listImageVersionsResp.ImageVersions[0].Version)

	s.T().Log("GET enabled image definition via Customer API")

	getCustomerImageDefinitionResp, err := s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(enabledImageDefinition.Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(enabledImageDefinition.Name, getCustomerImageDefinitionResp.ImageDefinition.Name)

	s.T().Log("GET disabled image definition via Customer API")

	_, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Log("LIST image definitions with Include Disabled false via Customer API")

	listCustomerImageDefinitionsResp, err := s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "owner"},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions := s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(1, len(listedCustomerImageDefinitions))
	s.Require().Equal(enabledImageDefinition.Id, listedCustomerImageDefinitions[0].Id)
	s.Require().Equal(enabledImageDefinition.Name, listedCustomerImageDefinitions[0].Name)

	s.T().Log("LIST image definitions with Include Disabled true via Customer API")

	listCustomerImageDefinitionsResp, err = s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "owner"},
		IncludeDisabled: true,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(2, len(listedCustomerImageDefinitions))
	s.Require().Equal(enabledImageDefinition.Id, listedCustomerImageDefinitions[0].Id)
	s.Require().Equal(enabledImageDefinition.Name, listedCustomerImageDefinitions[0].Name)
	s.Require().Equal(disabledImageDefinition.Id, listedCustomerImageDefinitions[1].Id)
	s.Require().Equal(disabledImageDefinition.Name, listedCustomerImageDefinitions[1].Name)

	s.T().Log("LIST image versions for enabled image definition via Customer API")

	listCustomerImageVersionsResp, err := s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(len(sortedEnabledImageVersions), len(listCustomerImageVersionsResp.ImageVersions))
	for ind := 0; ind < len(sortedEnabledImageVersions); ind++ {
		s.Require().Equal(sortedEnabledImageVersions[ind], listCustomerImageVersionsResp.ImageVersions[ind].Version)
	}

	s.T().Log("GET image versions for enabled image definition via Customer API")

	for _, iv := range addedImageVersions {
		getCustomerImageVersionsResp, err := s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: "owner"},
			ImageDefinitionId: enabledImageDefinition.Id,
			Version:           iv.Version,
		})
		if iv.Enabled {
			s.Require().NoError(err)
			s.Require().Equal(iv.Version, getCustomerImageVersionsResp.ImageVersion.Version)
		} else {
			s.Require().ErrorContains(err, "image version is not found")
		}
	}

	s.T().Log("LIST image versions for disabled image definition via Customer API")

	_, err = s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image versions for disabled image definition via Customer API")

	_, err = s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: disabledImageDefinition.Id,
		Version:           imageVersionForDisabledImageDefinition,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("DELETE image versions for image definitions via Admin API")

	for _, iv := range addedImageVersions {
		s.waitForAdminImageVersionProvisionFailed(enabledImageDefinition.Id, iv.Version)
	}

	s.waitForAdminImageVersionProvisionFailed(disabledImageDefinition.Id, imageVersionForDisabledImageDefinition)

	for _, version := range sortedImageVersions {
		_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: enabledImageDefinition.Id,
			Version:           version,
		})
		s.Require().NoError(err)
	}

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: disabledImageDefinition.Id,
		Version:           imageVersionForDisabledImageDefinition,
	})
	s.Require().NoError(err)

	for _, version := range sortedImageVersions {
		s.waitForAdminImageVersionDeletion(enabledImageDefinition.Id, version)
	}

	s.waitForAdminImageVersionDeletion(disabledImageDefinition.Id, imageVersionForDisabledImageDefinition)

	s.T().Log("DELETE image definitions via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Log("LIST image definitions via Admin API")

	listCuratedImageDefinitionsResp, err := s.adminTwirpClient.ListCuratedImageDefinitions(s.ctx, &adminapi.ListCuratedImageDefinitionsRequest{})
	s.Require().NoError(err)
	listedImageDefinitions = s.filterTestCuratedImageDefinitions(listCuratedImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(0, len(listedImageDefinitions))

	s.T().Log("LIST image definitions include disabled false via Customer API")

	listCustomerImageDefinitionsResp, err = s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "owner"},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(0, len(listedCustomerImageDefinitions))

	s.T().Log("LIST image definitions include disabled true via Customer API")

	listCustomerImageDefinitionsResp, err = s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "owner"},
		IncludeDisabled: true,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(0, len(listedCustomerImageDefinitions))
}

func (s *CuratedImagesE2ETestSuite) Test_UpdateImageDefinitionAndVersion() {
	var (
		imageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-update-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}
		newImageDefinitionName = fmt.Sprintf("%s-curated-update-def-2", s.uniquePrefix)
		imageVersion           = &adminapi.ImageVersion{
			Version: "1.0.0",
		}
	)

	s.T().Log("CREATE curated image definition via Admin API")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         imageDefinition.Name,
		OsType:       imageDefinition.OsType,
		Architecture: imageDefinition.Architecture,
		Enabled:      true,
	})
	s.Require().NoError(err)
	imageDefinition.Id = createImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET curated image definition via Admin API")

	getImageDefinitionResp, err := s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(imageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(imageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(imageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(imageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(true, getImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("UPDATE curated image definition via Admin API")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinition.Id,
		Name:              newImageDefinitionName,
		Enabled:           false,
	})
	s.Require().NoError(err)

	s.T().Log("GET curated image definition via Admin API")

	getImageDefinitionResp, err = s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(imageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(newImageDefinitionName, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(imageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(imageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(false, getImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("CREATE image version via Admin API")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinition.Id,
		Version:           imageVersion.Version,
		Enabled:           true,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().NoError(err)

	s.waitForAdminImageVersionProvisionFailed(imageDefinition.Id, imageVersion.Version)

	s.T().Log("GET image version via Admin API")

	getImageVersionResp, err := s.adminTwirpClient.GetCuratedImageVersion(s.ctx, &adminapi.GetCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinition.Id,
		Version:           imageVersion.Version,
	})
	s.Require().NoError(err)
	s.Require().Equal(imageVersion.Version, getImageVersionResp.ImageVersion.Version)
	s.Require().Equal(true, getImageVersionResp.ImageVersion.Enabled)

	s.T().Log("UPDATE image version via Admin API")

	_, err = s.adminTwirpClient.UpdateCuratedImageVersion(s.ctx, &adminapi.UpdateCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinition.Id,
		Version:           imageVersion.Version,
		Enabled:           false,
	})
	s.Require().NoError(err)

	s.T().Log("GET image version via Admin API")

	getImageVersionResp, err = s.adminTwirpClient.GetCuratedImageVersion(s.ctx, &adminapi.GetCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinition.Id,
		Version:           imageVersion.Version,
	})
	s.Require().NoError(err)
	s.Require().Equal(imageVersion.Version, getImageVersionResp.ImageVersion.Version)
	s.Require().Equal(false, getImageVersionResp.ImageVersion.Enabled)

	s.T().Log("DELETE image version via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinition.Id,
		Version:           imageVersion.Version,
	})
	s.Require().NoError(err)

	s.waitForAdminImageVersionDeletion(imageDefinition.Id, imageVersion.Version)

	s.T().Log("DELETE image definition via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinition.Id,
	})
	s.Require().NoError(err)
}

func (s *CuratedImagesE2ETestSuite) Test_FeatureFlagInImageDefinition() {
	imageDefinitions := []*adminapi.ImageDefinition{
		{
			Name:         fmt.Sprintf("%s-feature-flag-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
			Enabled:      false,
			FeatureFlag:  string(featureflags.FeatureFlag_E2E_TestFlag_GloballyEnabled),
		},
		{
			Name:         fmt.Sprintf("%s-feature-flag-def-2", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
			Enabled:      true,
			FeatureFlag:  string(featureflags.FeatureFlag_E2E_TestFlag_GloballyDisabled),
		},
		{
			Name:         fmt.Sprintf("%s-feature-flag-def-3", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
			Enabled:      false,
			FeatureFlag:  string(featureflags.FeatureFlag_E2E_TestFlag_EnabledPerOwner),
		},
	}

	s.T().Log("CREATE multiple image definitions with feature flag via Admin API")
	for _, imageDefinition := range imageDefinitions {

		resp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
			Name:         imageDefinition.Name,
			OsType:       imageDefinition.OsType,
			Architecture: imageDefinition.Architecture,
			Enabled:      imageDefinition.Enabled,
			FeatureFlag:  imageDefinition.FeatureFlag,
		})
		s.Require().NoError(err)

		imageDefinition.Id = resp.ImageDefinition.Id
	}

	s.T().Log("CREATE image version on globally enabled image definition via Admin API")

	_, err := s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinitions[0].Id,
		Version:           "1.0.0",
		Enabled:           true,
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
	})
	s.Require().NoError(err)

	s.T().Log("LIST curated image definitions for known user via Customer API")
	listCustomerImageDefinitionsResp, err := s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: featureflags.FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions := s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(2, len(listedCustomerImageDefinitions))

	s.T().Log("LIST curated image definitions for other user via Customer API")
	listCustomerImageDefinitionsResp, err = s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "other"},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(1, len(listedCustomerImageDefinitions))

	s.T().Log("GET image definition with feature flag globally enabled via Customer API")
	getCustomerImageDefinitionResp, err := s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "other"},
		ImageDefinitionId: imageDefinitions[0].Id,
	})

	s.Require().NoError(err)
	s.Require().Equal(imageDefinitions[0].Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(imageDefinitions[0].Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(imageDefinitions[0].OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(imageDefinitions[0].Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(true, getCustomerImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("GET image definition with feature flag enabled per user for known user via Customer API")
	getCustomerImageDefinitionResp, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: featureflags.FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID},
		ImageDefinitionId: imageDefinitions[2].Id,
	})

	s.Require().NoError(err)
	s.Require().Equal(imageDefinitions[2].Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(imageDefinitions[2].Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(imageDefinitions[2].OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(imageDefinitions[2].Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(true, getCustomerImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("GET image definition with feature flag enabled per user for unknown user via Customer API")
	getCustomerImageDefinitionResp, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "other"},
		ImageDefinitionId: imageDefinitions[2].Id,
	})

	s.Require().NoError(err)
	s.Require().Equal(imageDefinitions[2].Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(imageDefinitions[2].Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(imageDefinitions[2].OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(imageDefinitions[2].Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(false, getCustomerImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("GET image definition with feature flag globally disabled via Customer API")
	getCustomerImageDefinitionResp, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "other"},
		ImageDefinitionId: imageDefinitions[1].Id,
	})

	s.Require().NoError(err)
	s.Require().Equal(imageDefinitions[1].Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(imageDefinitions[1].Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(imageDefinitions[1].OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(imageDefinitions[1].Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(false, getCustomerImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("UPDATE image definition globally disabled feature flag to empty string via Admin API")
	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitions[1].Id,
		Name:              imageDefinitions[1].Name,
		Enabled:           true,
	})
	s.Require().NoError(err)

	s.T().Log("GET image definition with feature flag empty string via Admin API")

	getImageDefinitionResp, err := s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitions[1].Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitions[1].Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(imageDefinitions[1].Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(imageDefinitions[1].OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(imageDefinitions[1].Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(imageDefinitions[1].Enabled, getImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal("", getImageDefinitionResp.ImageDefinition.FeatureFlag)

	s.T().Log("GET image definition with feature flag empty string via Customer API")
	getCustomerImageDefinitionResp, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "other"},
		ImageDefinitionId: imageDefinitions[1].Id,
	})

	s.T().Logf("Enabled: %+v", getCustomerImageDefinitionResp.ImageDefinition.Enabled)

	s.Require().NoError(err)
	s.Require().Equal(imageDefinitions[1].Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(imageDefinitions[1].Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(imageDefinitions[1].OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(imageDefinitions[1].Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(imageDefinitions[1].Enabled, getCustomerImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("UPDATE image definition globally disabled feature flag back to original via Admin API")
	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId: imageDefinitions[1].Id,
		Name:              imageDefinitions[1].Name,
		Enabled:           false,
		FeatureFlag:       imageDefinitions[1].FeatureFlag,
	})
	s.Require().NoError(err)

	s.T().Log("LIST image versions for globally enabled image definition via Customer API")

	listCustomerImageVersionsResp, err := s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: imageDefinitions[0].Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(1, len(listCustomerImageVersionsResp.ImageVersions))

	s.T().Log("LIST image versions for globally enabled image definition via Customer API")

	_, err = s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: imageDefinitions[1].Id,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image version on globally enabled image definition via Customer API")

	_, err = s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: imageDefinitions[0].Id,
		Version:           "1.0.0",
	})
	s.Require().NoError(err)

	s.T().Log("GET image version on globally disabled image definition via Customer API")
	_, err = s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: imageDefinitions[1].Id,
		Version:           "1.0.0",
	})

	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("DELETE image version via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinitions[0].Id,
		Version:           "1.0.0",
	})

	s.Require().NoError(err)

	s.waitForAdminImageVersionDeletion(imageDefinitions[0].Id, "1.0.0")

	s.T().Log("DELETE multiple image definitions via Admin API")

	for _, imageDefinition := range imageDefinitions {
		_, err := s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
			ImageDefinitionId: imageDefinition.Id,
		})

		s.Require().NoError(err)
	}
}

func (s *CuratedImagesE2ETestSuite) Test_Validations() {
	var (
		invalidImageDefinitionName       = fmt.Sprintf("%s Invalid Name!", s.uniquePrefix)
		validCuratedImageDefinitionName  = fmt.Sprintf("%s-curated-validation-def-1 Ubuntu 22.04", s.uniquePrefix)
		validCuratedImageDefinitionName2 = fmt.Sprintf("%s-curated-validation-def-2 Ubuntu 22.04", s.uniquePrefix)
		validCustomerImageDefinitionName = fmt.Sprintf("%s-curated-validation-def-1", s.uniquePrefix)
	)

	s.T().Log("CREATE image definition without name")

	_, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
		Enabled:      true,
	})
	s.Require().ErrorContains(err, "name: value is required")

	s.T().Log("CREATE image definition with invalid name")

	_, err = s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         invalidImageDefinitionName,
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
		Enabled:      true,
	})
	s.Require().ErrorContains(err, "name: value does not match regex pattern")

	s.T().Log("CREATE image definition with correct params")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         validCuratedImageDefinitionName,
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
		Enabled:      true,
	})
	s.Require().NoError(err)

	s.T().Log("CREATE image definition with existing name")

	_, err = s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         validCuratedImageDefinitionName,
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
		Enabled:      true,
	})
	s.Require().ErrorContains(err, "image definition with this name already exists")

	s.T().Log("UPDATE image definition name without image definition id and name")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{})
	s.Require().ErrorContains(err, "image_definition_id: value is required")
	s.Require().ErrorContains(err, "name: value is required")

	s.T().Log("UPDATE image definition name to invalid")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Name:              invalidImageDefinitionName,
	})
	s.Require().ErrorContains(err, "name: value does not match regex pattern")

	s.T().Log("UPDATE curated image definition via Customer API")

	_, err = s.customerTwirpClient.UpdateCustomerImageDefinition(s.ctx, &imagesapi.UpdateCustomerImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Name:              validCustomerImageDefinitionName,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("CREATE curated image version with missed image definition id, version and source vhd url")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		Enabled: true,
	})
	s.Require().ErrorContains(err, "image_definition_id: value is required")
	s.Require().ErrorContains(err, "version: value is required")
	s.Require().ErrorContains(err, "source_vhd_url: value is required")

	s.T().Log("CREATE curated image version with invalid version format")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.aa.bb",
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
		Enabled:           true,
	})
	s.Require().ErrorContains(err, "version: value does not match regex pattern")

	s.T().Log("CREATE curated image version with invalid source vhd url")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
		SourceVhdUrl:      "www.github.com/invalid url/",
		Enabled:           true,
	})
	s.Require().ErrorContains(err, "source_vhd_url: value must be a valid URI")

	s.T().Log("CREATE curated image version with correct params")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
		Enabled:           true,
	})
	s.Require().NoError(err)

	s.waitForAdminImageVersionProvisionFailed(createImageDefinitionResp.ImageDefinition.Id, "1.2.3")

	s.T().Log("CREATE curated image version with existing version")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
		SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
		Enabled:           true,
	})
	s.Require().ErrorContains(err, "image version with this version already exists")

	s.T().Log("UPDATE curated image version with missed image definition id and version")

	_, err = s.adminTwirpClient.UpdateCuratedImageVersion(s.ctx, &adminapi.UpdateCuratedImageVersionRequest{
		Enabled: false,
	})
	s.Require().ErrorContains(err, "image_definition_id: value is required")
	s.Require().ErrorContains(err, "version: value is required")

	s.T().Log("CREATE second image definition with correct params")

	createImageDefinitionResp2, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         validCuratedImageDefinitionName2,
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
		Enabled:      true,
	})
	s.Require().NoError(err)

	s.T().Log("UPDATE name of the second image definition to be equal to first image definition")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp2.ImageDefinition.Id,
		Name:              validCuratedImageDefinitionName,
		Enabled:           true,
	})
	s.Require().ErrorContains(err, "image definition with this name already exists")

	s.T().Log("DELETE second image definition")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp2.ImageDefinition.Id,
	})
	s.Require().NoError(err)

	s.T().Log("DELETE image definition before deleting image versions")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().ErrorContains(err, "failed to delete image definition")

	s.T().Log("DELETE image version via Customer API")

	_, err = s.customerTwirpClient.DeleteCustomerImageVersion(s.ctx, &imagesapi.DeleteCustomerImageVersionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "owner"},
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("DELETE image version via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
	})
	s.Require().NoError(err)

	s.waitForAdminImageVersionDeletion(createImageDefinitionResp.ImageDefinition.Id, "1.2.3")

	s.T().Log("DELETE image definition via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
}
