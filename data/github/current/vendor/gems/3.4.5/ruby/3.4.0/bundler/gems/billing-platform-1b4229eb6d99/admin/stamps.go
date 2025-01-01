package admin

import (
	_ "embed"
	"encoding/json"
	"fmt"
)

//go:embed static/stamps.json
var stampBytes []byte

type Stamps struct {
	Stamps []StampMapping `json:"stamps"`
}

type StampMapping struct {
	Stamp        string `json:"stamp"`
	AdminToolUrl string `json:"adminToolUrl"`
}

func LoadStamps(environment string) (Stamps, error) {
	if environment == "development" {
		return Stamps{
			Stamps: []StampMapping{
				{
					Stamp:        "development",
					AdminToolUrl: "http://127.0.0.1:8899",
				},
			},
		}, nil
	}

	var stamps Stamps
	err := json.Unmarshal(stampBytes, &stamps)
	if err != nil {
		return Stamps{}, fmt.Errorf("failed to unmarshal stamp JSON: %w", err)
	}

	return stamps, nil
}
