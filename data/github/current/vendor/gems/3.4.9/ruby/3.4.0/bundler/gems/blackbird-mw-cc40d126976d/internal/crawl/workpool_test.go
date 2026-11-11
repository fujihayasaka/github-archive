package crawl_test

import (
	"context"
	"testing"

	"github.com/github/blackbird-mw/internal/crawl"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_CreatePoolAndClose(t *testing.T) {
	ctx := context.Background()
	const workers = 2
	pool := crawl.NewWorkPool(ctx, nil, nil, workers, helpers.Corpus(t))
	pool.Close()
}
