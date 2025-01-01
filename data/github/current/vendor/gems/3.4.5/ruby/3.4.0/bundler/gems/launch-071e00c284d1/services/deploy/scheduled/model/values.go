package model

import (
	"github.com/github/launch/types"
)

type ScheduleSync struct {
	RepoNodeID                types.GlobalID
	InstallationID            int64
	FlowIdentifiersToSchedule map[types.WorkflowSelector]string
	Tier                      types.RepositoryTier
	ActorID                   types.GlobalID
	ActorLogin                string
	CommitSHA                 types.CommitSha
	InvalidFiles              []string
	OwnerID                   int64
}
