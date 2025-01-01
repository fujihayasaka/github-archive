// FILEPATH: /workspaces/hosted-compute-ims/internal/twirp/image_version_helper_test.go

package twirp

import (
	"context"
	"testing"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestImagesAdminApiHandler_getNextImageVersionAsNeeded(t *testing.T) {
	type versionIncTestCases struct {
		description    string
		input          string
		expectedOutput string
	}

	var (
		ctx               = context.Background()
		ImageDefinitionId = uint64(10)
		// There's no garuntee that the image versions will be in order from the database.
		ImageVersions = []*models.ImageVersion{
			{
				Id:                4,
				Version:           "3.0.0",
				ImageDefinitionId: 10,
			},
			{
				Id:                2,
				Version:           "3.0.2",
				ImageDefinitionId: 10,
			},
			{
				Id:                3,
				Version:           "3.0.1",
				ImageDefinitionId: 10,
			},
			{
				Id:                6,
				Version:           "2.1.0",
				ImageDefinitionId: 10,
			},
			{
				Id:                5,
				Version:           "2.1.2",
				ImageDefinitionId: 10,
			},
		}
		TestCases = []versionIncTestCases{
			// If image version is not specified at all, take the last image version 1.5.0 and increment minor version (to 1.6.0)
			{
				description:    "empty version",
				input:          "",
				expectedOutput: "3.1.0",
			},
			// If input is 1.*.*, increment patch version of 1.<highest-minor>
			{
				description:    "new major version 4.*.*",
				input:          "4.*.*",
				expectedOutput: "4.0.0",
			},
			{
				description:    "new minor version but not latest major version",
				input:          "2.*.*",
				expectedOutput: "2.1.3",
			},

			// If input is 1.5.*, increment patch version of 1.5.0 -> 1.5.1
			{
				description:    "new major version 4.1.*",
				input:          "4.1.*",
				expectedOutput: "4.1.0",
			},
			{
				description:    "new minor version 2.2.*",
				input:          "2.2.*",
				expectedOutput: "2.2.0",
			},
			{
				description:    "new patch version 2.1.*",
				input:          "2.1.*",
				expectedOutput: "2.1.3",
			},

			// If input is 1.*, increment minor version 1.5.0 -> 1.6.0
			{
				description:    "new major version 4.*",
				input:          "4.*",
				expectedOutput: "4.0.0",
			},
			{
				description:    "new minor version 2.2.*",
				input:          "2.*",
				expectedOutput: "2.2.0",
			},

			// Explicit version
			{
				description:    "explicit version 3.4.1",
				input:          "3.4.1",
				expectedOutput: "3.4.1",
			},
		}
	)

	for _, scenario := range TestCases {
		t.Run(scenario.description, func(t *testing.T) {
			ctrl, s := setupImagesApiHandler(t)
			defer ctrl.Finish()

			gomock.InOrder(
				mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), ImageDefinitionId).AnyTimes().Return(ImageVersions, nil),
			)

			version, err := s.getNextImageVersionAsNeeded(ctx, ImageDefinitionId, scenario.input)

			assert.NoError(t, err)
			assert.Equal(t, scenario.expectedOutput, version)
		})
	}

	t.Run("empty input and no image versions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), ImageDefinitionId).AnyTimes().Return([]*models.ImageVersion{}, nil),
		)

		version, err := s.getNextImageVersionAsNeeded(ctx, ImageDefinitionId, "")

		assert.NoError(t, err)
		assert.Equal(t, "1.0.0", version)
	})

	t.Run("non-empty input and no image versions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), ImageDefinitionId).AnyTimes().Return([]*models.ImageVersion{}, nil),
		)

		version, err := s.getNextImageVersionAsNeeded(ctx, ImageDefinitionId, "3.*.*")

		assert.NoError(t, err)
		assert.Equal(t, "3.0.0", version)

		version, err = s.getNextImageVersionAsNeeded(ctx, ImageDefinitionId, "3.1.*")
		assert.NoError(t, err)
		assert.Equal(t, "3.1.0", version)
	})

	t.Run("invalid inputs", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), ImageDefinitionId).AnyTimes().Return([]*models.ImageVersion{}, nil),
		)

		_, err := s.getNextImageVersionAsNeeded(ctx, ImageDefinitionId, "a.b.c")
		assert.Error(t, err, "Invalid image version")

		_, err = s.getNextImageVersionAsNeeded(ctx, ImageDefinitionId, "3.a.*")
		assert.Error(t, err, "invalid version format")
	})
}
