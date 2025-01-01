package azure

import (
	"context"
	"net/http"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/arm"
	azfake "github.com/Azure/azure-sdk-for-go/sdk/azcore/fake"
	armComputeFakes "github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5/fake"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armresources"
	armResourcesFakes "github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armresources/fake"
	armStorageFakes "github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/storage/armstorage/fake"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/pageblob"
	"github.com/github/hosted-compute-ims/internal/azure/clientbuilder"
)

var (
	fakeResourcesServer            *armResourcesFakes.Server
	fakeResourceGroupsServer       *armResourcesFakes.ResourceGroupsServer
	fakeStorageAccountsServer      *armStorageFakes.AccountsServer
	fakeStorageContainersServer    *armStorageFakes.BlobContainersServer
	fakeGalleriesServer            *armComputeFakes.GalleriesServer
	fakeGalleryImagesServer        *armComputeFakes.GalleryImagesServer
	fakeGalleryImageVersionsServer *armComputeFakes.GalleryImageVersionsServer
)

func setup() *AzureClient {
	fakeResourcesServer = &armResourcesFakes.Server{}
	fakeResourceGroupsServer = &armResourcesFakes.ResourceGroupsServer{}
	fakeStorageAccountsServer = &armStorageFakes.AccountsServer{}
	fakeStorageContainersServer = &armStorageFakes.BlobContainersServer{}
	fakeGalleriesServer = &armComputeFakes.GalleriesServer{}
	fakeGalleryImagesServer = &armComputeFakes.GalleryImagesServer{}
	fakeGalleryImageVersionsServer = &armComputeFakes.GalleryImageVersionsServer{}

	return &AzureClient{
		clientBuilder: clientbuilder.NewClientBuilderWithClientOptions(
			&azfake.TokenCredential{},
			&arm.ClientOptions{ClientOptions: azcore.ClientOptions{Transport: armResourcesFakes.NewServerTransport(fakeResourcesServer)}},
			&arm.ClientOptions{ClientOptions: azcore.ClientOptions{Transport: armResourcesFakes.NewResourceGroupsServerTransport(fakeResourceGroupsServer)}},
			&arm.ClientOptions{ClientOptions: azcore.ClientOptions{Transport: armStorageFakes.NewAccountsServerTransport(fakeStorageAccountsServer)}},
			&arm.ClientOptions{ClientOptions: azcore.ClientOptions{Transport: armStorageFakes.NewBlobContainersServerTransport(fakeStorageContainersServer)}},
			&arm.ClientOptions{ClientOptions: azcore.ClientOptions{Transport: armComputeFakes.NewGalleriesServerTransport(fakeGalleriesServer)}},
			&arm.ClientOptions{ClientOptions: azcore.ClientOptions{Transport: armComputeFakes.NewGalleryImagesServerTransport(fakeGalleryImagesServer)}},
			&arm.ClientOptions{ClientOptions: azcore.ClientOptions{Transport: armComputeFakes.NewGalleryImageVersionsServerTransport(fakeGalleryImageVersionsServer)}},
			&pageblob.ClientOptions{},
		),
	}
}

func mockResourceExistence(resourceId string, exist bool) {
	resourceId = strings.TrimLeft(resourceId, "/")

	fakeResourcesServer.GetByID = func(ctx context.Context, id string, apiVersion string, options *armresources.ClientGetByIDOptions) (resp azfake.Responder[armresources.ClientGetByIDResponse], errResp azfake.ErrorResponder) {
		if id == resourceId && exist {
			resp.SetResponse(http.StatusOK, armresources.ClientGetByIDResponse{}, nil)
		} else {
			errResp.SetResponseError(http.StatusNotFound, "Resource not found")
		}

		return
	}
}
