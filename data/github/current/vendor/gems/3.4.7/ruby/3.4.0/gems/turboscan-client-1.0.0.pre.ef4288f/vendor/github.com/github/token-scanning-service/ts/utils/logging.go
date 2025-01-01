package utils

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/spokes-proto/gen/go/v1/types"

	hydro_schemas_github_v1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"

	"github.com/github/token-scanning-service/ts/twirp/proto/job"
)

type LoggerKey struct{}
type StatterKey struct{}

func ContextWithLogger(ctx context.Context, logger log.Logger) context.Context {
	return context.WithValue(ctx, LoggerKey{}, logger)
}

func LoggerFromContext(ctx context.Context, orDefault ...log.Logger) log.Logger {
	if logger, ok := ctx.Value(LoggerKey{}).(log.Logger); ok {
		return logger
	}
	for _, l := range orDefault {
		if l != nil {
			return l
		}
	}
	return nil
}

func RepoPushScanRefUpdateKVPs(ru *job.RefUpdate) []kvp.Field {
	return []kvp.Field{
		kvp.String("gh.tss.ref_name", ru.GetRef()),
		kvp.String("before_commit", ru.GetBefore()),
		kvp.String("after_commit", ru.GetAfter()),
	}
}

func GistPushScanRefUpdateKVPs(ru *hydro_schemas_github_v1.GistPush_RefUpdate) []kvp.Field {
	return []kvp.Field{
		kvp.String("gh.tss.ref_name", ru.GetRefName()),
		kvp.String("before_commit", ru.GetPreviousRefOid()),
		kvp.String("after_commit", ru.GetCurrentRefOid()),
	}
}

func PostReceiveRefUpdateKVPs(ru *hydro_schemas_github_v1.PostReceive_RefUpdate) []kvp.Field {
	return []kvp.Field{
		kvp.String("gh.tss.ref_name", ru.GetRefName()),
		kvp.String("before_commit", ru.GetPreviousRefOid()),
		kvp.String("after_commit", ru.GetCurrentRefOid()),
	}
}

func SpokesRefUpdateKVPs(ru *types.ReferenceUpdate) []kvp.Field {
	return []kvp.Field{
		kvp.String("gh.tss.ref_name", ru.GetReference().String()),
		kvp.String("before_commit", ru.GetBefore().String()),
		kvp.String("after_commit", ru.GetAfter().String()),
	}
}

func LoggerWithCtxJobFields(ctx context.Context, logger log.Logger) log.Logger {
	logger = LoggerWithCtxJobQueue(ctx, logger)
	logger = LoggerWithCtxJobID(ctx, logger)
	//TODO: Add More!
	return logger
}

type JobQueueContextKey struct{}

func ContextWithJobQueue(ctx context.Context, queueName string) context.Context {
	if ctx == nil {
		ctx = context.Background()
	}
	return context.WithValue(ctx, JobQueueContextKey{}, queueName)
}

func JobQueueFromContext(ctx context.Context) string {
	if ctx == nil {
		return ""
	}
	if queue, ok := ctx.Value(JobQueueContextKey{}).(string); ok {
		return queue
	}
	return ""
}

func LoggerWithCtxJobQueue(ctx context.Context, logger log.Logger) log.Logger {
	if queue := JobQueueFromContext(ctx); queue != "" {
		return logger.WithFields(kvp.String("gh.aqueduct.queue.name", queue))
	}
	return logger
}

type JobIDCtxKey struct{}

func ContextWithJobID(ctx context.Context, jobID string) context.Context {
	if ctx == nil {
		ctx = context.Background()
	}
	return context.WithValue(ctx, JobIDCtxKey{}, jobID)
}

func JobIDFromContext(ctx context.Context) string {
	if ctx == nil {
		return ""
	}
	if queue, ok := ctx.Value(JobIDCtxKey{}).(string); ok {
		return queue
	}
	return ""
}

func LoggerWithCtxJobID(ctx context.Context, logger log.Logger) log.Logger {
	if jobID := JobIDFromContext(ctx); jobID != "" {
		return logger.WithFields(kvp.String("gh.tss.job.id", jobID), kvp.String("gh.request_id", jobID))
	}
	return logger
}

func ContextWithStatter(ctx context.Context, statter stats.Client) context.Context {
	return context.WithValue(ctx, StatterKey{}, statter)
}

func StatterFromContext(ctx context.Context) stats.Client {
	if statter, ok := ctx.Value(StatterKey{}).(stats.Client); ok {
		return statter
	}
	return nil
}
