package consumers

import (
	"context"
	"fmt"
	"net/url"
	"strconv"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
)

// handleError is called by the supervisor loop to decide whether the
// message was processed correctly.  See MemorySource.Consume()
// Returning an error will cause the same message to be reprocessed
// (offset is not changed).  This is typically not what we want, since
// we have an explicit retry logic in the NewAnalysis
// method. Therefore, this method almost always returns nil.
func handleError(ctx context.Context, err error, m *hydro.Message) error {
	if ctx.Err() != nil {
		// Always return context errors, because we do not know if we would have succeeded by retrying.
		appctx.Logger(ctx).WithError(err).Info("context error")
		return ctx.Err()
	}

	// Stat, Log, and Report
	appctx.Logger(ctx).WithError(err).Error("error when consuming hydro message",
		kvp.String("gh.hydro.msg.topic", m.Topic), kvp.Int("gh.hydro.msg.partition", int(m.Partition)), kvp.Int("gh.hydro.msg.offset", int(m.Offset)))

	partitionStr := strconv.Itoa(int(m.Partition))
	offsetStr := strconv.Itoa(int(m.Offset))
	payload := map[string]string{
		"gh.hydro.msg.topic":                       m.Topic,
		"gh.hydro.msg.partition":                   partitionStr,
		"gh.hydro.msg.offset":                      offsetStr,
		"gh.hydro.msg.url":                         hydroURL(m.Topic, partitionStr, offsetStr),
		"gh.turboscan.splunk_hydro_message_search": splunkURL(m.Topic, partitionStr, offsetStr),
	}
	appctx.Report(ctx, err, payload)

	return nil
}

// hydroURL builds a URL to view the Hydro message in on hydro.githubapp.com
func hydroURL(topic, partition, offset string) string {
	params := url.Values{}
	params.Add("topic", topic)
	params.Add("partition", partition)
	params.Add("offset", offset)
	params.Add("tab", "messages")
	return fmt.Sprintf("https://hydro.githubapp.com/kafka/clusters/potomac/topic?%s", params.Encode())
}

// splunkURL builds a URL to search for logs matching the given hydro message
func splunkURL(topic, partition, offset string) string {
	now := time.Now()
	params := url.Values{}
	params.Add("q", fmt.Sprintf("search gh.hydro.msg.topic=%s gh.hydro.msg.partition=%s gh.hydro.msg.offset=%s index=catchall sourcetype=turboscan", topic, partition, offset))
	params.Add("earliest", strconv.FormatInt(now.Add(-time.Hour).Unix(), 10))
	params.Add("latest", strconv.FormatInt(now.Add(time.Hour).Unix(), 10))
	return fmt.Sprintf("https://splunk.githubapp.com/app/gh_reference_app/search?%s", params.Encode())
}
