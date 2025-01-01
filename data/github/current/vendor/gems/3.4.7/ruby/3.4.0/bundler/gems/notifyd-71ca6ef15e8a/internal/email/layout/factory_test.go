package layout

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/go-stats"
	"github.com/github/notifyd/internal/email/layout/basic"
	"github.com/github/notifyd/internal/email/layout/config"
	"github.com/github/notifyd/internal/email/pipeline"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

func TestExistingProcessor(t *testing.T) {
	r := require.New(t)
	_, err := BuildProcessor(config.Config{}, logs.NullTelem, stats.NullStatter, &pipeline.PostProcessorMock{}, basic.TypeURL)
	r.NoError(err)
}

func TestMissingProcessor(t *testing.T) {
	r := require.New(t)
	_, err := BuildProcessor(config.Config{}, logs.NullTelem, stats.NullStatter, &pipeline.PostProcessorMock{}, "non-existent")
	r.Equal(ErrUnknownProcessor, err)
}
