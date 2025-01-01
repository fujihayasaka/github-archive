package e2e

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/wrapperspb"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
)

// This is 'User:29457092' DotcomActor as a Global ID
const OtherUser = "U_kgDOAcF6xA"

type CuratedImagesE2ETestSuite struct {
	BaseE2ETestSuite
}

func TestCuratedImagesE2ETestSuite(t *testing.T) {
	// tests within suite will run in sequential order unless t.Parallel() is called within individual tests
	// for now, only suites will run in parallel
	t.Parallel()
	suite.Run(t, new(CuratedImagesE2ETestSuite))
}

func (s *CuratedImagesE2ETestSuite) Test_CreateImageDefinitionsAndVersionsForGitHubOwner() {
	var (
		enabledImageDefinition = &adminapi.ImageDefinition{
			Name:                       fmt.Sprintf("%s-curated-create-github-def-1", s.uniquePrefix),
			OsType:                     sharedapi.OsType_Linux,
			Architecture:               sharedapi.Architecture_X64,
			Enabled:                    true,
			OwnerId:                    models.GithubOwnerId,
			IsImageGenerationSupported: true,
		}
		disabledImageDefinition = &adminapi.ImageDefinition{
			Name:                       fmt.Sprintf("%s-curated-create-github-def-2", s.uniquePrefix),
			OsType:                     sharedapi.OsType_Windows,
			Architecture:               sharedapi.Architecture_Arm64,
			Enabled:                    false,
			OwnerId:                    models.GithubOwnerId,
			IsImageGenerationSupported: false,
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
		user                                   = &sharedapi.Actor{GlobalId: "user-1"}
	)

	s.T().Log("CREATE enabled curated image definition via Admin API")

	enabledImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:                       enabledImageDefinition.Name,
		OsType:                     enabledImageDefinition.OsType,
		Architecture:               enabledImageDefinition.Architecture,
		Enabled:                    enabledImageDefinition.Enabled,
		OwnerId:                    enabledImageDefinition.OwnerId,
		IsImageGenerationSupported: enabledImageDefinition.IsImageGenerationSupported,
	})
	s.Require().NoError(err)
	enabledImageDefinition.Id = enabledImageDefinitionResp.ImageDefinition.Id

	s.T().Log("CREATE disabled curated image definition via Admin API")

	disabledImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:                       disabledImageDefinition.Name,
		OsType:                     disabledImageDefinition.OsType,
		Architecture:               disabledImageDefinition.Architecture,
		Enabled:                    disabledImageDefinition.Enabled,
		OwnerId:                    disabledImageDefinition.OwnerId,
		IsImageGenerationSupported: disabledImageDefinition.IsImageGenerationSupported,
	})
	s.Require().NoError(err)
	disabledImageDefinition.Id = disabledImageDefinitionResp.ImageDefinition.Id

	s.T().Log("GET enabled curated image definition before adding image versions via Admin API")

	getImageDefinitionResp, err := s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(enabledImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(enabledImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(enabledImageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(enabledImageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(enabledImageDefinition.Enabled, getImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(enabledImageDefinition.OwnerId, getImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal("", getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(enabledImageDefinition.IsImageGenerationSupported, getImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)

	s.T().Log("GET disabled curated image definition before adding image versions via Admin API")

	getImageDefinitionResp, err = s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(disabledImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(disabledImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(disabledImageDefinition.OsType, getImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(disabledImageDefinition.Architecture, getImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(disabledImageDefinition.Enabled, getImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(disabledImageDefinition.OwnerId, getImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal("", getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(disabledImageDefinition.IsImageGenerationSupported, getImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)

	s.T().Log("GET enabled curated image definition before adding image versions via Customer API")

	getCustomerImageDefinitionResp, err := s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             user,
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(enabledImageDefinition.Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(enabledImageDefinition.Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(enabledImageDefinition.OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(enabledImageDefinition.Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(enabledImageDefinition.Enabled, getCustomerImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(enabledImageDefinition.OwnerId, getCustomerImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal("", getCustomerImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getCustomerImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(int32(0), getCustomerImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(enabledImageDefinition.IsImageGenerationSupported, getCustomerImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)

	s.T().Log("GET disabled curated image definition before adding image versions via Customer API")

	getCustomerImageDefinitionResp, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             user,
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(disabledImageDefinition.Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(disabledImageDefinition.Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(disabledImageDefinition.OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(disabledImageDefinition.Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(disabledImageDefinition.Enabled, getCustomerImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(disabledImageDefinition.OwnerId, getCustomerImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal("", getCustomerImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getCustomerImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(int32(0), getCustomerImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(disabledImageDefinition.IsImageGenerationSupported, getCustomerImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)

	s.T().Log("LIST curated image definitions before adding image versions via Admin API")

	listImageDefinitionsResp, err := s.adminTwirpClient.ListCuratedImageDefinitions(s.ctx, &adminapi.ListCuratedImageDefinitionsRequest{})
	s.Require().NoError(err)
	listedImageDefinitions := s.filterTestCuratedImageDefinitions(listImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(2, len(listedImageDefinitions))
	s.Require().Equal(enabledImageDefinition.Id, listedImageDefinitions[0].Id)
	s.Require().Equal(enabledImageDefinition.Name, listedImageDefinitions[0].Name)
	s.Require().Equal(enabledImageDefinition.OwnerId, listedImageDefinitions[0].OwnerId)
	s.Require().Equal(enabledImageDefinition.OsType, listedImageDefinitions[0].OsType)
	s.Require().Equal(enabledImageDefinition.Architecture, listedImageDefinitions[0].Architecture)
	s.Require().Equal("", listedImageDefinitions[0].LatestVersion)
	s.Require().Equal(int32(0), listedImageDefinitions[0].LatestVersionSizeGb)
	s.Require().Equal(int32(0), listedImageDefinitions[0].ImageVersionsCount)
	s.Require().Equal(enabledImageDefinition.IsImageGenerationSupported, listedImageDefinitions[0].IsImageGenerationSupported)
	s.Require().Equal(disabledImageDefinition.Id, listedImageDefinitions[1].Id)
	s.Require().Equal(disabledImageDefinition.Name, listedImageDefinitions[1].Name)
	s.Require().Equal(disabledImageDefinition.OwnerId, listedImageDefinitions[1].OwnerId)
	s.Require().Equal(disabledImageDefinition.OsType, listedImageDefinitions[1].OsType)
	s.Require().Equal(disabledImageDefinition.Architecture, listedImageDefinitions[1].Architecture)
	s.Require().Equal("", listedImageDefinitions[1].LatestVersion)
	s.Require().Equal(int32(0), listedImageDefinitions[1].LatestVersionSizeGb)
	s.Require().Equal(int32(0), listedImageDefinitions[1].ImageVersionsCount)
	s.Require().Equal(disabledImageDefinition.IsImageGenerationSupported, listedImageDefinitions[1].IsImageGenerationSupported)

	s.T().Log("LIST curated image definitions before adding image versions via Customer API")

	listCustomerImageDefinitionsResp, err := s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           user,
		IncludeDisabled: true,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions := s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(2, len(listedCustomerImageDefinitions))
	s.Require().Equal(enabledImageDefinition.Id, listedCustomerImageDefinitions[0].Id)
	s.Require().Equal(enabledImageDefinition.Name, listedCustomerImageDefinitions[0].Name)
	s.Require().Equal(enabledImageDefinition.OwnerId, listedCustomerImageDefinitions[0].OwnerId)
	s.Require().Equal(enabledImageDefinition.OsType, listedCustomerImageDefinitions[0].OsType)
	s.Require().Equal(enabledImageDefinition.Architecture, listedCustomerImageDefinitions[0].Architecture)
	s.Require().Equal("", listedCustomerImageDefinitions[0].LatestVersion)
	s.Require().Equal(int32(0), listedCustomerImageDefinitions[0].LatestVersionSizeGb)
	s.Require().Equal(int32(0), listedCustomerImageDefinitions[0].ImageVersionsCount)
	s.Require().Equal(enabledImageDefinition.IsImageGenerationSupported, listedCustomerImageDefinitions[0].IsImageGenerationSupported)
	s.Require().Equal(disabledImageDefinition.Id, listedCustomerImageDefinitions[1].Id)
	s.Require().Equal(disabledImageDefinition.Name, listedCustomerImageDefinitions[1].Name)
	s.Require().Equal(disabledImageDefinition.OwnerId, listedCustomerImageDefinitions[1].OwnerId)
	s.Require().Equal(disabledImageDefinition.OsType, listedCustomerImageDefinitions[1].OsType)
	s.Require().Equal(disabledImageDefinition.Architecture, listedCustomerImageDefinitions[1].Architecture)
	s.Require().Equal("", listedCustomerImageDefinitions[1].LatestVersion)
	s.Require().Equal(int32(0), listedCustomerImageDefinitions[1].LatestVersionSizeGb)
	s.Require().Equal(int32(0), listedCustomerImageDefinitions[1].ImageVersionsCount)
	s.Require().Equal(disabledImageDefinition.IsImageGenerationSupported, listedCustomerImageDefinitions[1].IsImageGenerationSupported)

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

	s.T().Log("GET image version for enabled image definition via Admin API")

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

	s.T().Log("GET image version for disabled image definition via Admin API")

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

	s.T().Log("GET enabled curated image definition after adding image versions via Admin API")

	getImageDefinitionResp, err = s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(enabledImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(enabledImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal("", getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(int32(3), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(enabledImageDefinition.IsImageGenerationSupported, getImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)

	s.T().Log("GET disabled curated image definition after adding image versions via Admin API")

	getImageDefinitionResp, err = s.adminTwirpClient.GetCuratedImageDefinition(s.ctx, &adminapi.GetCuratedImageDefinitionRequest{
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(disabledImageDefinition.Id, getImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(disabledImageDefinition.Name, getImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal("", getImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(int32(1), getImageDefinitionResp.ImageDefinition.ImageVersionsCount)
	s.Require().Equal(disabledImageDefinition.IsImageGenerationSupported, getImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)

	s.T().Log("GET enabled image definition after adding image versions via Customer API")

	getCustomerImageDefinitionResp, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(enabledImageDefinition.Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(enabledImageDefinition.Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(enabledImageDefinition.OwnerId, getCustomerImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal(enabledImageDefinition.OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(enabledImageDefinition.Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(true, getCustomerImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(sharedapi.ImageDefinitionState_ImageDefinitionReady, getCustomerImageDefinitionResp.ImageDefinition.State)
	s.Require().Equal("", getCustomerImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getCustomerImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(enabledImageDefinition.IsImageGenerationSupported, getCustomerImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)

	s.T().Log("GET disabled image definition after adding image versions via Customer API")

	getCustomerImageDefinitionResp, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(disabledImageDefinition.Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(disabledImageDefinition.Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(disabledImageDefinition.OwnerId, getCustomerImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal(disabledImageDefinition.OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(disabledImageDefinition.Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(false, getCustomerImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(sharedapi.ImageDefinitionState_ImageDefinitionReady, getCustomerImageDefinitionResp.ImageDefinition.State)
	s.Require().Equal("", getCustomerImageDefinitionResp.ImageDefinition.LatestVersion)
	s.Require().Equal(int32(0), getCustomerImageDefinitionResp.ImageDefinition.LatestVersionSizeGb)
	s.Require().Equal(disabledImageDefinition.IsImageGenerationSupported, getCustomerImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)

	s.T().Log("LIST image definitions without IncludeDisabled via Customer API")

	listCustomerImageDefinitionsResp, err = s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: OtherUser},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(1, len(listedCustomerImageDefinitions))
	s.Require().Equal(enabledImageDefinition.Id, listedCustomerImageDefinitions[0].Id)
	s.Require().Equal(enabledImageDefinition.Name, listedCustomerImageDefinitions[0].Name)
	s.Require().Equal(enabledImageDefinition.OwnerId, listedCustomerImageDefinitions[0].OwnerId)
	s.Require().True(listedCustomerImageDefinitions[0].Enabled)
	s.Require().True(listedCustomerImageDefinitions[0].IsImageGenerationSupported)

	s.T().Log("LIST image definitions with IncludeDisabled via Customer API")

	listCustomerImageDefinitionsResp, err = s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: OtherUser},
		IncludeDisabled: true,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(2, len(listedCustomerImageDefinitions))
	s.Require().Equal(enabledImageDefinition.Id, listedCustomerImageDefinitions[0].Id)
	s.Require().Equal(enabledImageDefinition.Name, listedCustomerImageDefinitions[0].Name)
	s.Require().Equal(enabledImageDefinition.OwnerId, listedCustomerImageDefinitions[0].OwnerId)
	s.Require().Equal(true, listedCustomerImageDefinitions[0].Enabled)
	s.Require().Equal(true, listedCustomerImageDefinitions[0].IsImageGenerationSupported)
	s.Require().Equal(disabledImageDefinition.Id, listedCustomerImageDefinitions[1].Id)
	s.Require().Equal(disabledImageDefinition.Name, listedCustomerImageDefinitions[1].Name)
	s.Require().Equal(disabledImageDefinition.OwnerId, listedCustomerImageDefinitions[1].OwnerId)
	s.Require().Equal(false, listedCustomerImageDefinitions[1].Enabled)
	s.Require().Equal(false, listedCustomerImageDefinitions[1].IsImageGenerationSupported)

	s.T().Log("LIST image versions for enabled image definition via Customer API")

	listCustomerImageVersionsResp, err := s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(len(sortedEnabledImageVersions), len(listCustomerImageVersionsResp.ImageVersions))
	for ind := 0; ind < len(sortedEnabledImageVersions); ind++ {
		s.Require().Equal(sortedEnabledImageVersions[ind], listCustomerImageVersionsResp.ImageVersions[ind].Version)
	}

	s.T().Log("GET image version for enabled image definition via Customer API")

	for _, iv := range addedImageVersions {
		getCustomerImageVersionsResp, err := s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: OtherUser},
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
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image version for disabled image definition via Customer API")

	_, err = s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
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
		deleteImageVersionResponse, err := s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: enabledImageDefinition.Id,
			Version:           version,
		})
		s.Require().NoError(err)
		s.Require().NotNil(deleteImageVersionResponse)
		s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)
	}

	deleteImageVersionResponse, err := s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: disabledImageDefinition.Id,
		Version:           imageVersionForDisabledImageDefinition,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageVersionResponse)
	s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)

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
		Owner:           &sharedapi.Actor{GlobalId: OtherUser},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(0, len(listedCustomerImageDefinitions))

	s.T().Log("LIST image definitions include disabled true via Customer API")

	listCustomerImageDefinitionsResp, err = s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: OtherUser},
		IncludeDisabled: true,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(0, len(listedCustomerImageDefinitions))
}

func (s *CuratedImagesE2ETestSuite) Test_CreateImageDefinitionsAndVersionsForPartnerOwner() {
	var (
		enabledImageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-create-partner-def-1", s.uniquePrefix),
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			Enabled:      true,
			OwnerId:      models.PartnerOwnerId,
		}
		disabledImageDefinition = &adminapi.ImageDefinition{
			Name:         fmt.Sprintf("%s-curated-create-partner-def-2", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
			Enabled:      false,
			OwnerId:      models.PartnerOwnerId,
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
		OwnerId:      enabledImageDefinition.OwnerId,
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
		OwnerId:      disabledImageDefinition.OwnerId,
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

	s.T().Log("LIST curated image definitions via Admin API")

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
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(enabledImageDefinition.Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(enabledImageDefinition.Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(enabledImageDefinition.OwnerId, getCustomerImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal(enabledImageDefinition.OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(enabledImageDefinition.Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(true, getCustomerImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(sharedapi.ImageDefinitionState_ImageDefinitionReady, getCustomerImageDefinitionResp.ImageDefinition.State)

	s.T().Log("GET disabled image definition via Customer API")

	getCustomerImageDefinitionResp, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(disabledImageDefinition.Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(disabledImageDefinition.Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(disabledImageDefinition.OwnerId, getCustomerImageDefinitionResp.ImageDefinition.OwnerId)
	s.Require().Equal(disabledImageDefinition.OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(disabledImageDefinition.Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(false, getCustomerImageDefinitionResp.ImageDefinition.Enabled)
	s.Require().Equal(sharedapi.ImageDefinitionState_ImageDefinitionReady, getCustomerImageDefinitionResp.ImageDefinition.State)

	s.T().Log("LIST image definitions without IncludeDisabled via Customer API")

	listCustomerImageDefinitionsResp, err := s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: OtherUser},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions := s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(1, len(listedCustomerImageDefinitions))
	s.Require().Equal(enabledImageDefinition.Id, listedCustomerImageDefinitions[0].Id)
	s.Require().Equal(enabledImageDefinition.Name, listedCustomerImageDefinitions[0].Name)
	s.Require().Equal(enabledImageDefinition.OwnerId, listedCustomerImageDefinitions[0].OwnerId)

	s.T().Log("LIST image definitions with IncludeDisabled via Customer API")

	listCustomerImageDefinitionsResp, err = s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: OtherUser},
		IncludeDisabled: true,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(2, len(listedCustomerImageDefinitions))
	s.Require().Equal(enabledImageDefinition.Id, listedCustomerImageDefinitions[0].Id)
	s.Require().Equal(enabledImageDefinition.Name, listedCustomerImageDefinitions[0].Name)
	s.Require().Equal(enabledImageDefinition.OwnerId, listedCustomerImageDefinitions[0].OwnerId)
	s.Require().Equal(disabledImageDefinition.Id, listedCustomerImageDefinitions[1].Id)
	s.Require().Equal(disabledImageDefinition.Name, listedCustomerImageDefinitions[1].Name)
	s.Require().Equal(disabledImageDefinition.OwnerId, listedCustomerImageDefinitions[1].OwnerId)

	s.T().Log("LIST image versions for enabled image definition via Customer API")

	listCustomerImageVersionsResp, err := s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: enabledImageDefinition.Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(len(sortedEnabledImageVersions), len(listCustomerImageVersionsResp.ImageVersions))
	for ind := 0; ind < len(sortedEnabledImageVersions); ind++ {
		s.Require().Equal(sortedEnabledImageVersions[ind], listCustomerImageVersionsResp.ImageVersions[ind].Version)
	}

	s.T().Log("GET image version for enabled image definition via Customer API")

	for _, iv := range addedImageVersions {
		getCustomerImageVersionsResp, err := s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: OtherUser},
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
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: disabledImageDefinition.Id,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image version for disabled image definition via Customer API")

	_, err = s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
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
		deleteImageVersionResponse, err := s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: enabledImageDefinition.Id,
			Version:           version,
		})
		s.Require().NoError(err)
		s.Require().NotNil(deleteImageVersionResponse)
		s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)
	}

	deleteImageVersionResponse, err := s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: disabledImageDefinition.Id,
		Version:           imageVersionForDisabledImageDefinition,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageVersionResponse)
	s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)

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
		Owner:           &sharedapi.Actor{GlobalId: OtherUser},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(0, len(listedCustomerImageDefinitions))

	s.T().Log("LIST image definitions include disabled true via Customer API")

	listCustomerImageDefinitionsResp, err = s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: OtherUser},
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
			OwnerId:      models.GithubOwnerId,
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
		OwnerId:      imageDefinition.OwnerId,
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
	s.Require().False(getImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)

	s.T().Log("UPDATE curated image definition via Admin API")

	_, err = s.adminTwirpClient.UpdateCuratedImageDefinition(s.ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
		ImageDefinitionId:          imageDefinition.Id,
		Name:                       newImageDefinitionName,
		Enabled:                    false,
		IsImageGenerationSupported: true,
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
	s.Require().True(getImageDefinitionResp.ImageDefinition.IsImageGenerationSupported)

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

	deleteImageVersionResponse, err := s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinition.Id,
		Version:           imageVersion.Version,
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageVersionResponse)
	s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)

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
			FeatureFlag:  string(featureflags.TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled),
			OwnerId:      models.GithubOwnerId,
		},
		{
			Name:         fmt.Sprintf("%s-feature-flag-def-2", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
			Enabled:      true,
			FeatureFlag:  string(featureflags.TEST_FeatureFlag_E2E_TestFlag_GloballyDisabled),
			OwnerId:      models.GithubOwnerId,
		},
		{
			Name:         fmt.Sprintf("%s-feature-flag-def-3", s.uniquePrefix),
			OsType:       sharedapi.OsType_Windows,
			Architecture: sharedapi.Architecture_Arm64,
			Enabled:      false,
			FeatureFlag:  string(featureflags.TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner),
			OwnerId:      models.GithubOwnerId,
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
			OwnerId:      imageDefinition.OwnerId,
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
		Owner:           &sharedapi.Actor{GlobalId: featureflags.TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions := s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(2, len(listedCustomerImageDefinitions))

	s.T().Log("LIST curated image definitions for other user via Customer API")
	listCustomerImageDefinitionsResp, err = s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: OtherUser},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	listedCustomerImageDefinitions = s.filterTestCustomerImageDefinitions(listCustomerImageDefinitionsResp.ImageDefinitions)
	s.Require().Equal(1, len(listedCustomerImageDefinitions))

	s.T().Log("GET image definition with feature flag globally enabled via Customer API")
	getCustomerImageDefinitionResp, err := s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: imageDefinitions[0].Id,
	})

	s.Require().NoError(err)
	s.Require().Equal(imageDefinitions[0].Id, getCustomerImageDefinitionResp.ImageDefinition.Id)
	s.Require().Equal(imageDefinitions[0].Name, getCustomerImageDefinitionResp.ImageDefinition.Name)
	s.Require().Equal(imageDefinitions[0].OsType, getCustomerImageDefinitionResp.ImageDefinition.OsType)
	s.Require().Equal(imageDefinitions[0].Architecture, getCustomerImageDefinitionResp.ImageDefinition.Architecture)
	s.Require().Equal(true, getCustomerImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("GET image definition with invalid GlobaID")
	getCustomerImageDefinitionResp, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: "invalid_global_id"},
		ImageDefinitionId: imageDefinitions[0].Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(false, getCustomerImageDefinitionResp.ImageDefinition.Enabled)

	s.T().Log("GET image definition with feature flag enabled per user for known user via Customer API")
	getCustomerImageDefinitionResp, err = s.customerTwirpClient.GetCuratedImageDefinition(s.ctx, &imagesapi.GetCuratedImageDefinitionRequest{
		Owner:             &sharedapi.Actor{GlobalId: featureflags.TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID},
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
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
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
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
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
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
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
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: imageDefinitions[0].Id,
	})
	s.Require().NoError(err)
	s.Require().Equal(1, len(listCustomerImageVersionsResp.ImageVersions))

	s.T().Log("LIST image versions for globally enabled image definition via Customer API")

	_, err = s.customerTwirpClient.ListCuratedImageVersions(s.ctx, &imagesapi.ListCuratedImageVersionsRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: imageDefinitions[1].Id,
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("GET image version on globally enabled image definition via Customer API")

	_, err = s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: imageDefinitions[0].Id,
		Version:           "1.0.0",
	})
	s.Require().NoError(err)

	s.T().Log("GET image version on globally disabled image definition via Customer API")
	_, err = s.customerTwirpClient.GetCuratedImageVersion(s.ctx, &imagesapi.GetCuratedImageVersionRequest{
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: imageDefinitions[1].Id,
		Version:           "1.0.0",
	})

	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("DELETE image version via Admin API")

	deleteImageVersionResponse, err := s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinitions[0].Id,
		Version:           "1.0.0",
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageVersionResponse)
	s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)

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
		OwnerId:      models.GithubOwnerId,
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
		Enabled:      true,
	})
	s.Require().NoError(err)

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
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Name:              wrapperspb.String(validCustomerImageDefinitionName),
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("CREATE curated image version with missed image definition id, version and source vhd url")

	_, err = s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
		Enabled: true,
	})
	s.Require().ErrorContains(err, "image_definition_id: value is required")
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
		OwnerId:      models.GithubOwnerId,
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
		Enabled:      true,
	})
	s.Require().NoError(err)

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
		Owner:             &sharedapi.Actor{GlobalId: OtherUser},
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
	})
	s.Require().ErrorContains(err, "image definition is not found")

	s.T().Log("DELETE image version via Admin API")

	deleteImageVersionResponse, err := s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
		Version:           "1.2.3",
	})
	s.Require().NoError(err)
	s.Require().NotNil(deleteImageVersionResponse)
	s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)

	s.waitForAdminImageVersionDeletion(createImageDefinitionResp.ImageDefinition.Id, "1.2.3")

	s.T().Log("DELETE image definition via Admin API")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
}

func (s *CuratedImagesE2ETestSuite) Test_ImageVersionWildcards() {
	type versionIncTestCases struct {
		description    string
		input          string
		expectedOutput string
	}

	var (
		validCuratedImageDefinitionName = fmt.Sprintf("%s-curated-validation-def-3 Ubuntu 22.04", s.uniquePrefix)
		testCases                       = []versionIncTestCases{
			{
				description:    "Initial empty image version",
				input:          "",
				expectedOutput: "1.0.0",
			},
			{
				description:    "Bump minor with empty image version",
				input:          "",
				expectedOutput: "1.1.0",
			},
			{
				description:    "Bump patch with star patch version",
				input:          "1.0.*",
				expectedOutput: "1.0.1",
			},
			{
				description:    "Bump patch with star minor and patch version",
				input:          "1.*.*",
				expectedOutput: "1.1.1",
			},
			{
				description:    "Bump minor with star minor version",
				input:          "1.*",
				expectedOutput: "1.2.0",
			},
		}
	)

	s.T().Log("CREATE image definition with correct params")

	createImageDefinitionResp, err := s.adminTwirpClient.CreateCuratedImageDefinition(s.ctx, &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         validCuratedImageDefinitionName,
		OwnerId:      models.GithubOwnerId,
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
		Enabled:      true,
	})
	s.Require().NoError(err)

	for _, testCase := range testCases {
		s.T().Logf("Test case: %s", testCase.description)

		createImageVersionResp, err := s.adminTwirpClient.CreateCuratedImageVersion(s.ctx, &adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
			Version:           testCase.input,
			SourceVhdUrl:      s.sourceVhdUrlForQuickFail,
			Enabled:           true,
		})

		s.Require().NoError(err)
		s.Require().Equal(testCase.expectedOutput, createImageVersionResp.ImageVersion.Version)
	}

	for _, testCase := range testCases {
		s.T().Logf("DELETE image version: %s", testCase.expectedOutput)

		deleteImageVersionResponse, err := s.adminTwirpClient.DeleteCuratedImageVersion(s.ctx, &adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
			Version:           testCase.expectedOutput,
		})
		s.Require().NoError(err)
		s.Require().NotNil(deleteImageVersionResponse)
		s.Require().Equal(sharedapi.ImageVersionState_Deleting, deleteImageVersionResponse.ImageVersion.State)
	}

	for _, testCase := range testCases {
		s.waitForAdminImageVersionDeletion(createImageDefinitionResp.ImageDefinition.Id, testCase.expectedOutput)
	}

	s.T().Log("DELETE image definition")

	_, err = s.adminTwirpClient.DeleteCuratedImageDefinition(s.ctx, &adminapi.DeleteCuratedImageDefinitionRequest{
		ImageDefinitionId: createImageDefinitionResp.ImageDefinition.Id,
	})
	s.Require().NoError(err)
}
