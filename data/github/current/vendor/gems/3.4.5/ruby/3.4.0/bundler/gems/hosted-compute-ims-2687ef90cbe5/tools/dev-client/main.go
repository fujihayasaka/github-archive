//nolint:all
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
)

type Scenario struct {
	ImageRequired bool
	Func          func(context.Context, imagesapi.ImageManagementService, adminapi.ImageManagementAdminService, internalapi.InternalImageManagementService, *devClientImage) error
}

var KnownScenarios = map[string]Scenario{
	"health": {
		ImageRequired: false,
		Func:          validateApiHealth,
	},
	"list-curated": {
		ImageRequired: false,
		Func:          listCuratedImages,
	},
	"upload-curated": {
		ImageRequired: true,
		Func:          queueCuratedImage,
	},
	"upload-customer": {
		ImageRequired: true,
		Func:          queueCustomerImage,
	},
	"upload-macos": {
		ImageRequired: false,
		Func:          queueMacosImage,
	},
	"custom": {
		ImageRequired: true,
		Func:          runCustomScenario,
	},
}

func main() {
	if err := realMain(); err != nil {
		log.Fatal(err)
	}
}

func realMain() error {
	ctx := context.Background()

	appParams, err := parseParameters()
	if err != nil {
		return err
	}

	imagesApiClient := imagesapi.NewImageManagementServiceProtobufClient(appParams.ServerUrl, &http.Client{})
	adminApiClient := adminapi.NewImageManagementAdminServiceProtobufClient(appParams.ServerUrl, &http.Client{})
	internalApiClient := internalapi.NewInternalImageManagementServiceProtobufClient(appParams.ServerUrl, &http.Client{})

	fmt.Printf("Running scenario: %s\n", appParams.ScenarioName)

	if err := appParams.Scenario.Func(ctx, imagesApiClient, adminApiClient, internalApiClient, appParams.Image); err != nil {
		return err
	}

	fmt.Printf("Finished scenario: %s\n", appParams.ScenarioName)

	return nil
}

func validateApiHealth(ctx context.Context, imagesApiClient imagesapi.ImageManagementService, adminApiClient adminapi.ImageManagementAdminService, internalApiClient internalapi.InternalImageManagementService, image *devClientImage) error {
	_, err := imagesApiClient.ListCuratedImageDefinitions(ctx, &imagesapi.ListCuratedImageDefinitionsRequest{Owner: &sharedapi.Actor{GlobalId: "test-user"}})
	if err != nil {
		fmt.Println("Customer api health check failed.")
		return fmt.Errorf("failed to list curated image definitions using customers api: %w", err)
	}

	_, err = adminApiClient.ListCuratedImageDefinitions(ctx, &adminapi.ListCuratedImageDefinitionsRequest{})
	if err != nil {
		fmt.Println("Admin api health check failed.")
		return fmt.Errorf("failed to list curated image definitions using admin api: %w", err)
	}

	fmt.Println("API health validated successfully")

	return nil
}

func listCuratedImages(ctx context.Context, imagesApiClient imagesapi.ImageManagementService, adminApiClient adminapi.ImageManagementAdminService, internalApiClient internalapi.InternalImageManagementService, image *devClientImage) error {
	imageDefinitionsResp, err := adminApiClient.ListCuratedImageDefinitions(ctx, &adminapi.ListCuratedImageDefinitionsRequest{})
	if err != nil {
		return fmt.Errorf("failed to list curated image definitions using admin api: %w", err)
	}

	imageDefinitions := make([]proto.Message, 0, len(imageDefinitionsResp.ImageDefinitions))
	for _, im := range imageDefinitionsResp.ImageDefinitions {
		imageDefinitions = append(imageDefinitions, im)
	}

	printResponse("Curated images", imageDefinitions...)

	return nil
}

