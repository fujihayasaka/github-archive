// Package layout implements the layout processing of emails.
package layout

import (
	"context"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	emaildatastructures "github.com/github/notifyd/internal/email/datastructures"
	"github.com/github/notifyd/internal/email/layout/basic"
	"github.com/github/notifyd/internal/email/layout/config"
	"github.com/github/notifyd/internal/email/layout/email"
	"github.com/github/notifyd/internal/email/layout/raw"
	"github.com/github/notifyd/internal/email/pipeline"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Processor represents a layout processor.
type Processor interface {
	Process(ctx context.Context, tenant tenancy.Tenant, deliverEmailData emaildatastructures.DeliverEmailData, msg *emaildatastructures.Email) (email.Email, error)
}

// ErrUnknownProcessor is an error raised when the processor is unknown.
var ErrUnknownProcessor = errors.New("unknown processor")

// BuildProcessor creates a new layout processor.
func BuildProcessor(cfg config.Config, telem *telemetry.Provider, statter stats.Client, postprocessor pipeline.PostProcessor, typeURL string) (Processor, error) {
	switch typeURL {
	case basic.TypeURL:
		return basic.NewProcessor(cfg, telem, statter, postprocessor), nil
	case raw.TypeURL:
		return raw.NewProcessor(cfg, telem, statter), nil
	default:
		return nil, errors.Wrap(ErrUnknownProcessor, typeURL)
	}
}
