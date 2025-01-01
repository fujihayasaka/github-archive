package models

import (
	"sort"
	"time"

	"github.com/Masterminds/semver"
)

type ImageVersion struct {
	Id                uint64
	Version           string
	ImageDefinitionId uint64
	State             ImageVersionState
	StateDetails      string
	SizeGB            *int32
	ResourceId        string
	Enabled           bool
	CreatedAt         time.Time
	UpdatedAt         *time.Time
}

type ImageVersionUpdate struct {
	Enabled    bool
	ResourceId string
}

type ImageVersionReplicationData struct {
	Id                    uint64
	ImageDefinitionId     uint64
	ImageVersion          string
	RegionReplicationData map[string]ImageVersionRegionalReplicationData // region is the key
}

type ImageVersionRegionalReplicationData struct {
	VMCount      int32
	ReplicaCount int32
}

func SortImageVersionsByVersion(versions []*ImageVersion) {
	sort.Slice(versions, func(i, j int) bool {
		a, err := semver.NewVersion(versions[i].Version)
		if err != nil {
			a, _ = semver.NewVersion("0.0.0")
		}

		b, err := semver.NewVersion(versions[j].Version)
		if err != nil {
			b, _ = semver.NewVersion("0.0.0")
		}

		return a.GreaterThan(b)
	})
}
