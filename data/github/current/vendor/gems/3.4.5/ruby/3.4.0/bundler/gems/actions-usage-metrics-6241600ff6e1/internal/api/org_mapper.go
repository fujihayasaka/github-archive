//go:build !dev

package api

import (
	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

func setMappedScope(_ *proto.Scope, _ config.KustoConfig) {
	// this is compiled for any non-dev (non skaffold) builds. This should be a noop in ci builds, see org_mapper_dev for dev implementation
}
