package config

import (
	"encoding/json"
	"fmt"
	"os"
)

const MetadataPath = "/etc/github/metadata.json"

type Metadata struct {
	Application string `json:"app"`
	Environment string `json:"env"`
	Hostname    string
	Pod         string
	Region      string `json:"region"`
	Role        string `json:"role"`
	Site        string `json:"site"`
}

func GetMetadataMetal(app string) (*Metadata, error) {
	var metadata Metadata
	if err := metadata.PopulateFromFile(); err != nil {
		return &metadata, err
	}
	if app != "" {
		metadata.Application = app
	}
	return &metadata, nil
}

func GetMetadataKube(app string) (*Metadata, error) {
	var metadata Metadata
	if err := metadata.PopulateFromFile(); err != nil {
		return &metadata, err
	}
	if err := metadata.PopulateFromKubeEnv(); err != nil {
		return &metadata, err
	}
	if app != "" {
		metadata.Application = app
	}
	return &metadata, nil
}

const DeployedEnvKey = "HEAVEN_DEPLOYED_ENV"
const PodNameKey = "KUBE_POD_NAME"
const HostNameKey = "KUBE_NODE_HOSTNAME"

func (md *Metadata) PopulateFromKubeEnv() error {

	if val, ok := os.LookupEnv(DeployedEnvKey); ok {
		md.Environment = val
	} else {
		return fmt.Errorf("no value set for: %s", DeployedEnvKey)
	}

	if val, ok := os.LookupEnv(PodNameKey); ok {
		md.Pod = val
	} else {
		return fmt.Errorf("no value set for: %s", PodNameKey)
	}

	if val, ok := os.LookupEnv(HostNameKey); ok {
		md.Hostname = val
	} else {
		return fmt.Errorf("no value set for: %s", HostNameKey)
	}
	return nil
}

func (md *Metadata) PopulateFromFile() error {
	return metadataFromFile(md, MetadataPath)
}

func metadataFromFile(md *Metadata, path string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("failed to load github metadata: %w", err)
	}

	if err := json.NewDecoder(f).Decode(&md); err != nil {
		return fmt.Errorf("failed to decode github metadata: %w", err)
	}

	return nil
}
