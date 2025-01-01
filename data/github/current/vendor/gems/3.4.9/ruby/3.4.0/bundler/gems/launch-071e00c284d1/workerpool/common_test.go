package workerpool

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
)

func Test_run(t *testing.T) {
	suite.Run(t, new(runSuite))
}

type runSuite struct {
	suite.Suite

	log   logger.Logger
	stats statter.Statter

	rmd *reqmeta.RequestMetadata
}

func (r *runSuite) SetupTest() {
	r.rmd = reqmeta.NewRequestMetadata()
	r.log = logger.TestLogger()
	r.stats = statter.NullStatter()
}

func (r *runSuite) runJob(jobName string, job JobFunc) string {
	ctx := context.Background()
	ctx = context.WithValue(ctx, reqmeta.RMDContextKey, r.rmd)
	return run(ctx, r.log, r.stats, jobName, job)
}

func (r *runSuite) TestError() {
	result := r.runJob("testjob", func(context.Context) error {
		return fmt.Errorf("BOOM")
	})
	r.Assert().Equal(failedStatus, result)
}

func (r *runSuite) TestPanic() {
	result := r.runJob("testjob", func(context.Context) error {
		panic("BOOM")
	})
	r.Assert().Equal(failedStatus, result)
}
