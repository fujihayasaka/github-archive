package gitauth

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewSetUpPushStateRequest(repository *types.Repository, quarantineID string, hosts ...*HostStatus) *SetUpPushStateRequest {
	return &SetUpPushStateRequest{
		Repository:   repository,
		QuarantineId: quarantineID,
		Hosts:        hosts,
	}
}

func OKHostStatus(replicaName, host, path string) *HostStatus {
	return &HostStatus{
		ReplicaName: replicaName,
		Host:        host,
		Path:        path,
		Result:      &HostStatus_OkResult{&OkResult{}},
	}
}

func FailedHostStatus(replicaName, host, path, errorMessage string) *HostStatus {
	return &HostStatus{
		ReplicaName: replicaName,
		Host:        host,
		Path:        path,
		Result:      &HostStatus_ErrorResult{&ErrorResult{ErrorMessage: errorMessage}},
	}
}
