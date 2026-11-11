package aqueduct

import (
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/github/go-stats"
)

const (
	defaultStatsAddr = ""
	defaultStatsRate = 10 * time.Second
)

// StatsConfig is used to control how stats are reported.
//
// It must be created NewStatsConfig.
type StatsConfig struct {
	addr        string
	rate        time.Duration
	tags        stats.Tags
	statsClient stats.Client
}

// StatsOption is the functional option type for configuring a StatsConfig.
type StatsOption func(config *StatsConfig) error

// WithStatsAddress is the StatsOption that sets the stats server address. The
// address must be in the form of "host:port". It returns an error when empty.
func WithStatsAddress(s string) StatsOption {
	return func(sc *StatsConfig) error {
		if s == "" {
			return errors.New("stats address must be non-empty")
		}
		sc.addr = s
		return nil
	}
}

// WithStatsRate is the StatsOption that sets the stats client's reporting
// interval. It returns an error when non-positive.
func WithStatsRate(d time.Duration) StatsOption {
	return func(sc *StatsConfig) error {
		if d <= 0 {
			return errors.New("stats rate must be positive")
		}
		sc.rate = d
		return nil
	}
}

// WithStatsTags is the StatsOption that sets the base tags reported by the
// client. It returns an error when empty.
func WithStatsTags(t stats.Tags) StatsOption {
	return func(sc *StatsConfig) error {
		if t == nil {
			return errors.New("stats tags must be non-empty")
		}
		sc.tags = t
		return nil
	}
}

// WithStatsClient is the StatsOption that allows for providing a stats.Client
// to be used. It returns an error when nil.
func WithStatsClient(c stats.Client) StatsOption {
	return func(sc *StatsConfig) error {
		if c == nil {
			return errors.New("stats client must be non-nil")
		}
		sc.statsClient = c
		return nil
	}
}

// NewStatsConfig returns a new StatsConfig configured with any provided
// StatsOption.
//
// Stats reporting is disabled by default. Reporting can be enabled by using an
// internal stats.Client or providing an existing one.
//
// To use an internal stats.Client an address must be set using
// WithStatsAddress. The internal client can be configured with the other
// related StatsOptions.
//
// To use an already configured stats.Client use the WithStatsClient option.
// When using this style all other StatsOptions will be ignored.
func NewStatsConfig(opts ...StatsOption) (*StatsConfig, error) {
	sc := &StatsConfig{
		addr: defaultStatsAddr,
		rate: defaultStatsRate,
		tags: stats.Tags{},
	}

	for _, o := range opts {
		if err := o(sc); err != nil {
			return nil, fmt.Errorf("applying stats option: %w", err)
		}
	}
	return sc, nil
}

func (sc *StatsConfig) client(aqComponent string, tags stats.Tags) (stats.Client, error) {
	var err error
	var c stats.Client

	if sc.statsClient != nil {
		// Take existing stats client and create a new one with aqueduct prefix key: {aqueduct.client, aqueduct.worker}
		bc := sc.statsClient
		c, err = newPrefixedReporter(bc, aqComponent)
	} else {
		// Create our own stats client from the configuration
		c, err = sc.newStatsClient(aqComponent)
	}

	if err != nil {
		return nil, fmt.Errorf("creating stats reporter: %w", err)
	}

	return c.WithTags(tags), err
}

func (sc *StatsConfig) newStatsClient(prefixKey string) (stats.Client, error) {
	if sc.addr == "" {
		return stats.NullStatter, nil
	}

	return stats.NewClient(
		stats.UDPSink(sc.addr),
		sc.rate, prefixKey,
	).WithTags(sc.tags), nil
}

type prefixedReporter struct {
	stats  stats.Client
	prefix string
}

func newPrefixedReporter(stats stats.Client, prefixKey string) (*prefixedReporter, error) {
	statsClient := stats

	if stats == nil {
		return nil, errors.New("stats client must be non-nil")
	}

	if prefixKey == "" {
		return nil, errors.New("prefix must be non-nil")
	} else if !strings.HasSuffix(prefixKey, ".") {
		prefixKey += "."
	}

	return &prefixedReporter{
		stats:  statsClient,
		prefix: prefixKey,
	}, nil
}

func (pr *prefixedReporter) Start() {
	// pr.stats.Start() is deprecated
	pr.stats.Run()
}

func (pr *prefixedReporter) Run() {
	pr.stats.Run()
}

func (pr *prefixedReporter) Stop() {
	pr.stats.Stop()
}

func (pr *prefixedReporter) ClearTags() stats.Client {
	return pr.stats.ClearTags()
}

func (pr *prefixedReporter) SetPrefix(prefix string) stats.Client {
	// This is a hack until we use the new go.stats@1.15 interface properly
	pr.prefix = prefix
	return pr.stats
}

func (pr *prefixedReporter) Report(t stats.Type, key string, value float64, tags stats.Tags, rate float32) {
	pr.stats.Report(t, pr.prefix+key, value, tags, rate)
}

func (pr *prefixedReporter) Event(title, text string, tags stats.Tags) {
	pr.stats.Event(title, text, tags)
}

func (pr *prefixedReporter) Gauge(key string, tags stats.Tags, value int64) {
	pr.stats.Gauge(pr.prefix+key, tags, value)
}

func (pr *prefixedReporter) Counter(key string, tags stats.Tags, value int64) {
	pr.stats.Counter(pr.prefix+key, tags, value)
}

func (pr *prefixedReporter) Increment(key string, tags stats.Tags) {
	pr.stats.Increment(pr.prefix+key, tags)
}

func (pr *prefixedReporter) Histogram(key string, tags stats.Tags, value int64) {
	pr.stats.Histogram(pr.prefix+key, tags, value)
}

func (pr *prefixedReporter) Timing(key string, tags stats.Tags, value time.Duration) {
	pr.stats.Timing(pr.prefix+key, tags, value)
}

func (pr *prefixedReporter) Distribution(key string, tags stats.Tags, value float64) {
	pr.stats.Distribution(pr.prefix+key, tags, value)
}

func (pr *prefixedReporter) DistributionMs(key string, tags stats.Tags, value time.Duration) {
	pr.stats.DistributionMs(pr.prefix+key, tags, value)
}

func (pr *prefixedReporter) Set(key string, tags stats.Tags, value string) {
	pr.stats.Set(key, tags, value)
}

func (pr *prefixedReporter) WithTags(tags stats.Tags) stats.Client {
	return &prefixedReporter{
		stats:  pr.stats.WithTags(tags),
		prefix: pr.prefix,
	}
}
