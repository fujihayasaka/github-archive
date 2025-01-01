// Package managed_analyses provides the Resolver for the github.turboscan.ManagedAnalyses Twirp endpoint.
package managed_analyses

import (
	ma "github.com/github/turboscan/ts/managedanalyses/service"
)

const (
	ErrorMsgCodeqlConfigConflict = "a new configuration is already being staged"
)

type Service struct {
	ma                      *ma.ManagedAnalyses
	javaBuildlessDisabled   bool
	cSharpBuildlessDisabled bool
}

func New(ma *ma.ManagedAnalyses, javaBuildlessDisabled bool, cSharpBuildlessDisabled bool) *Service {
	return &Service{
		ma:                      ma,
		javaBuildlessDisabled:   javaBuildlessDisabled,
		cSharpBuildlessDisabled: cSharpBuildlessDisabled,
	}
}
