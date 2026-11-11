package aqueduct

import (
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
)

const (
	appKey           = "aqueduct_app"
	queuesKey        = "aqueduct_queues"
	jobQueueKey      = "aqueduct_job_queue"
	jobIDKey         = "aqueduct_job_id"
	workerLoggerName = "aqueduct_worker"
	clientLoggerName = "aqueduct_client"
)

func newLogger() (log.Logger, error) {
	tp, err := telemetry.NewFromEnv()
	if err != nil {
		return nil, err
	}

	return tp.Logger.Named("aqueduct_client_go"), nil
}

func newWorkerLogger(logger log.Logger) (log.Logger, error) {
	if logger == nil {
		var err error
		logger, err = newLogger()
		if err != nil {
			return nil, err
		}
	}
	return logger.Named(workerLoggerName).WithFields(staticKvps()...), nil
}

func newClientLogger(logger log.Logger) (log.Logger, error) {
	if logger == nil {
		var err error
		logger, err = newLogger()
		if err != nil {
			return nil, err
		}
	}
	return logger.Named(clientLoggerName).WithFields(staticKvps()...), nil
}

// Static kvps used for logging
func staticKvps() []kvp.Field {
	return []kvp.Field{
		kvp.String("package", "github.com/github/aqueduct-client-go/pkg/aqueduct"),
	}
}

func kvpsForWorkerMetadata(wm WorkerMetadata, clientID string) []kvp.Field {
	return []kvp.Field{
		kvp.String("client_id", clientID),
		kvp.String("worker_hostname", wm.Hostname),
		kvp.Int("worker_pid", wm.PID),
		kvp.String("worker_id", wm.ID),
	}
}

// Dynamic fields used for logging
func kvpsForAppQueues(app string, queues []string) []kvp.Field {
	return []kvp.Field{
		kvp.String(appKey, app),
		kvp.Any(queuesKey, queues),
	}
}

func kvpsForJob(job Job) []kvp.Field {
	kvps := []kvp.Field{
		kvp.String(appKey, job.App),
		kvp.String(jobQueueKey, job.Queue),
	}

	// Sometimes the id is not available (e.g. sending a job)
	if job.ID != "" {
		kvps = append(kvps, kvp.String(jobIDKey, job.ID))
	}

	return kvps
}
