package vssf_runner

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestMergeImagesUsage(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	usage1 := &ImageUsage{
		ImageVersions: map[string]ImageVersionUsage{
			"1.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus": 1,
					"westus": 1,
				},
			},
			"1.0.1": {
				VMCountPerRegion: map[string]int32{
					"eastus": 1,
				},
			},
		},
	}
	usage2 := &ImageUsage{
		ImageVersions: map[string]ImageVersionUsage{
			"1.0.0": {
				VMCountPerRegion: map[string]int32{},
			},
			"1.0.1": {
				VMCountPerRegion: map[string]int32{
					"eastus": 1,
				},
			},
		},
	}

	expectedUsage := &ImageUsage{
		ImageVersions: map[string]ImageVersionUsage{
			"1.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus": 1,
					"westus": 1,
				},
			},
			"1.0.1": {
				VMCountPerRegion: map[string]int32{
					"eastus": 2,
				},
			},
		},
	}

	actualUsage := MergeImagesUsage(usage1, usage2)
	assert.Equal(t, expectedUsage, actualUsage)
}
