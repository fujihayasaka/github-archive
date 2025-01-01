package freno

import (
	"context"
)

type NopClient struct{}

var nopCheckResponse = &CheckResponse{
	CanWrite:       true,
	ReplicationLag: 0,
}

func (NopClient) Check(_ context.Context, _ string) (*CheckResponse, error) {
	return nopCheckResponse, nil
}

func (NopClient) CanWriteToClusters(_ context.Context, clusters ...string) (map[string]bool, error) {
	res := make(map[string]bool, len(clusters))
	for _, c := range clusters {
		res[c] = true
	}
	return res, nil
}
