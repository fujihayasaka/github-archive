package models

import (
	"fmt"
	"time"
)

// OwnerId has format "<T>_<ID>" where T is single up-case letter (O or E, org vs enterprise) and ID is base64url-encoded string (https://base64.guru/standards/base64url)
// ^[A-Z]_[A-Za-z0-9_-]+$, max symbols count is 12, examples: E_kgDNHLM, O_kgDOAu6jWA

type ImageDefinition struct {
	Id                         uint64
	OwnerId                    string
	ImageType                  ImageType
	Name                       string
	Enabled                    bool
	FeatureFlag                *string
	OsType                     OsType
	Architecture               Architecture
	PointsToImageDefinitionId  *uint64
	CreatedAt                  time.Time
	UpdatedAt                  *time.Time
	State                      ImageDefinitionState
	RunnerGroupId              *uint64
	IsImageGenerationSupported bool
}

// VexiID returns a valid Vex identifier in the format TYPE:VALUE
func (def *ImageDefinition) VexiID() string {
	return fmt.Sprintf("ImageDefinition:%d", def.Id)
}

func (def *ImageDefinition) IsGalleryImageDefinition() bool {
	return def.OsType == OsType_Linux || def.OsType == OsType_Windows
}

func (def *ImageDefinition) ResolveImageDefinitionId() uint64 {
	if def.PointsToImageDefinitionId != nil {
		return *def.PointsToImageDefinitionId
	}

	return def.Id
}

type ImageVersionsSummary struct {
	Count                    int32
	TotalImageVersionsSizeGB int32
}
