package twirp

import (
	"fmt"

	sharedtwirp "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/models"
)

func actorFromTwirpActor(actor *sharedtwirp.Actor) (models.Actor, error) {
	return models.NewActorFromGlobalIdAndStamp(actor.GlobalId, actor.Stamp)
}

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

func mapApiToVmGeneration(vmGeneration sharedtwirp.VmGeneration) (models.VmGeneration, error) {
	switch vmGeneration {
	case sharedtwirp.VmGeneration_Gen1:
		return models.VmGeneration_Gen1, nil
	case sharedtwirp.VmGeneration_Gen2:
		return models.VmGeneration_Gen2, nil
	default:
		return "", fmt.Errorf("unknown vm generation: %s", vmGeneration)
	}
}

func mapApiToOsState(osState sharedtwirp.OsState) (models.OsState, error) {
	switch osState {
	case sharedtwirp.OsState_Generalized:
		return models.OsState_Generalized, nil
	case sharedtwirp.OsState_Specialized:
		return models.OsState_Specialized, nil
	default:
		return "", fmt.Errorf("unknown os state: %s", osState)
	}
}
