package observability

import (
	"context"

	"github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/logkeys"
	"github.com/github/launch/observability/statter"
)

func LogStage(ctx context.Context, log logger.Logger, stageName logkeys.StageName) {
	log.Log(ctx, "Stage", kvp.String(logkeys.StageNameField, string(stageName)))
}

// Logs the tags added to stats, along with fields added to ctx and any fields supplied. These logs are intended
// for investigating the distinct number of resources or users impacted by errors, and determining whether
// to status following a metric monitor alert. We have to avoid tagging metrics with unbounded values (e.g.
// timestamps, repo_global_id), but we can log those values.
func LogStatTags(ctx context.Context, log logger.Logger, key string, nonRMDTags statter.Tags, fields ...kvp.Field) {
	var rmdTags reqmeta.Tags
	if rmd, ok := ctx.Value(reqmeta.RMDContextKey).(*reqmeta.RequestMetadata); ok {
		rmdTags = rmd.StatTags()
	}

	log.Debug(ctx, "statTags", combineFieldsTags(key, fields, statter.Tags(rmdTags).Merge(nonRMDTags))...)
}

func combineFieldsTags(statKey string, fields []kvp.Field, tags statter.Tags) []kvp.Field {
	allFields := make([]kvp.Field, len(fields)+len(tags)+1)
	copy(allFields, fields)
	i := len(fields)

	for k, v := range tags {
		allFields[i] = kvp.String(k, v)
		i++
	}

	allFields[i] = kvp.String("stat_key", statKey)
	return allFields
}
