package fromctx

import (
	"context"
	"strconv"

	"github.com/github/go-stats"
	"github.com/simon-engledew/ctxkey"
)

type sloTrackerKey struct {
	ctxkey.ContextKey[stats.Client]
}

var SLOTracker = sloTrackerKey{
	ctxkey.New[stats.Client](stats.NullStatter),
}

func (s sloTrackerKey) Track(ctx context.Context, tagName string, success bool) {
	s.Value(ctx).Counter("slo", stats.Tags{
		"name":    tagName,
		"success": strconv.FormatBool(success),
	}, 1)
}
