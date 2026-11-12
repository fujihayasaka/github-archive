package dsapiclient

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"

	ds "github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/encoding/protojson"
)

// NewNullDiffStatus creates a new DiffStatusGetterStub with no client for DS API
// It has a stubbed implementation of DS APIs which can be configured to return
// desired diff status responses
func NewNullDiffStatus(nullConfig NullConfig, logger log.Logger, metrics stats.Client) *StatusGetter {
	diffStatusGetter := &DSDiffStatusStub{
		SeededResponses: nullConfig.GetSnapshotDiffStatusResponses,
	}
	return &StatusGetter{
		SnapshotsDiffStatusGetter: diffStatusGetter,
		Logger:                    logger,
		Metrics:                   metrics,
	}
}

// NullConfig is used to configure the ds proto responses of null diff statuses
type NullConfig struct {
	GetSnapshotDiffStatusResponses map[string]*ds.GetSnapshotDiffStatusResponse
}

// DSDiffStatusStub stubs the DS snapshot diff status twirp API
type DSDiffStatusStub struct {
	SeededResponses map[string]*ds.GetSnapshotDiffStatusResponse
}

// GetSnapshotDiffStatus returns the stubbed response
func (sg *DSDiffStatusStub) GetSnapshotDiffStatus(ctx context.Context, request *ds.GetSnapshotDiffStatusRequest) (*ds.GetSnapshotDiffStatusResponse, error) {
	if request.RepositoryId == 500 {
		// Repo 500 from seed data forces an error to be returned.  Used for testing errors from dsapiclient.
		err := errors.New("simulated error from DS-API client")
		return nil, err
	}
	key := fmt.Sprintf("%d:%s", request.GetRepositoryId(), request.GetBasehead())
	response, ok := sg.SeededResponses[key]
	if !ok {
		return &ds.GetSnapshotDiffStatusResponse{}, nil
	}
	return response, nil
}

// LoadNullSeeds loads diff statuses to be returned from the stub
// From JSON files
func LoadNullSeeds(snapshotsDiffStatusFilePath string) (NullConfig, error) {
	var seededResponses map[string]*ds.GetSnapshotDiffStatusResponse
	if snapshotsDiffStatusFilePath != "" {
		snapshotsDiffStatusFile, err := os.Open(snapshotsDiffStatusFilePath)
		if err != nil {
			return NullConfig{}, fmt.Errorf("failed to open snapshots diff status file: %w", err)
		}
		defer func() {
			err := snapshotsDiffStatusFile.Close()
			if err != nil {
				fmt.Printf("failed to close snapshots diff status file: %v\n", err)
			}
		}()

		seededResponses, err = loadSnapshotsDiffStatusResponses(snapshotsDiffStatusFile)
		if err != nil {
			return NullConfig{}, fmt.Errorf("failed to load snapshots diff: %w", err)
		}
	}

	return NullConfig{
		GetSnapshotDiffStatusResponses: seededResponses,
	}, nil
}

func loadSnapshotsDiffStatusResponses(snapshotsDiffStatusFile *os.File) (map[string]*ds.GetSnapshotDiffStatusResponse, error) {
	allSeedsBytes, err := io.ReadAll(snapshotsDiffStatusFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read snapshots diff status file: %w", err)
	}

	var allSeedsRawJSON map[string]json.RawMessage
	err = json.Unmarshal(allSeedsBytes, &allSeedsRawJSON)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal snapshots diff statuses: %w", err)
	}

	responsesMap := make(map[string]*ds.GetSnapshotDiffStatusResponse)
	for key, seed := range allSeedsRawJSON {
		var response ds.GetSnapshotDiffStatusResponse
		err := protojson.Unmarshal(seed, &response)
		if err != nil {
			return nil, fmt.Errorf("failed to proto unmarshal snapshots diff status: %w", err)
		}

		responsesMap[key] = &response
	}

	return responsesMap, nil
}
