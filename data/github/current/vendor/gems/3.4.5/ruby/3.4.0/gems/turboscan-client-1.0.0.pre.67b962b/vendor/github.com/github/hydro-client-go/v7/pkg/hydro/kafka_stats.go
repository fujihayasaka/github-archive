package hydro

import (
	"regexp"
	"time"

	"github.com/github/go-stats"
	"github.com/rcrowley/go-metrics"
)

// Default rate used to sample Kafka client stats when enabled.
const DefaultKafkaSampleRate = 5 * time.Second

// TODO: add comment

type metricStatsAdapter struct {
	prefix string
	client stats.Client
}

// TODO: add comment

func (msa *metricStatsAdapter) Counter(name string, t stats.Tags, i interface{}) {
	var c metrics.Counter
	switch v := i.(type) {
	case *metrics.StandardCounter:
		c = v.Snapshot()
		v.Clear()
	case *metrics.CounterSnapshot:
		c = v
	default:
		return
	}

	msa.client.Counter(msa.prefix+name, t, c.Count())
}

// TODO: add comment

func (msa *metricStatsAdapter) Meter(name string, t stats.Tags, i interface{}) {
	m, ok := i.(metrics.Meter)
	if !ok {
		return
	}

	ms := m.Snapshot()
	name = msa.prefix + name
	msa.client.Gauge(name+".avg", t, int64(ms.RateMean()))
	msa.client.Gauge(name+".1m", t, int64(ms.Rate1()))
	msa.client.Gauge(name+".5m", t, int64(ms.Rate5()))
	msa.client.Gauge(name+".15m", t, int64(ms.Rate15()))
}

// TODO: add comment

func (msa *metricStatsAdapter) Histogram(name string, t stats.Tags, i interface{}) {
	h, ok := i.(metrics.Histogram)
	if !ok {
		return
	}

	hs := h.Snapshot()
	name = msa.prefix + name
	msa.client.Gauge(name+".count", t, hs.Count())
	msa.client.Gauge(name+".sum", t, hs.Sum())
	msa.client.Gauge(name+".min", t, hs.Min())
	msa.client.Gauge(name+".max", t, hs.Max())
	msa.client.Gauge(name+".avg", t, int64(hs.Mean()))
	msa.client.Gauge(name+".p50", t, int64(hs.Percentile(50)))
	msa.client.Gauge(name+".p90", t, int64(hs.Percentile(90)))
	msa.client.Gauge(name+".p95", t, int64(hs.Percentile(95)))
	msa.client.Gauge(name+".p99", t, int64(hs.Percentile(99)))
}

var saramaMetricRegexps = []*regexp.Regexp{
	// Broker stats
	regexp.MustCompile(`^(incoming-byte-rate)-for-broker-(\S+)$`),
	regexp.MustCompile(`^(outgoing-byte-rate)-for-broker-(\S+)$`),
	regexp.MustCompile(`^(request-rate)-for-broker-(\S+)$`),
	regexp.MustCompile(`^(request-size)-for-broker-(\S+)$`),
	regexp.MustCompile(`^(request-latency-in-ms)-for-broker-(\S+)$`),
	regexp.MustCompile(`^(response-rate)-for-broker-(\S+)$`),
	regexp.MustCompile(`^(response-size)-for-broker-(\S+)$`),
	regexp.MustCompile(`^(requests-in-flight)-for-broker-(\S+)$`),

	// Producer stats
	regexp.MustCompile(`^(batch-size)-for-topic-(\S+)$`),
	regexp.MustCompile(`^(record-send-rate)-for-topic-(\S+)$`),
	regexp.MustCompile(`^(records-per-request)-for-topic-(\S+)$`),
	regexp.MustCompile(`^(compression-ratio)-for-topic-(\S+)$`),

	// Consumer stats
	regexp.MustCompile(`^consumer-batch-size$`),
}

// TODO: add comment

func matchSaramaMetric(s string) []string {
	for _, re := range saramaMetricRegexps {
		if m := re.FindStringSubmatch(s); m != nil {
			return m
		}
	}
	return nil
}

// TODO: add comment

type saramaStatsReporter struct {
	metrics metrics.Registry
	adapter *metricStatsAdapter
	ticker  *time.Ticker
}

// TODO: add comment

func (ssr *saramaStatsReporter) Run() {
	for {
		_, ok := <-ssr.ticker.C
		if !ok {
			return // stopped
		}

		ssr.metrics.Each(ssr.report)
	}
}

// TODO: add comment

func (ssr *saramaStatsReporter) Stop() {
	if ssr.ticker != nil {
		ssr.ticker.Stop()
	}
}

// TODO: add comment

func (ssr *saramaStatsReporter) report(name string, i interface{}) {
	var tagValue string
	m := matchSaramaMetric(name)
	switch len(m) {
	case 1:
		name = m[0]
	case 3:
		name = m[1]
		tagValue = m[2]
	default:
		return
	}

	switch name {
	// Broker stats
	case "incoming-byte":
		// Bytes/second read off a given broker
		tags := stats.Tags{"broker": tagValue}
		ssr.adapter.Meter("receive.bytes.per_second", tags, i)
	case "outgoing-byte":
		// Bytes/second written to a given broker
		tags := stats.Tags{"broker": tagValue}
		ssr.adapter.Meter("send.bytes.per_second", tags, i)
	case "request-rate":
		// Requests/second sent to a given broker
		tags := stats.Tags{"broker": tagValue}
		ssr.adapter.Meter("request.per_second", tags, i)
	case "request-size":
		// Distribution of the request size in bytes for a given broker
		tags := stats.Tags{"broker": tagValue}
		ssr.adapter.Histogram("request.size.bytes", tags, i)
	case "request-latency-in-ms":
		// Distribution of the request latency in ms for a given broker
		tags := stats.Tags{"broker": tagValue}
		ssr.adapter.Histogram("request.latency.milliseconds", tags, i)
	case "requests-in-flight":
		// The current number of in-flight requests awaiting a response for a
		// given broker
		tags := stats.Tags{"broker": tagValue}
		ssr.adapter.Counter("request.pending", tags, i)
	case "response-rate":
		// Responses/second received from a given broker
		tags := stats.Tags{"broker": tagValue}
		ssr.adapter.Meter("response.per_second", tags, i)
	case "response-size":
		// Distribution of the response size in bytes for a given broker
		tags := stats.Tags{"broker": tagValue}
		ssr.adapter.Histogram("response.size.bytes", tags, i)

	// Producer stats
	case "batch-size":
		// Distribution of the number of bytes sent per partition per request
		// for a given topic
		tags := stats.Tags{"topic": tagValue}
		ssr.adapter.Histogram("request.batch.size.bytes", tags, i)
	case "record-send-rate":
		// Records/second sent to a given topic
		tags := stats.Tags{"topic": tagValue}
		ssr.adapter.Meter("send.message.per_second", tags, i)
	case "records-per-request":
		// Distribution of the number of records sent per request for a given
		// topic
		tags := stats.Tags{"topic": tagValue}
		ssr.adapter.Histogram("request.batch.size", tags, i)
	case "compression-ratio":
		// Distribution of the compression ratio times 100 of record batches
		// for a given topic
		tags := stats.Tags{"topic": tagValue}
		ssr.adapter.Histogram("request.compression.ratio", tags, i)

		// Consumer stats
	case "consumer-batch-size":
		// Distribution of the number of messages in a batch
		ssr.adapter.Histogram("response.batch.size", nil, i)
	}
}
