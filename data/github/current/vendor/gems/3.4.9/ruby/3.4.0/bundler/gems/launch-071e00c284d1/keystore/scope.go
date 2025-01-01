package keystore

import (
	"fmt"
)

func NewScope(env string, org string) (*scope, error) {
	if env == "" {
		return nil, fmt.Errorf("scope environment cannot be empty")
	}
	if org == "" {
		return nil, fmt.Errorf("scope organization cannot be empty")
	}
	return &scope{
		Environment:  env,
		Organization: org,
	}, nil
}

type scope struct {
	Environment  string
	Organization string
}
