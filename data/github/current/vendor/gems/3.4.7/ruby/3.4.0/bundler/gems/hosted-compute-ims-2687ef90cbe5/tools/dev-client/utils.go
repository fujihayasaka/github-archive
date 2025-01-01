//nolint:all
package main

import (
	"flag"
	"fmt"
	"maps"
	"slices"
	"strings"
	"time"

	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/utils"
	protojson "google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

type devClientParameters struct {
	ServerUrl    string
	ScenarioName string
	Scenario     Scenario
	Image        *devClientImage
}

type devClientImage struct {
	Name         string
	SourceVhdUrl string
	OsType       sharedapi.OsType
	Architecture sharedapi.Architecture
}

func parseParameters() (*devClientParameters, error) {
	var (
		result    devClientParameters
		imageName string
	)

	flag.StringVar(&result.ServerUrl, "server-url", "", "server url")
	flag.StringVar(&result.ScenarioName, "scenario", "", "scenario name")
	flag.StringVar(&imageName, "image", "", "image name")
	flag.Parse()

	if result.ServerUrl == "" {
		return nil, fmt.Errorf("Server url is required. Use --server-url argument to pass server url")
	}

	if scenario, scenarioFound := KnownScenarios[result.ScenarioName]; scenarioFound {
		result.Scenario = scenario
	} else {
		return nil, fmt.Errorf("Unknown scenario. Use --scenario argument to specify valid scenario name. Allowed values: %v", slices.Collect(maps.Keys(KnownScenarios)))
	}

	if result.Scenario.ImageRequired {
		if imageName == "" {
			imageName = "centos"
		} else {
			imageName = strings.ToLower(imageName)
		}

		fmt.Println("Generating VHD URL for image:", imageName)
		sourceVhdUrl, err := utils.GenerateImageVhdUrl(imageName)
		if err != nil {
			return nil, err
		}

		imageOsType := sharedapi.OsType_Linux
		if strings.Contains(imageName, "windows") {
			imageOsType = sharedapi.OsType_Windows
		}

		imageArch := sharedapi.Architecture_X64
		if strings.Contains(imageName, "arm") {
			imageArch = sharedapi.Architecture_Arm64
		}

		result.Image = &devClientImage{
			Name:         imageName,
			SourceVhdUrl: sourceVhdUrl,
			OsType:       imageOsType,
			Architecture: imageArch,
		}
	}

	return &result, nil
}

func generateOwner() string {
	return fmt.Sprintf("user-%d", time.Now().UnixNano())
}

func generateImageDefinitionName() string {
	return fmt.Sprintf("image-%d", time.Now().UnixNano())
}

func printResponse(msg string, objs ...proto.Message) {
	fmt.Printf("%s: \n", msg)
	for _, obj := range objs {
		fmt.Println(protojson.Format(obj))
	}
}
