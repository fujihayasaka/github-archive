// Package globalid provides convenience functions for working with Rails style Global IDs.
package globalid

import (
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
)

// GlobalID represents a rails global id object in its basic parts.
type GlobalID struct {
	App       string
	ModelName string
	ModelID   string
}

// Parse takes a raw string and creates a GlobalID from it if formatted correctly.
// An error is returned if the string does not match the expected global id format.
func Parse(rawGlobalID string) (*GlobalID, error) {
	gURL, err := url.Parse(rawGlobalID)

	if err != nil {
		return nil, err
	}

	if gURL.Scheme != "gid" {
		return nil, fmt.Errorf("invalid globalId scheme")
	}

	if gURL.Host == "" {
		return nil, fmt.Errorf("globalId scheme requires an app name")
	}
	const numParts = 3
	pathParts := strings.SplitN(gURL.EscapedPath(), "/", numParts)

	partsRequred := fmt.Errorf("globalId scheme requires a model_name and model_id")

	if len(pathParts) != numParts {
		return nil, partsRequred
	}

	modelName := pathParts[1]
	modelID := pathParts[2]

	if modelName == "" || modelID == "" {
		return nil, partsRequred
	}

	return &GlobalID{
		App:       gURL.Host,
		ModelName: modelName,
		ModelID:   modelID,
	}, nil
}

func (g GlobalID) String() string {
	return fmt.Sprintf("gid://%s/%s/%s", g.App, g.ModelName, g.ModelID)
}

// MarshalJSON marshals the GlobalID into a string through the json Marshaler.
func (g *GlobalID) MarshalJSON() ([]byte, error) {
	return json.Marshal(g.String())
}

// UnmarshalJSON unmarshals the GlobalID from a JSON string.
func (g *GlobalID) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err != nil {
		return err
	}

	parsed, err := Parse(s)
	if err != nil {
		return err
	}

	*g = *parsed
	return nil
}
