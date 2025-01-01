package azp

import (
	"context"
	"time"

	"github.com/golang/protobuf/ptypes/wrappers"

	"github.com/github/launch/types"
)

// Larger Runners service API
type LargerRunnersClient interface {
	ReportRunnerAdminEvent(ctx context.Context, name string, data map[string]string) error
	ListRunnerPools(ctx context.Context, entityID, ownerID, planOwnerID types.GlobalID, planOwnerTenant string, planOwnerTenantID string, isPrivateEntity bool, isPublicIPEnabled *wrappers.BoolValue) ([]*RunnerPool, error)
	GetRunnerPool(ctx context.Context, poolID int64) (*RunnerPool, error)
	CreateRunnerPool(ctx context.Context, runnerPool CreatePoolRequest) (*RunnerPool, error)
	UpdateRunnerPool(ctx context.Context, poolID int64, runnerPoolUpdate UpdatePoolRequest) (*RunnerPool, error)
	DeleteRunnerPool(ctx context.Context, poolID int64) (*RunnerPool, error)
	CreateImageDefinition(ctx context.Context, osType string, poolName string) (*ImageDefinition, error)
	ListImageDefinitions(ctx context.Context) ([]*ImageDefinition, error)
	GetImageDefinition(ctx context.Context, imageDefinitionID int64) (*ImageDefinition, error)
	DeleteImageDefinition(ctx context.Context, imageDefinitionID int64) error
	CreateImageVersion(ctx context.Context, imageSasURI string, imageDefinitionID int64) (*ImageVersion, error)
	ListImageVersions(ctx context.Context, imageDefinitionID int64, pattern *string) ([]*ImageVersion, error)
	GetImageVersion(ctx context.Context, imageDefinitionID int64, version string) (*ImageVersion, error)
	DeleteImageVersion(ctx context.Context, imageDefinitionID int64, version string) error
	ListPoolAgents(ctx context.Context, poolID int64) ([]*RunnerV2, error)
	ListMachineSpecs(ctx context.Context) ([]*MachineSpec, error)
	ListCuratedImages(ctx context.Context) ([]*Image, error)
	ListMarketplaceImages(ctx context.Context) ([]*Image, error)
	ListRunnerLabels(ctx context.Context) ([]string, error)
	GetTenantInfo(ctx context.Context) (*TenantInfo, error)
	ListBetaFeatures(ctx context.Context) ([]*BetaFeature, error)
	GetBetaFeature(ctx context.Context, featureName string) (*BetaFeature, error)
	SetBetaFeature(ctx context.Context, featureName string, enabled bool) (*BetaFeature, error)
}

type RunnerPool struct {
	ID                     int64       `json:"id"`
	Name                   string      `json:"name"`
	State                  string      `json:"state"`
	Platform               string      `json:"platform"`
	RunnerGroupID          int64       `json:"runnerGroupId"`
	GroupName              string      `json:"groupName"`
	Inherited              bool        `json:"inherited"`
	Labels                 []string    `json:"labels"`
	Ephemeral              bool        `json:"ephemeral"`
	RunnerCount            int64       `json:"runnerCount"`
	IsDev                  bool        `json:"isDev"`
	Image                  ImageKey    `json:"image"`
	PublicIPs              []PublicIP  `json:"publicIps"`
	MachineSpec            MachineSpec `json:"machineSpec"`
	LastActiveOn           string      `json:"lastActiveOn"`
	MaximumRunners         int64       `json:"maximumRunners"`
	MachineSpecID          string      `json:"machineSpecId"`
	UnavailableRunnerCount int64       `json:"unavailableRunnerCount"`
	PersistentOSDisk       bool        `json:"persistentOsDisk"`
	ErrorCode              string      `json:"errorCode"`
	PublicIPEnabled        bool        `json:"publicIpEnabled"`
}

type ImageKey struct {
	Source  string `json:"source"`
	ID      string `json:"id"`
	Version string `json:"version"`
}

