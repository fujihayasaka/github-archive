// Package security provides chatops security functionality.
package security

import (
	"fmt"
	"io/ioutil"

	yaml "gopkg.in/yaml.v2"
)

// Constraints is a collection of security options for commands in a namespace.
type Constraints struct {
	Commands map[string]Command
}

// Command describes security options for a single chatops command.
type Command struct {
	Owner       string
	Require2fa  bool     `yaml:"2fa"`
	SafeRooms   []string `yaml:"safe_rooms"`
	SafeOptions []string `yaml:"safe_options"`
	SafeRoles   []string `yaml:"safe_roles"`
}

// LoadSecurityConfig parses the yaml config file and returns a structured result.
func LoadSecurityConfig(filename string) (*Constraints, error) {
	var security Constraints

	rawConfig, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("unable to read security constraints from file %s: %w", filename, err)
	}

	err = yaml.Unmarshal(rawConfig, &security)
	if err != nil {
		return nil, fmt.Errorf("error unmarshalling YAML from string %s: %w", rawConfig, err)
	}

	return &security, nil
}

// LoadSecurityConfigString parse the given string into a Constraints object.
func LoadSecurityConfigString(rawConfig string) (*Constraints, error) {
	var security Constraints

	err := yaml.Unmarshal([]byte(rawConfig), &security)
	if err != nil {
		return nil, fmt.Errorf("error in LoadSecurityConfigString unmarshalling YAML from string %s: %w", rawConfig, err)
	}

	return &security, nil
}
