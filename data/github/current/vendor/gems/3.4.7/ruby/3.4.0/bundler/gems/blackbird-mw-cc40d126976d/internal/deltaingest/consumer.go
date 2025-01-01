package deltaingest

import (
	"context"
	"errors"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/hydro-client-go/v7/pkg/hydro"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/mysqlerrors"
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
	store            db.Store
	corpus           routing.Corpus
	backfillConsumer hydro.Consumer
	incrConsumer     hydro.Consumer
	indexerCluster   *routing.IndexerCluster
	currentEpochID   types.EpochID
	state            *db.CorpusState
	last_fetched     time.Time
}

func NewIngestModeConsumer(
	ctx context.Context,
	store db.Store,
	corpus routing.Corpus,
	backfillConsumer hydro.Consumer,
	incrConsumer hydro.Consumer,
	indexerCluster *routing.IndexerCluster,
	currentEpochID types.EpochID,
) *IngestModeConsumer {
	return &IngestModeConsumer{
		store,
		corpus,
		backfillConsumer,
		incrConsumer,
		indexerCluster,
		currentEpochID,
		nil,
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
		if m.state == nil || time.Since(m.last_fetched) > time.Second {
			s, err := m.store.GetCorpusState(ctx, m.corpus)
			m.state = s
			m.last_fetched = time.Now()
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

		msg, err := m.readMessage(ctx, m.state)
		if err != nil {
			if errors.Is(err, context.DeadlineExceeded) {
				continue // Read timeout, try again
			}

			return msg, nil, err
		}

		// TODO: what if the corpus state changed? Do we need to reload it here before proceeding?
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
