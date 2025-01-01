//nolint:all
package main

import (
	"context"
	"fmt"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
)

func runCustomScenario(ctx context.Context, imagesApiClient imagesapi.ImageManagementService, adminApiClient adminapi.ImageManagementAdminService, sourceVhdUrl string) error {
	fmt.Println("Empty scenario")

	// DON'T COMMIT CHANGES IN THIS SCENARIO
	// This scenario is kept an empty in "main" branch intentionally.
	// So developers can quickly modify it locally to cover some specific scenario, validate it locally and then revert.
	// Use "script/dev-client custom" to call this scenario

	return nil
}
