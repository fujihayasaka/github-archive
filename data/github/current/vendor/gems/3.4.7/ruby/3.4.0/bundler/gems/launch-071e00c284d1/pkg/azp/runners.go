package azp

import (
	"context"
	"strings"

	"github.com/github/launch/types"
)

type RunnersClient interface {
	GenerateJITRunnerConfig(context.Context, *JITRunnerSettings) (*JITRunnerConfig, error)
	GetRunnerRegistrationCredentials(ctx context.Context, ownerID types.GlobalID, billingOwnerID types.GlobalID, tenantSlug string) (*RunnerRegistrationCredentials, error)
	ListRunnersV2(ctx context.Context, page, perPage int64, includeAssignedRequest bool, poolID int64, runnerName string, excludeElasticRunners bool) ([]*RunnerV2, int64, error)
	UpdateRunners(ctx context.Context, operations []*RunnerOp) ([]*RunnerV2, error)
	GetRunner(ctx context.Context, id int64) (*RunnerV2, error)
	DeleteRunner(ctx context.Context, id int64) error
	ListDownloads(ctx context.Context) ([]*Download, error)
	GetAccessPolicy(ctx context.Context) (*AccessPolicy, error)
	UpdateAccessPolicy(ctx context.Context, permissionsOp PermissionOp, addReposOp SelectedReposOp, removeReposOp SelectedReposOp) (*AccessPolicy, error)
}

/*
RunnerOp is used to represent an operation to perform on a single runner.
- op is the operation, e.g. add, remove, replace, etc.
- path is the target or location of what will be updated
- value is what's being added/removed/etc. for the target
*/
type RunnerOp struct {
	Op    string  `json:"op"`
	Path  string  `json:"path"`
	Value []int64 `json:"value"`
}

type PermissionOp struct {
	Op    string `json:"op"`
	Path  string `json:"path"`
	Value string `json:"value"`
}

type SelectedReposOp struct {
	Op    string           `json:"op"`
	Path  string           `json:"path"`
	Value []types.GlobalID `json:"value"`
}

type AssignedRequest struct {
	JobName          string `json:"jobName"`
	PlanID           string `json:"planId"`
	JobID            string `json:"jobId"`
	CheckRunGlobalID string `json:"checkRunGlobalId"`
}

type RunnerV2 struct {
	ID                 int64            `json:"id"`
	Name               string           `json:"name"`
	Labels             []*Label         `json:"labels"`
	Status             string           `json:"status"`
	AssignedRequest    *AssignedRequest `json:"assignedRequest"`
	CurrentParallelism int64            `json:"currentParallelism"`
	RunnerGroupID      int64            `json:"runnerGroupId"`
	OperatingSystem    string           `json:"osDescription"`
	Ephemeral          bool             `json:"ephemeral"`
}

// GetOS returns the operating system if that is properly set as a label.
func (r *RunnerV2) GetOS() string {
	for _, l := range r.Labels {
		t := strings.ToLower(l.Type)
		if t == "system" {
			d := strings.ToLower(l.Name)
			switch d {
			case "macos", "windows", "linux":
				return l.Name
			}
		}
	}
	if r.OperatingSystem == "" {
		return Unknown
	}
	return r.OperatingSystem
}

// GetArch returns the architecture if that is properly set as a label.
func (r *RunnerV2) GetArch() string {
	for _, l := range r.Labels {
		t := strings.ToLower(l.Type)
		if t == "system" {
			d := strings.ToLower(l.Name)
			switch d {
			case "x86", "x64", "arm32", "arm64":
				return d
			}
		}
	}
	return Unknown
}

func (r *RunnerV2) GetExternalJobID() string {
	if r.AssignedRequest == nil {
		return ""
	}

	return r.AssignedRequest.PlanID + "," + r.AssignedRequest.JobID
}

type RunnersListV2 struct {
	Count int64       `json:"count"`
	Value []*RunnerV2 `json:"value"`
}

type AccessPolicy struct {
	PermissionType       string           `json:"permissionType"`
	SelectedRepositories []types.GlobalID `json:"selectedRepositories"`
}

const Unknown = "unknown"

type JITRunnerSettings struct {
	Name          string   `json:"name"`
	RunnerGroupID int64    `json:"runnerGroupId"`
	Labels        []string `json:"labels"`
	WorkFolder    string   `json:"workFolder,omitempty"`
	GithubURL     string   `json:"githubUrl,omitempty"`
}

type JITRunnerConfig struct {
	Runner           *RunnerV2 `json:"runner"`
	EncodedJITConfig string    `json:"encodedJITConfig"`
}
