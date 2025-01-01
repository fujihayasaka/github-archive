package metadata

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"

	github "github.com/github/launch/hydro/schemas/github/v1/entities"
	"github.com/github/launch/types"
)

// WorkflowMetadata is context about a Workflow execution.
type WorkflowMetadata struct {
	Repository      *WorkflowRepositoryMetadata `json:"repository"`
	RepositoryOwner *WorkflowMetadataUser       `json:"repositoryOwner"`
	// Always present, whether user type is User, Bot or Organisation
	InvokingUser   *WorkflowMetadataUser  `json:"user"`
	Actor          *WorkflowMetadataActor `json:"actor"`
	RepositoryTier types.RepositoryTier   `json:"repositoryTier"`
	CustomerLabel  string                 `json:"customer_label,omitempty"`

	// CustomerID is the customer ID of the billing plan owner
	CustomerID *int64 `json:"customer_id,omitempty"`
}

// WorkflowRepositoryMetadata contains information about the repository the workflow
// was executed in.
//
// This is a subset of the github.Repository struct.
type WorkflowRepositoryMetadata struct {
	// The repository database id.
	ID uint32 `json:"id,omitempty"`
	// The repository global relay id.
	GlobalRelayID string `json:"global_relay_id,omitempty"`
	// The repository visibility.
	Visibility github.Repository_Visibility `json:"visibility,omitempty"`
}

// WorkflowMetadataUser is a subset of the github.User struct
// See https://github.com/github/hydro-schemas/blob/85c60a2f24b6c091478af7cd647bca1c0ce89075/proto/hydro/schemas/github/v1/entities/user.proto
type WorkflowMetadataUser struct {
	ID            uint32 `json:"id,omitempty"`
	Login         string `json:"login,omitempty"`
	GlobalRelayID string `json:"global_relay_id,omitempty"`
}

func (w *WorkflowMetadataUser) GetID() uint32 {
	if w != nil {
		return w.ID
	}

	return 0
}

type WorkflowMetadataActor struct {
	IsDependabot bool   `json:"isDependabot"`
	Login        string `json:"login"`
}

// Value serializes for database.
func (w WorkflowMetadata) Value() (driver.Value, error) {
	b, err := json.Marshal(&w)
	return string(b), err
}

// Scan reads from database.
func (w *WorkflowMetadata) Scan(val any) error {
	switch v := val.(type) {
	case string:
		return json.Unmarshal([]byte(v), w)
	case []byte:
		return json.Unmarshal(v, w)
	default:
		return fmt.Errorf("scan: unable to scan type %T into WorkflowMetadata", val)
	}
}
