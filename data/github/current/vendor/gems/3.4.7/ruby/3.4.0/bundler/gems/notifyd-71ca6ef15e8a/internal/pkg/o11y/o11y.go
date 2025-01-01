// Package o11y implements reporters and loggers for our observability tools.
package o11y

import (
	"context"
	"fmt"

	"github.com/google/uuid"

	"github.com/github/go-http/v2/middleware/requestid"
)

type ctxProcessEnv struct{}
type ctxProcessUnit struct{}

// CtxSetProcessInfo sets the env and the unit (the current program) name into the context so that
// they can be used by o11y tools like logs or error reports.
func CtxSetProcessInfo(ctx context.Context, deploymentEnvironment, unitName string) context.Context {
	ctx = CtxSetDeploymentEnv(ctx, deploymentEnvironment)
	return CtxSetUnit(ctx, unitName)
}

// CtxSetDeploymentEnv stores the deployment env in the context
func CtxSetDeploymentEnv(ctx context.Context, env string) context.Context {
	return context.WithValue(ctx, ctxProcessEnv{}, env)
}

// CtxGetDeploymentEnv returns the env name stored in the context or an empty string
func CtxGetDeploymentEnv(ctx context.Context) string { return ctxGetString(ctx, ctxProcessEnv{}) }

// CtxSetUnit stores the unit name in the context
func CtxSetUnit(ctx context.Context, unit string) context.Context {
	return context.WithValue(ctx, ctxProcessUnit{}, unit)
}

// CtxGetUnit returns the unit name stored in the context or an empty string
func CtxGetUnit(ctx context.Context) string { return ctxGetString(ctx, ctxProcessUnit{}) }

// CtxSetRequestID stores a request ID on the context. In case it can't generate one it stores
// "none"
func CtxSetRequestID(ctx context.Context) context.Context {
	var id string
	if newID, err := uuid.NewRandom(); err == nil {
		id = newID.String()
	} else {
		id = "none"
	}

	return requestid.WithGitHubRequestID(ctx, id)
}

// CtxGetRequestID returns the request id stored in the context or an empty string
func CtxGetRequestID(ctx context.Context) string { return requestid.GetGitHubRequestID(ctx) }

type ctxAqueductQueue struct{}
type ctxAqueductApp struct{}
type ctxParallelJobs struct{}

// AqueductConfigInfo represents aqueduct configuration information
type AqueductConfigInfo interface {
	GetApp() string
	GetQueue() string
	GetParallelJobs() int
}

// CtxSetAqueductInfo stores aqueduct info, namely:
// Aqueduct queue name
// Aqueduct app name
// Number of parallel jobs the worker is handling
func CtxSetAqueductInfo(ctx context.Context, config AqueductConfigInfo) context.Context {
	newCtx := context.WithValue(ctx, ctxAqueductQueue{}, config.GetQueue())
	newCtx = context.WithValue(newCtx, ctxAqueductApp{}, config.GetApp())
	return context.WithValue(newCtx, ctxParallelJobs{}, fmt.Sprint(config.GetParallelJobs()))
}

// CtxGetAqueductQueue returns the queue name stored in the context or an empty string
func CtxGetAqueductQueue(ctx context.Context) string { return ctxGetString(ctx, ctxAqueductQueue{}) }

// CtxGetAqueductApp returns the app name stored in the context or an empty string
func CtxGetAqueductApp(ctx context.Context) string { return ctxGetString(ctx, ctxAqueductApp{}) }

// CtxGetAqueductParallelJobs returns the number of parallel jobs stored in the context or an empty string
func CtxGetAqueductParallelJobs(ctx context.Context) string {
	return ctxGetString(ctx, ctxParallelJobs{})
}

type ctxHydroConsumer struct{}
type ctxHydroPartition struct{}
type ctxHydroTopic struct{}
type ctxHydroOffset struct{}

// HydroRequestInfo describes the interface that any request needs to implement in case they want to
// provide hydro related information to our o11y sources.
type HydroRequestInfo interface {
	HydroOffset(context.Context) int64
	HydroTopic(context.Context) string
	HydroPartition(context.Context) int64
}

