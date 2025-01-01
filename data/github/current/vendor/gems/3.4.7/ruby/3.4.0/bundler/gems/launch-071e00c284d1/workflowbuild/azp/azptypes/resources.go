package azptypes

import (
	"time"

	"github.com/github/launch/types"
)

// returned by Azure's API
type CreationResult struct {
	// EntityId is the GlobalId for the repository
	EntityID types.GlobalID
	// TenantID is the GUID of the tenant
	TenantID   string
	TenantName string

	ProjectName              string
	PipelineID               int64
	ClientID                 string
	PipelinesScaleUnitID     string
	ArtifactCacheScaleUnitID string
	RunnerScaleUnitID        string
}

type BackingResources struct {
	CreationResult

	// additional information we need to use a set of backing resources
	EncryptedPrivateKey []byte
	Environment         string

	CreatedAt *time.Time
}
