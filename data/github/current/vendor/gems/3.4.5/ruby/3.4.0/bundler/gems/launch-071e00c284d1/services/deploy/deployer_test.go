package deploy

import (
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils"
	"github.com/github/launch/workerpool"
)

func newTestService() *service {
	return &service{
		cfg: config{
			WorkflowFilePath: utils.DefaultWorkflowFilePath,
			Log:              logger.NullLogger(),
			Stats:            statter.NullStatter(),
		},
	}
}

func makeService(config config) *service {
	m := workerpool.NewInline(config.Log, config.Stats)
	config.Workers = m
	return &service{cfg: config}
}
