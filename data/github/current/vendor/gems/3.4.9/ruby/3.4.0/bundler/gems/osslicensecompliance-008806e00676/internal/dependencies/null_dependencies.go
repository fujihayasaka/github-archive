package dependencies

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"

	dg "github.com/github/dependency-graph-api/gen/go/v1"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/encoding/protojson"
)

// NewNullDependencies creates a new DependencyGetter with no client for DG API
// It has a stubbed implementation of DG APIs which can be configured to return
// desired repo dependencies and packages
func NewNullDependencies(nullConfig NullConfig, logger log.Logger, metrics stats.Client) *DependencyGetter {
	shaDiffGetter := &DGShaDiffAPIStub{
		ResponseSnapshots: nullConfig.GetSnapshotsDiffResponses,
	}

	packageGetter := &DGPackageAPIStub{
		ListPackageVersionsResponses: nullConfig.ListPackageVersionsResponses,
	}

	return &DependencyGetter{
		ShaDiffGetter: shaDiffGetter,
		PackageGetter: packageGetter,
		Logger:        logger,
		Metrics:       metrics,
	}
}

// NullConfig is used to configure the dg proto responses of null dependencies
type NullConfig struct {
	GetSnapshotsDiffResponses    map[string]*dg.GetSnapshotsDiffResponse
	ListPackageVersionsResponses map[string]*dg.ListPackageVersionsResponse
}

// DGShaDiffAPIStub stubs the DG snapshot diff twirp API
type DGShaDiffAPIStub struct {
	ResponseSnapshots map[string]*dg.GetSnapshotsDiffResponse
}

// GetSnapshotsDiff returns the stubbed response
func (d DGShaDiffAPIStub) GetSnapshotsDiff(_ context.Context, request *dg.GetSnapshotsDiffRequest) (*dg.GetSnapshotsDiffResponse, error) {
	key := fmt.Sprintf("%d:%s:%s", request.GetRepositoryId(), request.GetBaseSha(), request.GetTargetSha())
	response, ok := d.ResponseSnapshots[key]
	if !ok {
		return &dg.GetSnapshotsDiffResponse{}, nil
	}
	return response, nil
}

// DGPackageAPIStub stubs the DG package API
type DGPackageAPIStub struct {
	ListPackageVersionsResponses map[string]*dg.ListPackageVersionsResponse
}

// ListPackageVersions returns the stubbed response
func (d *DGPackageAPIStub) ListPackageVersions(_ context.Context, request *dg.ListPackageVersionsRequest) (*dg.ListPackageVersionsResponse, error) {
	key := fmt.Sprintf("%d:%s", request.GetPackageManager(), request.GetPackageName())
	response, ok := d.ListPackageVersionsResponses[key]
	if !ok {
		return &dg.ListPackageVersionsResponse{}, nil
	}
	return response, nil
}

// LoadNullSeeds loads dependencies to be returned from the stub
// From JSON files
func LoadNullSeeds(snapshotsDiffFilePath, listPackageVersionsFilePath string) (NullConfig, error) {
	var snapshotsDiff map[string]*dg.GetSnapshotsDiffResponse
	if snapshotsDiffFilePath != "" {
		snapshotsDiffFile, err := os.Open(snapshotsDiffFilePath)
		if err != nil {
			return NullConfig{}, fmt.Errorf("failed to open snapshots diff file: %w", err)
		}
		defer snapshotsDiffFile.Close()

		snapshotsDiff, err = loadSnapshotsDiffResponses(snapshotsDiffFile)
		if err != nil {
			return NullConfig{}, fmt.Errorf("failed to load snapshots diff: %w", err)
		}
	}

	var listPackageVersions map[string]*dg.ListPackageVersionsResponse
	if listPackageVersionsFilePath != "" {
		listPackageVersionsFile, err := os.Open(listPackageVersionsFilePath)
		if err != nil {
			return NullConfig{}, fmt.Errorf("failed to open list package versions file: %w", err)
		}
		defer listPackageVersionsFile.Close()

		listPackageVersions, err = loadListPackageVersionsResponses(listPackageVersionsFile)
		if err != nil {
			return NullConfig{}, fmt.Errorf("failed to load list package versions: %w", err)
		}
	}

	return NullConfig{
		GetSnapshotsDiffResponses:    snapshotsDiff,
		ListPackageVersionsResponses: listPackageVersions,
	}, nil
}

func loadSnapshotsDiffResponses(snapshotsDiffFile *os.File) (map[string]*dg.GetSnapshotsDiffResponse, error) {
	snapshotsDiffBytes, err := io.ReadAll(snapshotsDiffFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read snapshots diff file: %w", err)
	}

	var snapshotsDiffRawJsons map[string]json.RawMessage
	err = json.Unmarshal(snapshotsDiffBytes, &snapshotsDiffRawJsons)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal snapshots diff: %w", err)
	}

	snapshotsDiffMap := make(map[string]*dg.GetSnapshotsDiffResponse)
	for key, snapshotsDiff := range snapshotsDiffRawJsons {
		var snapshotsDiffResp dg.GetSnapshotsDiffResponse
		err := protojson.Unmarshal(snapshotsDiff, &snapshotsDiffResp)
		if err != nil {
			return nil, fmt.Errorf("failed to proto unmarshal snapshots diff: %w", err)
		}

		snapshotsDiffMap[key] = &snapshotsDiffResp
	}

	return snapshotsDiffMap, nil
}

func loadListPackageVersionsResponses(file *os.File) (map[string]*dg.ListPackageVersionsResponse, error) {
	bytes, err := io.ReadAll(file)
	if err != nil {
		return nil, fmt.Errorf("failed to read list package versions file: %w", err)
	}

	var rawJsons map[string]json.RawMessage
	err = json.Unmarshal(bytes, &rawJsons)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal list package versions: %w", err)
	}

	responsesMap := make(map[string]*dg.ListPackageVersionsResponse)
	for key, rawJSON := range rawJsons {
		var response dg.ListPackageVersionsResponse
		err := protojson.Unmarshal(rawJSON, &response)
		if err != nil {
			return nil, fmt.Errorf("failed to proto unmarshal list package versions: %w", err)
		}
		responsesMap[key] = &response
	}

	return responsesMap, nil
}
