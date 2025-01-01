package models

import (
	"encoding/json"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	v1 "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"go.uber.org/zap/zapcore"
)

// SyncEntityType represents the type of entity that is being synced.
type SyncEntityType int32

const (
	// SyncEntityTypeUnspecified is the default value for SyncEntityType.
	SyncEntityTypeUnspecified SyncEntityType = iota
	// SyncEntityTypeOrganization represents an organization.
	SyncEntityTypeOrganization
	// SyncEntityTypeCustomer represents a customer.
	SyncEntityTypeCustomer
)

var (
	entityTypeToString = map[SyncEntityType]string{
		SyncEntityTypeOrganization: "Organization",
		SyncEntityTypeCustomer:     "Customer",
	}
	stringToEntityType = map[string]SyncEntityType{
		"Organization": SyncEntityTypeOrganization,
		"Customer":     SyncEntityTypeCustomer,
	}
)

// String returns the string representation of a SyncEntityType.
func (e *SyncEntityType) String() string {
	return entityTypeToString[*e]
}

// MarshalJSON marshals a SyncEntityType to JSON.
func (e *SyncEntityType) MarshalJSON() ([]byte, error) {
	return json.Marshal(e.String())
}

// UnmarshalJSON unmarshals a SyncEntityType from JSON.
func (e *SyncEntityType) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	value, ok := stringToEntityType[s]
	if !ok {
		return fmt.Errorf("invalid SyncEntityType: %s", s)
	}
	*e = value
	return nil
}

// SyncOrganizationMembershipsJob represents an aqueduct job to sync organization memberships.
type SyncOrganizationMembershipsJob struct {
	EntityType SyncEntityType
	EntityID   uint64
}

// GetLoggerFields returns a list of relevant fields for logging.
func (j *SyncOrganizationMembershipsJob) GetLoggerFields() []zapcore.Field {
	return []zapcore.Field{
		kvp.String("gh.licensify.sync_job.entity_type", j.EntityType.String()),
		kvp.Uint64("gh.licensify.sync_job.entity_id", j.EntityID),
	}
}

// NewSyncJobFromProto creates a new SyncJob from a CreateSyncOrganizationMembershipsJobRequest request proto.
func NewSyncJobFromProto(proto *v1.SyncOrganizationMembershipsRequest) *SyncOrganizationMembershipsJob {
	return &SyncOrganizationMembershipsJob{
		EntityType: SyncEntityType(proto.EntityType),
		EntityID:   proto.EntityId,
	}
}

// NewOrganizationSyncJob creates a new SyncOrganizationMembershipsJob for an organization.
func NewOrganizationSyncJob(organizationID uint64) *SyncOrganizationMembershipsJob {
	return &SyncOrganizationMembershipsJob{
		EntityType: SyncEntityTypeOrganization,
		EntityID:   organizationID,
	}
}

// NewCustomerSyncJob creates a new SyncOrganizationMembershipsJob for a customer.
func NewCustomerSyncJob(customerID uint64) *SyncOrganizationMembershipsJob {
	return &SyncOrganizationMembershipsJob{
		EntityType: SyncEntityTypeCustomer,
		EntityID:   customerID,
	}
}

// CreateRepositoryCollaboratorsJob represents an aqueduct job to create repository collaborators.
type CreateRepositoryCollaboratorsJob struct {
	RepositoryID uint64
}

// GetLoggerFields returns a list of relevant fields for logging.
func (j *CreateRepositoryCollaboratorsJob) GetLoggerFields() []zapcore.Field {
	return []zapcore.Field{
		kvp.Uint64("gh.repository.id", j.RepositoryID),
	}
}

// NewCreateRepositoryCollaboratorsJob creates a new CreateRepositoryCollaboratorsJob for a repository.
func NewCreateRepositoryCollaboratorsJob(repoID, customerID uint64) *CreateRepositoryCollaboratorsJob {
	return &CreateRepositoryCollaboratorsJob{
		RepositoryID: repoID,
	}
}

// BackfillLicenseStatusJob represents an aqueduct job to backfill license status.
type BackfillLicenseStatusJob struct {
	CustomerID uint64
}

// GetLoggerFields returns a list of relevant fields for logging.
func (j *BackfillLicenseStatusJob) GetLoggerFields() []zapcore.Field {
	return []zapcore.Field{
		kvp.Uint64("gh.customer.id", j.CustomerID),
	}
}
