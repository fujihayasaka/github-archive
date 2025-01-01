package stats

import (
	"context"

	"github.com/github/go-reqmeta/v2"
	"github.com/github/go-stats"
	"github.com/github/go-twirp/v2/server"
	"github.com/twitchtv/twirp"
)

// TagsFunc is a function that can generate stats.Tags based on a context.Context.
type TagsFunc func(ctx context.Context) stats.Tags

func genTags(ctx context.Context, generators ...TagsFunc) stats.Tags {
	tags := stats.Tags{}

	for _, gen := range generators {
		tags = tags.Merge(gen(ctx))
	}

	return tags
}

// DefaultTags are the set of tags that we recommend are published with every Twirp related metric.
func DefaultTags(ctx context.Context) (tags stats.Tags) {
	tags = stats.Tags{"component": "twirp"}

	if pkg, ok := twirp.PackageName(ctx); ok {
		tags[server.PackageNameLabel] = pkg
	}

	if svc, ok := twirp.ServiceName(ctx); ok {
		tags[server.ServiceNameLabel] = svc
	}

	if mthd, ok := twirp.MethodName(ctx); ok {
		tags[server.MethodNameLabel] = mthd
	}

	if sc, ok := twirp.StatusCode(ctx); ok {
		tags[server.StatusCodeLabel] = sc
	}

	if rm, ok := reqmeta.GetRequestMetadata(ctx); ok {
		tags = rm.StatTags().Merge(tags)
	}

	return tags
}
