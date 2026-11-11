package ingest

import (
	"context"
	"errors"
	"time"

	"github.com/cenkalti/backoff/v4"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/hydro-client-go/v7/pkg/hydro"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/mysqlerrors"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

var ErrEpochChanged = errors.New("epoch changed, must restart")

// IngestModeConsumer is a wrapper around two Kafka consumers: one for the
// backfill topic and one for all incremental topics. This allows switching from
// "backfill" to "incremental" mode.
//
// When in backfill mode, only the backfill topic is read. The incremental
// consumer group is active, but lag is allowed to build up (no messages are
// read, no offsets are marked). When in incremental mode, reads switch to the
// incremental topics. The mode is determined by reading the state for the
// current corpus as part of each read.
type IngestModeConsumer struct {
	store             db.Store
	corpus            routing.Corpus
	topicConfig       routing.TopicConfig
	backfillConsumer  hydro.Consumer
	incrConsumer      hydro.Consumer
	indexerCluster    *routing.IndexerCluster
	checkModeInterval time.Duration
	currentEpochID    types.EpochID
	state             *db.CorpusState
	lastStateFetch    time.Time
	ingestMode        db.IngestMode
	lastModeFetch     time.Time
}

func NewIngestModeConsumer(
	ctx context.Context,
	store db.Store,
	corpus routing.Corpus,
	topicConfig routing.TopicConfig,
	backfillConsumer hydro.Consumer,
	incrConsumer hydro.Consumer,
	indexerCluster *routing.IndexerCluster,
	currentEpochID types.EpochID,
	checkModeInterval time.Duration,
) *IngestModeConsumer {
	return &IngestModeConsumer{
		store,
		corpus,
		topicConfig,
		backfillConsumer,
		incrConsumer,
		indexerCluster,
		checkModeInterval,
		currentEpochID,
		nil,
		time.Now(),
		db.IngestModeUnknown,
		time.Now(),
	}
}

// Reads a message from one of the underlying Kafka consumers based on the
// ingest mode of the corpus. Blocks until a message is read or the context is
// cancelled. Returns the hydro message and the epochID or an error.
func (m *IngestModeConsumer) ReadMessage(ctx context.Context) (hydro.Message, *db.CorpusState, error) {
	for {
		if m.indexerCluster.IsIndexingPaused() {
			time.Sleep(1 * time.Second)
			continue // Corpus is not enabled for indexing, try again after a delay
		}
		if m.state == nil || time.Since(m.lastStateFetch) > time.Second {
			s, err := m.store.GetCorpusState(ctx, m.corpus)
			m.state = s
			m.lastStateFetch = time.Now()
			if err != nil {
				// ReadMessage is a very hot path, so Vitess shutdowns are commonly
				// hit. To avoid a pod restart, pause for a moment and then continue
				// the loop.
				//
				// See https://github.com/github/blackbird/issues/7175
				if errors.Is(err, mysqlerrors.ServerShutdownError()) {
					logging.Error(ctx, "MySQL server shut down while getting corpus state, continuing consume loop", kvp.Err(err))
					time.Sleep(100 * time.Millisecond)
					continue
				}

				return hydro.Message{}, nil, err
			}
		}

		// TODO: Get epoch ID from indexer. Remove db.CorpusState from this method.
		if m.state.EpochID != m.currentEpochID {
			logging.Info(
				ctx,
				"detected epoch change",
				kvp.Uint("current_epoch", uint(m.currentEpochID)),
				kvp.Uint("new_epoch", uint(m.state.EpochID)),
			)
			return hydro.Message{}, nil, ErrEpochChanged
		}

		if err := m.updateIngestMode(ctx); err != nil {
			return hydro.Message{}, nil, err
		}

		msg, err := m.readMessage(ctx, m.state)
		if err != nil {
			if errors.Is(err, context.DeadlineExceeded) {
				continue // Read timeout, try again
			}

			return msg, nil, err
		}

		return msg, m.state, nil
	}
}

func (m *IngestModeConsumer) MarkMessage(msg hydro.Message) error {
	if msg.Topic == m.corpus.EpochBackfillTopic(m.currentEpochID) {
		return m.backfillConsumer.MarkMessage(msg)
	}
	return m.incrConsumer.MarkMessage(msg)
}

// Reads from the appropriate consumer (based on the given mode) with a 1 second
// timeout to avoid permanently blocking in the case where the backfill topic
// has been drained and the system needs to transition to incremental mode
// (reading from the incremental topics). The caller is expected to try again if
// context.DeadlineExceeded is returned.
func (m *IngestModeConsumer) readMessage(ctx context.Context, state *db.CorpusState) (hydro.Message, error) {
	ctx, cancel := context.WithTimeout(ctx, 1*time.Second)
	defer cancel()

	if state.IngestMode == db.IngestModeBackfill {
		return m.backfillConsumer.ReadMessage(ctx)
	}

	return m.incrConsumer.ReadMessage(ctx)
}

func (m *IngestModeConsumer) updateIngestMode(ctx context.Context) error {
	// Check current ingest mode no more than once a minute until we reach incremental mode
	if m.ingestMode == db.IngestModeIncremental || (m.ingestMode != db.IngestModeUnknown && time.Since(m.lastModeFetch) < m.checkModeInterval) {
		m.state.IngestMode = m.ingestMode
		return nil
	}

	kafkaInfo, err := getSourceKafkaInfo(ctx, m.indexerCluster)
	if err != nil {
		return err
	}

	// NOTE: Must get blackbird.EpochMode (a bitfield) **not** the entities.EpochMode (an int).
	epochMode := epoch.EpochMode(m.indexerCluster.EpochInfo().EpochMode)
	ingestMode := IngestModeFromSourceKafkaInfo(kafkaInfo, m.corpus, m.currentEpochID, epochMode, m.topicConfig)
	if m.ingestMode != ingestMode {
		logging.Info(ctx, "transitioning ingest mode", kvp.String("from_ingest_mode", m.ingestMode.String()), kvp.String("to_ingest_mode", ingestMode.String()))
	}

	m.ingestMode = ingestMode
	m.state.IngestMode = m.ingestMode
	m.lastModeFetch = time.Now()
	return nil
}

func getSourceKafkaInfo(ctx context.Context, indexerCluster *routing.IndexerCluster) (map[string]*servingpb.KafkaInfo, error) {
	// especially on system startup in e2e tests, getting a host takes a while to succeed. Try a few times.
	var host *routing.IndexerHost
	var err error
	op := func() error {
		host, err = indexerCluster.GetHost()
		if err != nil {
			return err
		}
		return nil
	}
	err = backoff.Retry(op, retry.DefaultConstBackOff(ctx, 10))
	if err != nil {
		return nil, err
	}

	req := &servingpb.StatusRequest{IncludeSourceKafkaInfo: true}
	resp, err := host.IndexAPI.Status(ctx, req)
	if err != nil {
		return nil, err
	}

	if len(resp.Status.Shards) == 0 {
		return nil, errors.New("no shards found in status response")
	}

	return resp.Status.Shards[0].SourceKafkaInfo, nil
}
