// Package twirp's CustomFieldsInterceptor inspects each Twirp request and
// copies a fixed set of identifier fields onto the request-scoped customfields
// store. Those customfields are attached to error reports sent via the
// go-server reporter (Failbotg, proxied to Sentry) and merged into the
// per-request log line by loggingHook.

package twirp

import (
	"context"
	"strconv"

	"github.com/github/go-server/runtime/telemetry/customfields"
	"github.com/twitchtv/twirp"
)

// Capability interfaces. A request type qualifies for a given telemetry
// field if and only if it has the corresponding GetXxx() method (which
// protoc-gen-go always generates for proto3 messages).

type (
	repositoryIDer      interface{ GetRepositoryId() uint64 }
	organizationIDer    interface{ GetOrganizationId() uint64 }
	enterpriseIDer      interface{ GetEnterpriseId() uint64 }
	alertIDer           interface{ GetAlertId() uint64 }
	alertNumberer       interface{ GetAlertNumber() uint32 }
	userIDer            interface{ GetUserId() uint64 }
	pullRequestIDer     interface{ GetPullRequestId() uint64 }
	pullRequestNumberer interface{ GetPullRequestNumber() uint64 }
	forkRepositoryIDer  interface{ GetForkRepositoryId() uint64 }
	commitSHAer         interface{ GetCommitSha() string }
	baseSHAer           interface{ GetBaseSha() string }
)

// CustomFieldsInterceptor returns a Twirp interceptor that records well-known
// identifier fields from the request proto onto the request-scoped
// customfields store.
//
// It depends on the request context carrying a requestcache (installed by
// reporterContextHook at the RequestReceived stage). If no requestcache is
// present, customfields.AddTag/AddField silently drop the value; the request
// itself is unaffected.
func CustomFieldsInterceptor() twirp.Interceptor {
	return func(next twirp.Method) twirp.Method {
		return func(ctx context.Context, req any) (any, error) {
			recordCustomFieldsFromRequest(ctx, req)
			return next(ctx, req)
		}
	}
}

// recordCustomFieldsFromRequest dispatches each known telemetry field for the
// given request. Tag vs. plain field is decided per call below: use a tag
// for IDs we routinely filter Sentry by, a field for everything else.
func recordCustomFieldsFromRequest(ctx context.Context, req any) {
	if r, ok := req.(repositoryIDer); ok {
		addUintTag(ctx, "repository_id", r.GetRepositoryId())
	}
	if r, ok := req.(organizationIDer); ok {
		addUintTag(ctx, "organization_id", r.GetOrganizationId())
	}
	if r, ok := req.(enterpriseIDer); ok {
		addUintTag(ctx, "enterprise_id", r.GetEnterpriseId())
	}
	if r, ok := req.(alertIDer); ok {
		addUintField(ctx, "alert_id", r.GetAlertId())
	}
	if r, ok := req.(alertNumberer); ok {
		addUintField(ctx, "alert_number", r.GetAlertNumber())
	}
	if r, ok := req.(pullRequestIDer); ok {
		addUintField(ctx, "pull_request_id", r.GetPullRequestId())
	}
	if r, ok := req.(pullRequestNumberer); ok {
		addUintField(ctx, "pull_request_number", r.GetPullRequestNumber())
	}
	if r, ok := req.(forkRepositoryIDer); ok {
		addUintField(ctx, "fork_repository_id", r.GetForkRepositoryId())
	}
	if r, ok := req.(userIDer); ok {
		addUintTag(ctx, "user_id", r.GetUserId())
	}
	if r, ok := req.(commitSHAer); ok {
		addStringField(ctx, "commit_sha", r.GetCommitSha())
	}
	if r, ok := req.(baseSHAer); ok {
		addStringField(ctx, "base_sha", r.GetBaseSha())
	}
}

// uintID is the set of unsigned integer ID widths used by the request protos.
// A single generic helper can then accept either width without per-width
// duplication or caller-side casts.
type uintID interface {
	~uint32 | ~uint64
}

func addUintTag[T uintID](ctx context.Context, key string, v T) {
	if v == 0 {
		return
	}
	customfields.AddTag(ctx, key, strconv.FormatUint(uint64(v), 10))
}

func addUintField[T uintID](ctx context.Context, key string, v T) {
	if v == 0 {
		return
	}
	customfields.AddField(ctx, key, strconv.FormatUint(uint64(v), 10))
}

func addStringField(ctx context.Context, key, v string) {
	if v == "" {
		return
	}
	customfields.AddField(ctx, key, v)
}
