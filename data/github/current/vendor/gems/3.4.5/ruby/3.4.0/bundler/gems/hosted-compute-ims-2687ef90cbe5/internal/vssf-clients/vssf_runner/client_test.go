package vssf_runner

import (
	"errors"
	"testing"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
)

func Test_GetRunnerImageSourceForImageDefinition(t *testing.T) {
	testCases := []struct {
		testName        string
		imageDefinition *models.ImageDefinition
		expectedResult  string
		expectedError   error
	}{
		{
			testName:        "curated image",
			imageDefinition: &models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated, OwnerId: models.GithubOwnerId},
			expectedResult:  "Curated",
			expectedError:   nil,
		},
		{
			testName:        "partner image",
			imageDefinition: &models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated, OwnerId: models.PartnerOwnerId},
			expectedResult:  "Marketplace",
			expectedError:   nil,
		},
		{
			testName:        "customer image",
			imageDefinition: &models.ImageDefinition{Id: 1, ImageType: models.ImageType_Customer, OwnerId: "U_kgAB"},
			expectedResult:  "Custom",
			expectedError:   nil,
		},
		{
			testName:        "unknown image",
			imageDefinition: &models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated, OwnerId: "unknown-partner"},
			expectedResult:  "",
			expectedError:   errors.New("image definition doesn't match any runner image source"),
		},
	}

	for _, test := range testCases {
		t.Run(test.testName, func(t *testing.T) {
			client := runnerClient{}
			actual, err := client.getRunnerImageSourceForImageDefinition(test.imageDefinition)
			assert.Equal(t, err, test.expectedError)
			assert.Equal(t, actual, test.expectedResult)
		})
	}
}
