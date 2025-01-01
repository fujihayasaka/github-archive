package appctx_test

import (
	"context"
	"testing"

	"go.uber.org/mock/gomock"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/mocks"
)

func TestKVP(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()
	m := mocks.NewMockLogger(mockCtrl)
	m.EXPECT().WithFields(kvp.Uint64("gh.turboscan.foo", 9))

	ctx := appctx.WithLogger(context.Background(), m)
	appctx.With(ctx, kvp.Uint64("gh.turboscan.foo", 9))
}
