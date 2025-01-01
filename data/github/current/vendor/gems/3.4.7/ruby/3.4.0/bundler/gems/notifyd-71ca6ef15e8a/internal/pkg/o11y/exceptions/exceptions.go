// Package exceptions implements an exception reporter.
package exceptions

import (
	"context"
	"strconv"

	ghexceptions "github.com/github/go-exceptions"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"

	"github.com/github/notifyd/internal/pkg/config/deployment"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y"
)

// Reporter is a proxy interface that we use in order to be able to mock our exceptions reporter in
// tests.
//
// By using it as the argument of a function, we allow our Reporter to be mocked when needed or even
// extended.
type Reporter interface {
	Report(ctx context.Context, exception error, payload map[string]string) error
}

// NewReporter creates a new exception reporter.
func NewReporter(cfg deployment.Config, unitName string, exporter ghexceptions.Exporter) (Reporter, error) {
	opts := []ghexceptions.Option{
		ghexceptions.WithApplication("notifyd"),
		ghexceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		ghexceptions.WithExporter(exporter),
		ghexceptions.WithValues(map[string]string{
			"deployment.environment": cfg.Environment,
			"gh.deployment.sha":      cfg.SHA,
			"gh.deployment.ref":      cfg.Ref,
			"gh.notifyd.unit.name":   unitName,
		}),
	}
	reporter, err := ghexceptions.NewReporter(opts...)
	if err != nil {
		err = errors.Wrap(err, "couldn't initialize exception reporter")
		return nil, err
	}

	return reporter, nil
}

// Payload extracts the exception payload from the context
func Payload(ctx context.Context) map[string]string {
	payload := make(map[string]string)

	if val := o11y.CtxGetDeploymentEnv(ctx); val != "" {
		payload["deployment.environment"] = val
	}

	if val := o11y.CtxGetUnit(ctx); val != "" {
		payload["gh.notifyd.unit.name"] = val
	}

	if val := o11y.CtxGetRequestID(ctx); val != "" {
		payload["gh.request_id"] = val
	}

	if val := o11y.CtxGetAqueductParallelJobs(ctx); val != "" {
		payload["gh.notifyd.aqueduct.parallel_jobs"] = val
	}

	if val := o11y.CtxGetAqueductApp(ctx); val != "" {
		payload["gh.aqueduct.app"] = val
	}

	if val := o11y.CtxGetAqueductQueue(ctx); val != "" {
		payload["gh.aqueduct.queue.name"] = val
	}

	if val := o11y.CtxGetHydroConsumer(ctx); val != "" {
		payload["messaging.client_id"] = val
	}

	if val := o11y.CtxGetHydroOffset(ctx); val != "" {
		payload["messaging.message.offset"] = val
	}

	if val := o11y.CtxGetHydroPartition(ctx); val != "" {
		payload["messaging.message.partition"] = val
	}

	if val := o11y.CtxGetHydroTopic(ctx); val != "" {
		payload["messaging.message.topic"] = val
	}

	if val := o11y.CtxGetListType(ctx); val != "" {
		payload["gh.notifications.list.type"] = val
	}

	if val := o11y.CtxGetListID(ctx); val != "" {
		payload["gh.notifications.list.id"] = val
	}

	if val := o11y.CtxGetThreadType(ctx); val != "" {
		payload["gh.notifications.thread.type"] = val
	}

	if val := o11y.CtxGetThreadID(ctx); val != "" {
		payload["gh.notifications.thread.id"] = val
	}

	if val := o11y.CtxGetCommentType(ctx); val != "" {
		payload["gh.notifications.comment.type"] = val
	}

	if val := o11y.CtxGetCommentID(ctx); val != "" {
		payload["gh.notifications.comment.id"] = val
	}

	if val := o11y.CtxGetActorID(ctx); val != int64(0) {
		payload["gh.actor.id"] = strconv.FormatInt(val, 10)
	}

	if val := o11y.CtxGetUserID(ctx); val != int64(0) {
		payload["gh.user.id"] = strconv.FormatInt(val, 10)
	}

	if val := o11y.CtxGetSubjectType(ctx); val != "" {
		payload["gh.notifications.subject.type"] = val
	}

	if val := o11y.CtxGetSubjectValue(ctx); val != "" {
		payload["gh.notifications.subject.id"] = val
	}

	if val := o11y.CtxGetPackage(ctx); val != "" {
		payload["code.namespace"] = val
	}

	if val := o11y.CtxGetMethod(ctx); val != "" {
		payload["code.function"] = val
	}

	if val := o11y.CtxGetTenantSlug(ctx); val != "" {
		payload["gh.tenant"] = val
	}

	return payload
}