func queueCuratedImage(ctx context.Context, imagesApiClient imagesapi.ImageManagementService, adminApiClient adminapi.ImageManagementAdminService, internalApiClient internalapi.InternalImageManagementService, image *devClientImage) error {
	createImageDefitionRequest := &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         generateImageDefinitionName(),
		OwnerId:      models.GithubOwnerId,
		OsType:       image.OsType,
		Architecture: image.Architecture,
		Enabled:      true,
	}

	createImageDefinitionResponse, err := adminApiClient.CreateCuratedImageDefinition(ctx, createImageDefitionRequest)
	if err != nil {
		return fmt.Errorf("failed to create curated image definition: %w", err)
	}

	imageDefinition := createImageDefinitionResponse.ImageDefinition
	printResponse("Created curated image definition", imageDefinition)

	createImageVersionRequest := &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinition.Id,
		Version:           "1.0.0",
		Enabled:           true,
		SourceVhdUrl:      image.SourceVhdUrl,
	}

	createImageVersionResponse, err := adminApiClient.CreateCuratedImageVersion(ctx, createImageVersionRequest)
	if err != nil {
		return fmt.Errorf("failed to create curated image version: %w", err)
	}

	imageVersion := createImageVersionResponse.ImageVersion
	printResponse("Created curated image version", imageVersion)

	return nil
}

func queueCustomerImage(ctx context.Context, imagesApiClient imagesapi.ImageManagementService, adminApiClient adminapi.ImageManagementAdminService, internalApiClient internalapi.InternalImageManagementService, image *devClientImage) error {
	imageOwner := generateOwner()

	createImageDefitionRequest := &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:        &sharedapi.Actor{GlobalId: imageOwner},
		Name:         generateImageDefinitionName(),
		OsType:       image.OsType,
		Architecture: image.Architecture,
	}

	createImageDefinitionResponse, err := imagesApiClient.CreateCustomerImageDefinition(ctx, createImageDefitionRequest)
	if err != nil {
		return fmt.Errorf("failed to create customer image definition: %w", err)
	}

	imageDefinition := createImageDefinitionResponse.ImageDefinition
	fmt.Printf("OwnerId: %s\n", imageOwner)
	printResponse("Created customer image definition", imageDefinition)

	createImageVersionRequest := &imagesapi.CreateCustomerImageVersionRequest{
		Owner:             &sharedapi.Actor{GlobalId: imageOwner},
		ImageDefinitionId: imageDefinition.Id,
		Version:           "1.0.0",
		SourceVhdUrl:      image.SourceVhdUrl,
	}

	createImageVersionResponse, err := imagesApiClient.CreateCustomerImageVersion(ctx, createImageVersionRequest)
	if err != nil {
		return fmt.Errorf("failed to create customer image version: %w", err)
	}

	imageVersion := createImageVersionResponse.ImageVersion
	printResponse("Created customer image version", imageVersion)

	return nil
}

func queueMacosImage(ctx context.Context, imagesApiClient imagesapi.ImageManagementService, adminApiClient adminapi.ImageManagementAdminService, internalApiClient internalapi.InternalImageManagementService, image *devClientImage) error {
	imageResourceId := fmt.Sprintf("macos://%s", uuid.New().String())

	createImageDefitionRequest := &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         generateImageDefinitionName(),
		OsType:       sharedapi.OsType_MacOS,
		Architecture: sharedapi.Architecture_X64,
		Enabled:      true,
	}

	createImageDefinitionResponse, err := adminApiClient.CreateCuratedImageDefinition(ctx, createImageDefitionRequest)
	if err != nil {
		return fmt.Errorf("failed to create curated image definition: %w", err)
	}

	imageDefinition := createImageDefinitionResponse.ImageDefinition
	printResponse("Created curated image definition", imageDefinition)

	createImageVersionRequest := &adminapi.CreateCuratedImageVersionRequest{
		ImageDefinitionId: imageDefinition.Id,
		Version:           "1.0.0",
		Enabled:           true,
		SourceVhdUrl:      imageResourceId,
	}

	createImageVersionResponse, err := adminApiClient.CreateCuratedImageVersion(ctx, createImageVersionRequest)
	if err != nil {
		return fmt.Errorf("failed to create curated image version: %w", err)
	}

	imageVersion := createImageVersionResponse.ImageVersion
	printResponse("Created curated image version", imageVersion)

	return nil
}