type ImageDefinition struct {
	ID                               int64   `json:"id"`
	Name                             string  `json:"name"`
	OsType                           string  `json:"osType"`
	ImageDefinitionState             string  `json:"state"`
	ImageDefinitionVersionCount      int64   `json:"versionCount"`
	ImageDefinitionTotalVersionsSize int64   `json:"totalVersionsSize"`
	ImageDefinitionLatestVersion     *string `json:"latestVersion"`
	Platform                         string  `json:"platform"`
}

type ImageVersion struct {
	ImageDefinitionID               int64     `json:"imageDefinitionId"`
	Version                         string    `json:"version"`
	ImageVersionState               string    `json:"state"`
	ImageVersionImportFailureReason string    `json:"failureReason"`
	ImageVersionCreatedOn           time.Time `json:"createdOn"`
	ImageVersionSize                *int32    `json:"size"`
	ImageVersionLastUsedOn          *string   `json:"lastUsedOn"`
}

type PublicIP struct {
	Enabled bool   `json:"enabled"`
	Prefix  string `json:"prefix"`
	Length  int64  `json:"length"`
}

type CreatePoolRequest struct {
	Name              string   `json:"name"`
	Platform          string   `json:"platform"`
	RunnerGroupID     int64    `json:"runnerGroupId"`
	Labels            []string `json:"labels"`
	IsDev             bool     `json:"isDev"`
	Image             ImageKey `json:"image"`
	IsPublicIPEnabled bool     `json:"isPublicIPEnabled"`
	MaximumRunners    int64    `json:"maximumRunners"`
	MachineSpecID     string   `json:"machineSpecId"`
	PersistentOSDisk  bool     `json:"persistentOSDisk"`
}

type UpdatePoolRequest struct {
	Name              string    `json:"name"`
	Platform          string    `json:"platform"`
	RunnerGroupID     int64     `json:"runnerGroupId"`
	Labels            []string  `json:"labels"`
	IsDev             bool      `json:"isDev"`
	Image             *ImageKey `json:"image,omitempty"`
	IsPublicIPEnabled bool      `json:"isPublicIPEnabled"`
	MaximumRunners    int64     `json:"maximumRunners"`
	MachineSpecID     string    `json:"machineSpecId"`
}

type ImageVersionsList struct {
	Count int64           `json:"count"`
	Value []*ImageVersion `json:"value"`
}

type MachineSpec struct {
	ID               string          `json:"id"`
	CPUCores         int64           `json:"cpuCores"`
	MemoryGB         int64           `json:"memoryGB"`
	StorageGB        int64           `json:"storageGB"`
	Type             string          `json:"type"`
	DocumentationURL string          `json:"documentationUrl"`
	GPU              *MachineSpecGpu `json:"gpu"`
	Architecture     string          `json:"architecture"`
}

type MachineSpecGpu struct {
	Name     string `json:"name"`
	Count    uint32 `json:"count"`
	MemoryGB uint64 `json:"memoryGB"`
}

type MachineSpecsList struct {
	Count int64          `json:"count"`
	Value []*MachineSpec `json:"value"`
}

type Image struct {
	ID          string `json:"id"`
	DisplayName string `json:"displayName"`
	SizeGB      int64  `json:"sizeGB"`
	Platform    string `json:"platform"`
}

type ImagesList struct {
	Count int64    `json:"count"`
	Value []*Image `json:"value"`
}

type RunnerLabelsList struct {
	Count int64    `json:"count"`
	Value []string `json:"value"`
}

type RunnerServiceHostInfo struct {
	InstanceID   string `json:"instanceId"`
	DeploymentID string `json:"deploymentId"`
}

type TenantInfo struct {
	TenantID        string `json:"tenantId"`
	RunnerScaleUnit string `json:"runnerScaleUnit"`
}

type BetaFeature struct {
	Name            string `json:"name"`
	EnabledForUser  bool   `json:"enabledForUser"`
	EnabledGlobally bool   `json:"enabledGlobally"`
}

type BetaFeaturesList struct {
	Count int64          `json:"count"`
	Value []*BetaFeature `json:"value"`
}
