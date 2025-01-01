//nolint:all
package main

import (
	"flag"
	"fmt"
	"slices"
	"time"

	"github.com/github/hosted-compute-ims/internal/utils"
	protojson "google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

type devClientParameters struct {
	ServerUrl   string
	Scenario    string
	ImageName   string
	ImageVhdUrl string
}

func parseParameters() (*devClientParameters, error) {
	var parsedParameters devClientParameters

	flag.StringVar(&parsedParameters.ServerUrl, "server-url", "", "server url")
	flag.StringVar(&parsedParameters.Scenario, "scenario", "", "scenario name")
	flag.StringVar(&parsedParameters.ImageName, "image", "", "image name")
	flag.Parse()

	if parsedParameters.ServerUrl == "" {
		return nil, fmt.Errorf("Server url is required. Use --server-url argument to pass server url")
	}

	if !slices.Contains(KnownScenarios, parsedParameters.Scenario) {
		return nil, fmt.Errorf("Unknown scenario. Use --scenario argument to specify valid scanario name. Allowed values: %v", KnownScenarios)
	}

	if parsedParameters.Scenario != HealthScenario {
		if parsedParameters.ImageName == "" {
			parsedParameters.ImageName = "centos"
		}

		fmt.Println("Generating VHD URL for image:", parsedParameters.ImageName)
		imageVhdUrl, err := utils.GenerateImageVhdUrl(parsedParameters.ImageName)
		if err != nil {
			return nil, err
		}

		parsedParameters.ImageVhdUrl = imageVhdUrl
	}

	return &parsedParameters, nil
}

func generateOwner() string {
	return fmt.Sprintf("user-%d", time.Now().UnixNano())
}

func generateImageDefinitionName() string {
	return fmt.Sprintf("image-%d", time.Now().UnixNano())
}

func printResponse(msg string, obj proto.Message) {
	serializedObj, _ := protojson.Marshal(obj)
	fmt.Printf("%s: %s\n", msg, string(serializedObj))
}
