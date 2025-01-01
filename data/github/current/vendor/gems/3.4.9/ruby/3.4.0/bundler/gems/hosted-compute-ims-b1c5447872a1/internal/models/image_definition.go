package models

import (
	"time"
)

// OwnerId has format "<T>_<ID>" where T is single up-case letter (O or E, org vs enterprise) and ID is base64url-encoded string (https://base64.guru/standards/base64url)
// ^[A-Z]_[A-Za-z0-9_-]+$, max symbols count is 12, examples: E_kgDNHLM, O_kgDOAu6jWA

type ImageDefinition struct {
	Id                        uint64
	OwnerId                   string
	ImageType                 ImageType
	Name                      string
	Enabled                   bool
	FeatureFlag               *string
	OsType                    OsType
	Architecture              Architecture
	AzureSubscriptionId       *uint64
	PointsToImageDefinitionId *uint64
	CreatedAt                 time.Time
	UpdatedAt                 *time.Time
}

func (def *ImageDefinition) IsGalleryImageDefinition() bool {
	return def.OsType == OsType_Linux || def.OsType == OsType_Windows
}

func (d *ImageDefinition) ResolveImageDefinitionId() uint64 {
	if d.PointsToImageDefinitionId != nil {
		return *d.PointsToImageDefinitionId
	}

	return d.Id
}

type ImageDefinitionUpdate struct {
	Name                      string
	Enabled                   bool
	RemoveFeatureFlag         bool
	FeatureFlag               *string
	PointsToImageDefinitionId *uint64
}

type AzureSubscription struct {
	Id              uint64
	SubscriptionId  string
	ImageType       ImageType
	ImageCount      int
	ResourcesPrefix string
	CreatedAt       time.Time
	UpdatedAt       *time.Time
}

type ImageVersionsStorageMetadata struct {
	ImageDefinitionId        uint64
	Count                    int32
	TotalImageVersionsSizeGB int32
}
