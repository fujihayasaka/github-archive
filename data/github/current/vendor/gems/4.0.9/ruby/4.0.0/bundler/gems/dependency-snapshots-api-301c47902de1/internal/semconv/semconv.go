package semconv // Package semconv provides semantic conventions for KVPs as per https://otel.githubapp.com/.

import (
	"github.com/github/github-telemetry-go/kvp"
	"go.uber.org/zap/zapcore"
)

// Common semantic conventions

func RequestID(id string) zapcore.Field {
	return kvp.String("gh.request.id", id)
}

func MessagingMessageID(id string) zapcore.Field {
	return kvp.String("messaging.message.id", id)
}

// Repository semantic conventions

func RepoID(id uint64) zapcore.Field {
	return kvp.Uint64("gh.repo.id", id)
}

func RepoVisibility(visibility string) zapcore.Field {
	return kvp.String("gh.repo.visibility", visibility)
}

func OwnerID(id uint64) zapcore.Field {
	return kvp.Uint64("gh.repo.owner.id", id)
}

// Actor semantic conventions

func ActorID(id uint64) zapcore.Field {
	return kvp.Uint64("gh.actor.id", id)
}

func ActorGlobalID(id string) zapcore.Field {
	return kvp.String("gh.actor.global_id", id)
}

func ActorLogin(id string) zapcore.Field {
	return kvp.String("gh.user.login", id)
}

// Git semantic conventions

func GitRef(ref string) zapcore.Field {
	return kvp.String("gh.git.ref", ref)
}

func GitPushBeforeOid(oid string) zapcore.Field {
	return kvp.String("gh.git.push.before_oid", oid)
}

func GitPushAfterOid(oid string) zapcore.Field {
	return kvp.String("gh.git.push.after_oid", oid)
}

func IsDefaultBranch(isDefault bool) zapcore.Field {
	return kvp.Bool("gh.repo.is_default_branch", isDefault)
}

// Job semantic conventions

func JobTriggeredBy(triggeredBy string) zapcore.Field {
	return kvp.String("gh.job.triggered_by", triggeredBy)
}

// Reset Events semantic conventions

func ResetManifestsTrigger(payload string) zapcore.Field {
	return kvp.String("gh.event.reset_manifests.trigger", payload)
}

func ResetManifestsAction(payload string) zapcore.Field {
	return kvp.String("gh.event.reset_manifests.action", payload)
}

// Dynamic Workflows semantic conventions

func DynamicWorkflowRunID(id uint64) zapcore.Field {
	return kvp.Uint64("gh.dgp.dynamic_workflow.run_id", id)
}

func DynamicWorkflowJobID(id string) zapcore.Field {
	return kvp.String("gh.dgp.dynamic_workflow.job_id", id)
}

// Aqueduct semantic conventions

func AqueductExecutionTimeMs(timeMs int64) zapcore.Field {
	return kvp.Int64("aqueduct.handler.execution.time_ms", timeMs)
}

func AqueductHandlerQueue(queue string) zapcore.Field {
	return kvp.String("aqueduct.handler.queue", queue)
}

// Hydro semantic conventions

func HydroExecutionTimeMs(timeMs int64) zapcore.Field {
	return kvp.Int64("hydro.execution.time_ms", timeMs)
}

func HydroEventID(v string) zapcore.Field {
	return kvp.String("hydro.event.id", v)
}

func HydroDestinationName(v string) zapcore.Field {
	return kvp.String("hydro.destination.name", v)
}

func HydroDestinationPartitionID(v int32) zapcore.Field {
	return kvp.Int32("hydro.destination.partition.id", v)
}

func HydroKafkaMessageOffset(v int64) zapcore.Field {
	return kvp.Int64("hydro.kafka.message.offset", v)
}
