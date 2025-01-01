//nolint:all
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
)

type Scenario = string

const (
	HealthScenario   Scenario = "health"
	CuratedScenario  Scenario = "curated"
	CustomerScenario Scenario = "customer"
	CustomScenario   Scenario = "custom"
)

var KnownScenarios = []Scenario{HealthScenario, CuratedScenario, CustomerScenario, CustomScenario}

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

	fmt.Printf("Running scenario: %s\n", appParams.Scenario)

	switch appParams.Scenario {
	case HealthScenario:
		err = validateApiHealth(ctx, imagesApiClient, adminApiClient)
	case CuratedScenario:
		err = queueCuratedImage(ctx, adminApiClient, appParams.ImageVhdUrl)
	case CustomerScenario:
		err = queueCustomerImage(ctx, imagesApiClient, appParams.ImageVhdUrl)
	case CustomScenario:
		err = runCustomScenario(ctx, imagesApiClient, adminApiClient, appParams.ImageVhdUrl)
	}

	if err != nil {
		return err
	}

	fmt.Printf("Finished scenario: %s\n", appParams.Scenario)

	return nil
}

func validateApiHealth(ctx context.Context, imagesApiClient imagesapi.ImageManagementService, adminApiClient adminapi.ImageManagementAdminService) error {
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

func queueCuratedImage(ctx context.Context, adminApiClient adminapi.ImageManagementAdminService, sourceVhdUrl string) error {
	createImageDefitionRequest := &adminapi.CreateCuratedImageDefinitionRequest{
		Name:         generateImageDefinitionName(),
		OsType:       sharedapi.OsType_Linux,
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
		SourceVhdUrl:      sourceVhdUrl,
	}

	createImageVersionResponse, err := adminApiClient.CreateCuratedImageVersion(ctx, createImageVersionRequest)
	if err != nil {
		return fmt.Errorf("failed to create curated image version: %w", err)
	}

	imageVersion := createImageVersionResponse.ImageVersion
	printResponse("Created curated image version", imageVersion)

	return nil
}

func queueCustomerImage(ctx context.Context, customerApiClient imagesapi.ImageManagementService, sourceVhdUrl string) error {
	imageOwner := generateOwner()

	createImageDefitionRequest := &imagesapi.CreateCustomerImageDefinitionRequest{
		Owner:        &sharedapi.Actor{GlobalId: imageOwner},
		Name:         generateImageDefinitionName(),
		OsType:       sharedapi.OsType_Linux,
		Architecture: sharedapi.Architecture_X64,
	}

	createImageDefinitionResponse, err := customerApiClient.CreateCustomerImageDefinition(ctx, createImageDefitionRequest)
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
		SourceVhdUrl:      sourceVhdUrl,
	}

	createImageVersionResponse, err := customerApiClient.CreateCustomerImageVersion(ctx, createImageVersionRequest)
	if err != nil {
		return fmt.Errorf("failed to create customer image version: %w", err)
	}

	imageVersion := createImageVersionResponse.ImageVersion
	printResponse("Created customer image version", imageVersion)

	return nil
}
