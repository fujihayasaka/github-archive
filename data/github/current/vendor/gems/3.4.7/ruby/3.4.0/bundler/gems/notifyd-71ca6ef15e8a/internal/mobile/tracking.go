package mobile

import (
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/types/known/anypb"

	schemav0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/job/middlewares/retries/retriables"
	"github.com/github/notifyd/internal/pkg/job/tracking"
)

const metricName string = "tracking_deliver_mobile_push"
const topic = "tracking.notifyd.v0.DeliverMobilePush"

/*
NewTracker will:
  - Unmarshal the DeliverMobilePush message from the Request payload
  - Skip messages that are coming from retries
  - Scrub any sensitive and problematic data from that message so our analytics tooling can
    ingest it. That means removing references to internal types in fields holding `Any` types
    and replacing them with smaller types that live inside hydro-schemas.
  - Publish the final message to Hydro
*/
func NewTracker(
	telem *telemetry.Provider,
	statter stats.Client,
	publisher *hydropkg.Publisher,
) job.Handler {
	metered := hydro.NewMeteredPublisher(
		topic,
		metricName,
		publisher,
		metrics.NewPublisherMetrics(telem, statter),
	)

	return tracking.NewJobTracker(metricName, metered, filter, scrubLayoutData)
}

// filter will return false if a message has retry attempts since these messages should not be tracked
func filter(msg *schemav0.DeliverMobilePush) (bool, string) {
	retriable := &retriables.MobilePush{DeliverMobilePush: msg}
	if retriable.GetAttempts() > 0 {
		return false, "the message has retry attempts"
	}

	return true, ""
}

// The DeliverMobilePush.LayoutData field is of google's Any type.
// We need to make sure this is safe to ingest, that is, it hold references
// to hydro-schemas defined messages. We also want to remove sensitive data.
func scrubLayoutData(msg *schemav0.DeliverMobilePush) error {
	layout := msg.GetLayoutData()
	if layout == nil {
		return nil
	}

	summary := entities.LayoutSummary{Kind: layout.GetTypeUrl()}
	if anysummary, err := anypb.New(&summary); err == nil {
		msg.LayoutData = anysummary
	} else {
		msg.LayoutData = nil
	}

	return nil
}
