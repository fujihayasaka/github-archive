package metadata_test

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"

	github "github.com/github/launch/hydro/schemas/github/v1/entities"

	"github.com/github/launch/clients/hydro/metadata"
)

func TestWorkflowMetadata_SQL(t *testing.T) {
	m := metadata.WorkflowMetadata{
		Repository: &metadata.WorkflowRepositoryMetadata{
			ID:            3,
			GlobalRelayID: "R_kgAD",
		},
		RepositoryOwner: &metadata.WorkflowMetadataUser{
			Login: "owner",
		},
	}

	v, err := m.Value()
	require.NoError(t, err)

	var scanned metadata.WorkflowMetadata
	err = scanned.Scan(v)
	require.NoError(t, err)
	assert.Equal(t, m, scanned)
}

func TestWorkflowMetadata_SQL_WithCustomerID(t *testing.T) {
	customerID := int64(64)
	m := metadata.WorkflowMetadata{
		Repository: &metadata.WorkflowRepositoryMetadata{
			ID:            3,
			GlobalRelayID: "R_kgAD",
		},
		RepositoryOwner: &metadata.WorkflowMetadataUser{
			Login: "owner",
		},
		CustomerID: &customerID,
	}

	v, err := m.Value()
	require.NoError(t, err)

	var scanned metadata.WorkflowMetadata
	err = scanned.Scan(v)
	require.NoError(t, err)
	assert.Equal(t, m, scanned)
}

func TestWorkflowMetadataUser_UserCompat(t *testing.T) {
	// *github.User and *metadata.WorkflowMetadataUser should be forward and backward compatible
	// when serialized to JSON.

	expectedJSON := `{"id": 16631042, "login": "joshmgross", "global_relay_id": "U_kgDOAP3FAg"}`
	// https://data.githubapp.com/sql/5eb2befd-23c1-4c70-82a8-328453839e4f

	gu := &github.User{
		Id:            16631042,
		Login:         "joshmgross",
		GlobalRelayId: "U_kgDOAP3FAg",
	}

	wmu := &metadata.WorkflowMetadataUser{
		ID:            16631042,
		Login:         "joshmgross",
		GlobalRelayID: "U_kgDOAP3FAg",
	}

	guJSON, err := json.Marshal(gu)
	require.NoError(t, err)

	wmuJSON, err := json.Marshal(wmu)
	require.NoError(t, err)

	require.JSONEq(t, expectedJSON, string(guJSON))
	require.JSONEq(t, expectedJSON, string(wmuJSON))
	require.JSONEq(t, string(guJSON), string(wmuJSON))

	// A *github.User should be able to be deserialized into a *metadata.WorkflowMetadataUser
	var scannedWmu metadata.WorkflowMetadataUser
	err = json.Unmarshal(guJSON, &scannedWmu)
	require.NoError(t, err)
	require.Equal(t, wmu, &scannedWmu)

	// A *metadata.WorkflowMetadataUser should be able to be deserialized into a *github.User
	var scannedGu github.User
	err = json.Unmarshal(wmuJSON, &scannedGu)
	require.NoError(t, err)
	require.Equal(t, gu, &scannedGu)

}

// fullWorkflowRepositoryMetadata is a copy of the WorkflowRepositoryMetadata struct
// with fields that have been removed
type fullWorkflowRepositoryMetadata struct {
	// The repository database id.
	ID uint32 `json:"id,omitempty"`
	// The repository global relay id.
	GlobalRelayID string `json:"global_relay_id,omitempty"`
	// The repository name.
	Name string `json:"name,omitempty"`
	// The repository visibility.
	Visibility github.Repository_Visibility `json:"visibility,omitempty"`
	// The stargazer count.
	StargazerCount uint32 `json:"stargazer_count,omitempty"`
	// The public fork count.
	PublicForkCount uint32 `json:"public_fork_count,omitempty"`
	// The timestamp the repository was last pushed at.
	PushedAt *timestamp.Timestamp `json:"pushed_at,omitempty"`
	// The repository created at timestamp.
	CreatedAt *timestamp.Timestamp `json:"created_at,omitempty"`
	// The repository updated at timestamp.
	UpdatedAt *timestamp.Timestamp `json:"updated_at,omitempty"`
}

func TestWorkflowRepositoryMetadata_RepositoryCompat(t *testing.T) {
	fmd := &fullWorkflowRepositoryMetadata{
		ID:              3,
		GlobalRelayID:   "R_kgAD",
		Name:            "github",
		Visibility:      github.Repository_PRIVATE,
		StargazerCount:  1,
		PublicForkCount: 0,
		PushedAt:        timestamppb.New(time.Now()),
		CreatedAt:       timestamppb.New(time.Now()),
		UpdatedAt:       timestamppb.New(time.Now()),
	}

	md := &metadata.WorkflowRepositoryMetadata{
		ID:            3,
		GlobalRelayID: "R_kgAD",
		Visibility:    github.Repository_PRIVATE,
	}

	// Backcompat
	fmdJSON, err := json.Marshal(fmd)
	require.NoError(t, err)

	deserializedFromFull := &metadata.WorkflowRepositoryMetadata{}
	err = json.Unmarshal(fmdJSON, deserializedFromFull)
	require.NoError(t, err)

	assert.Equal(t, md, deserializedFromFull)

	// Forward compat
	mdJSON, err := json.Marshal(md)
	require.NoError(t, err)

	deserializedFromMinimal := &fullWorkflowRepositoryMetadata{}
	err = json.Unmarshal(mdJSON, deserializedFromMinimal)
	require.NoError(t, err)

	assert.Equal(t, fmd.ID, deserializedFromMinimal.ID)
	assert.Equal(t, fmd.GlobalRelayID, deserializedFromMinimal.GlobalRelayID)
	assert.Equal(t, fmd.Visibility, deserializedFromMinimal.Visibility)
}