// CtxSetHydroInfo stores all the info we can from an hydro message, namely:
//   - Consumer name
//   - Current partition
//   - Current topic
//   - Offset (offsets refer to the current message being processed so it is kind of similar to a
//     unique message id)
func CtxSetHydroInfo(ctx context.Context, consumer string, req HydroRequestInfo) context.Context {
	ctx = context.WithValue(ctx, ctxHydroConsumer{}, consumer)
	ctx = context.WithValue(ctx, ctxHydroPartition{}, fmt.Sprint(req.HydroPartition(ctx)))
	ctx = context.WithValue(ctx, ctxHydroTopic{}, req.HydroTopic(ctx))
	return context.WithValue(ctx, ctxHydroOffset{}, fmt.Sprint(req.HydroOffset(ctx)))
}

// CtxGetHydroConsumer returns the consumer names stored in the context or an empty string
func CtxGetHydroConsumer(ctx context.Context) string { return ctxGetString(ctx, ctxHydroConsumer{}) }

// CtxGetHydroPartition returns the partition stored in the context or an empty string
func CtxGetHydroPartition(ctx context.Context) string { return ctxGetString(ctx, ctxHydroPartition{}) }

// CtxGetHydroTopic returns the topic stored in the context or an empty string
func CtxGetHydroTopic(ctx context.Context) string { return ctxGetString(ctx, ctxHydroTopic{}) }

// CtxGetHydroOffset returns the offset stored in the context or an empty string
func CtxGetHydroOffset(ctx context.Context) string { return ctxGetString(ctx, ctxHydroOffset{}) }

type ctxNotificationID struct{}

// CtxSetNotificationID stores a notification_id in the context
func CtxSetNotificationID(ctx context.Context, notificationID string) context.Context {
	return context.WithValue(ctx, ctxNotificationID{}, notificationID)
}

// CtxGetNotificationID returns the stored notification_id from the context or an empty string
func CtxGetNotificationID(ctx context.Context) string { return ctxGetString(ctx, ctxNotificationID{}) }

// CtxGetListID returns the stored list_id from the context or an empty string
func CtxGetListID(ctx context.Context) string { return ctxGetString(ctx, ctxListID{}) }

type ctxListID struct{}

// CtxSetListID stores a list_id in the context
func CtxSetListID(ctx context.Context, listID string) context.Context {
	return context.WithValue(ctx, ctxListID{}, listID)
}

// CtxGetListType returns the stored list_type from the context or an empty string
func CtxGetListType(ctx context.Context) string { return ctxGetString(ctx, ctxListType{}) }

type ctxListType struct{}

// CtxSetListType stores a list_type in the context
func CtxSetListType(ctx context.Context, listType string) context.Context {
	return context.WithValue(ctx, ctxListType{}, listType)
}

// CtxGetThreadID returns the stored thread_id from the context or an empty string
func CtxGetThreadID(ctx context.Context) string { return ctxGetString(ctx, ctxThreadID{}) }

type ctxThreadID struct{}

// CtxSetThreadID stores a thread_id in the context
func CtxSetThreadID(ctx context.Context, threadID string) context.Context {
	return context.WithValue(ctx, ctxThreadID{}, threadID)
}

// CtxGetThreadType returns the stored thread_type from the context or an empty string
func CtxGetThreadType(ctx context.Context) string { return ctxGetString(ctx, ctxThreadType{}) }

type ctxThreadType struct{}

// CtxSetThreadType stores a thread_type in the context
func CtxSetThreadType(ctx context.Context, threadType string) context.Context {
	return context.WithValue(ctx, ctxThreadType{}, threadType)
}

// CtxGetCommentID returns the stored comment_id from the context or an empty string
func CtxGetCommentID(ctx context.Context) string { return ctxGetString(ctx, ctxCommentID{}) }

type ctxCommentID struct{}

// CtxSetCommentID stores a comment_id in the context
func CtxSetCommentID(ctx context.Context, commentID string) context.Context {
	return context.WithValue(ctx, ctxCommentID{}, commentID)
}

// CtxGetCommentType returns the stored comment_type from the context or an empty string
func CtxGetCommentType(ctx context.Context) string { return ctxGetString(ctx, ctxCommentType{}) }

type ctxCommentType struct{}

// CtxSetCommentType stores a comment_type in the context
func CtxSetCommentType(ctx context.Context, commentType string) context.Context {
	return context.WithValue(ctx, ctxCommentType{}, commentType)
}

