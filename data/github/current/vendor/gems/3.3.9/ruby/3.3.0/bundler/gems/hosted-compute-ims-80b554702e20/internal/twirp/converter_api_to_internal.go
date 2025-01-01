package twirp

import (
	"fmt"

	sharedtwirp "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/models"
)

func mapApiToOsType(os_type sharedtwirp.OsType) (models.OsType, error) {
	switch os_type {
	case sharedtwirp.OsType_Linux:
		return models.OsType_Linux, nil
	case sharedtwirp.OsType_Windows:
		return models.OsType_Windows, nil
	case sharedtwirp.OsType_MacOS:
		return models.OsType_MacOS, nil
	default:
		return "", fmt.Errorf("unknown os type: %s", os_type)
	}
}

func mapApiToArchitecture(architecture sharedtwirp.Architecture) (models.Architecture, error) {
	switch architecture {
	case sharedtwirp.Architecture_X64:
		return models.Architecture_X64, nil
	case sharedtwirp.Architecture_Arm64:
		return models.Architecture_Arm64, nil
	default:
		return "", fmt.Errorf("unknown architecture: %s", architecture)
	}
}
