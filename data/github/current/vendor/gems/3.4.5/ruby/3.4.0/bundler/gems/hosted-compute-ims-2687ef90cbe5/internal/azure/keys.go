package azure

import "fmt"

// base

type ResourceGroupKey struct {
	SubscriptionId string
	ResourceGroup  string
}

func (k *ResourceGroupKey) ResourceGroupResourceId() string {
	return fmt.Sprintf("/subscriptions/%s/resourceGroups/%s", k.SubscriptionId, k.ResourceGroup)
}

// storage

type StorageKey struct {
	ResourceGroupKey
	StorageAccount string
}

func (k *StorageKey) StorageResourceId() string {
	return fmt.Sprintf("%s/providers/Microsoft.Storage/storageAccounts/%s", k.ResourceGroupResourceId(), k.StorageAccount)
}

func (k *StorageKey) BlobServiceUrl() string {
	return fmt.Sprintf("https://%s.blob.core.windows.net", k.StorageAccount)
}

type StorageContainerKey struct {
	StorageKey
	Container string
}

func (k *StorageContainerKey) StorageContainerResourceId() string {
	return fmt.Sprintf("%s/blobServices/default/containers/%s", k.StorageResourceId(), k.Container)
}

func (k *StorageContainerKey) BlobContainerUrl() string {
	return fmt.Sprintf("%s/%s", k.BlobServiceUrl(), k.Container)
}

type StorageBlobKey struct {
	StorageContainerKey
	Blob string
}

func (k *StorageBlobKey) BlobUrl() string {
	return fmt.Sprintf("%s/%s", k.BlobContainerUrl(), k.Blob)
}

func NewStorageBlobKey(subscriptionId string, resourceGroup string, storageAccount string, container string, blob string) *StorageBlobKey {
	return &StorageBlobKey{
		StorageContainerKey: StorageContainerKey{
			StorageKey: StorageKey{
				ResourceGroupKey: ResourceGroupKey{
					SubscriptionId: subscriptionId,
					ResourceGroup:  resourceGroup,
				},
				StorageAccount: storageAccount,
			},
			Container: container,
		},
		Blob: blob,
	}
}

// gallery

type GalleryKey struct {
	ResourceGroupKey
	GalleryName string
}

func (k *GalleryKey) GalleryResourceId() string {
	return fmt.Sprintf("%s/providers/Microsoft.Compute/galleries/%s", k.ResourceGroupResourceId(), k.GalleryName)
}

type GalleryImageDefinitionKey struct {
	GalleryKey
	ImageDefinitionName string
}

func (k *GalleryImageDefinitionKey) GalleryImageDefinitionResourceId() string {
	return fmt.Sprintf("%s/images/%s", k.GalleryResourceId(), k.ImageDefinitionName)
}

type GalleryImageVersionKey struct {
	GalleryImageDefinitionKey
	Version string
}

func (k *GalleryImageVersionKey) GalleryImageVersionResourceId() string {
	return fmt.Sprintf("%s/versions/%s", k.GalleryImageDefinitionResourceId(), k.Version)
}

func NewGalleryImageVersionKey(subscriptionId string, resourceGroup string, galleryName string, imageDefinitionName string, version string) *GalleryImageVersionKey {
	return &GalleryImageVersionKey{
		GalleryImageDefinitionKey: GalleryImageDefinitionKey{
			GalleryKey: GalleryKey{
				ResourceGroupKey: ResourceGroupKey{
					SubscriptionId: subscriptionId,
					ResourceGroup:  resourceGroup,
				},
				GalleryName: galleryName,
			},
			ImageDefinitionName: imageDefinitionName,
		},
		Version: version,
	}
}