// CtxGetReasons returns the stored reasons from the context or an empty string
func CtxGetReasons(ctx context.Context) string { return ctxGetString(ctx, ctxReasons{}) }

type ctxReasons struct{}

// CtxSetReasons stores a reasons in the context
func CtxSetReasons(ctx context.Context, reasons string) context.Context {
	return context.WithValue(ctx, ctxReasons{}, reasons)
}

// CtxGetChannel returns the stored channel from the context or an empty string
func CtxGetChannel(ctx context.Context) string { return ctxGetString(ctx, ctxChannel{}) }

type ctxChannel struct{}

// CtxSetChannel stores a channel in the context
func CtxSetChannel(ctx context.Context, channel string) context.Context {
	return context.WithValue(ctx, ctxChannel{}, channel)
}

type ctxActorID struct{}

// CtxSetActorID stores an actor_id in the context
func CtxSetActorID(ctx context.Context, userID int64) context.Context {
	return context.WithValue(ctx, ctxActorID{}, userID)
}

// CtxGetActorID returns the actor_id stored in the context or 0
func CtxGetActorID(ctx context.Context) int64 { return ctxGetInt64(ctx, ctxActorID{}) }

type ctxSubjectType struct{}

// CtxSetSubjectType stores an subjectType in the context
func CtxSetSubjectType(ctx context.Context, subjectType string) context.Context {
	return context.WithValue(ctx, ctxSubjectType{}, subjectType)
}

// CtxGetSubjectType returns a subject type out of the context
func CtxGetSubjectType(ctx context.Context) string {
	return ctxGetString(ctx, ctxSubjectType{})
}

type ctxSubjectValue struct{}

// CtxSetSubjectValue stores an subjectValue in the context
func CtxSetSubjectValue(ctx context.Context, subjectValue string) context.Context {
	return context.WithValue(ctx, ctxSubjectValue{}, subjectValue)
}

// CtxGetSubjectValue returns an actor_id out of the context
func CtxGetSubjectValue(ctx context.Context) string {
	return ctxGetString(ctx, ctxSubjectValue{})
}

type ctxUserID struct{}

// CtxSetUserID stores a user_id in the context
func CtxSetUserID(ctx context.Context, userID int64) context.Context {
	return context.WithValue(ctx, ctxUserID{}, userID)
}

// CtxGetUserID returns the user_id stored in the context or 0
func CtxGetUserID(ctx context.Context) int64 { return ctxGetInt64(ctx, ctxUserID{}) }

type ctxPackage struct{}

// CtxSetPackage stores a package in the context
func CtxSetPackage(ctx context.Context, pkg string) context.Context {
	return context.WithValue(ctx, ctxPackage{}, pkg)
}

// CtxGetPackage returns the package stored in the context
func CtxGetPackage(ctx context.Context) string {
	return ctxGetString(ctx, ctxPackage{})
}

type ctxMethod struct{}

// CtxSetMethod stores a package in the context
func CtxSetMethod(ctx context.Context, pkg string) context.Context {
	return context.WithValue(ctx, ctxMethod{}, pkg)
}

// CtxGetMethod returns the method stored in the context
func CtxGetMethod(ctx context.Context) string {
	return ctxGetString(ctx, ctxMethod{})
}

type ctxTenantSlug struct{}

// CtxSetTenantSlug stores a tenant slug in the context
func CtxSetTenantSlug(ctx context.Context, slug string) context.Context {
	return context.WithValue(ctx, ctxTenantSlug{}, slug)
}

// CtxGetTenantSlug returns the tenant slug stored in the context
func CtxGetTenantSlug(ctx context.Context) string {
	return ctxGetString(ctx, ctxTenantSlug{})
}

// ctxGetString is a helper to cast the return value of a given key or return an empty value
func ctxGetString(ctx context.Context, key interface{}) string {
	value, ok := ctx.Value(key).(string)

	if ok {
		return value
	}

	return ""
}

// ctxGetInt64 is a helper to cast the return value of a given key or return an empty value
func ctxGetInt64(ctx context.Context, key interface{}) int64 {
	value, ok := ctx.Value(key).(int64)

	if ok {
		return value
	}

	return int64(0)
}
