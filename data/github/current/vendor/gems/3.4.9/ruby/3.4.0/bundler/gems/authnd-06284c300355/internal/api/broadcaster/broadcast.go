package broadcaster

import (
	"context"
	"sync"
	"time"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/google/uuid"
	"github.com/pkg/errors"
)

// the amount of time the station will stay open after the initial broadcast to allow listeners to receive the result
const transmitTimeout = 10 * time.Millisecond

// ErrNoResult is returned when a broadcast ends with no result.
var ErrNoResult = errors.New("broadcast ended with no result")

// ErrCancelled is returned when the context of broadcaster is cancelled.
var ErrCancelled = errors.New("broadcast cancelled")

type listener struct {
	session   Session
	resultsCh chan Result
}

type station struct {
	joinable  bool
	listeners []listener
}

// Broadcaster is a mechanism for broadcasting a result to multiple listeners on identifiable station.
// The first client session to attempt TryBroadcast will become the broadcaster and any subsequent,
// concurrent client sessions will join as listeners.  Listeners will all receive the result provided
// by the broadcaster.
//
// Broadcaster is safe for concurrent access and is designed to coordinate the "request collapsing" pattern
// for identical, concurrent API requests.
//
// Important semantics for broadcaster use:
//   - Broadcasters MUST write to the channel returned by TryBroadcast to avoid blocking listeners (up to 10ms).
//   - Broadcasters MUST set reasonable timeouts in their context to avoid blocking listeners (up to 10ms).
//   - Listeners who call TryBroadcast MUST subsequently call TryListen and read from the returned channel. Otherwise,
//     future broadcasts are temporarily blocked for the given station (10ms).
type Broadcaster struct {
	mu       sync.RWMutex
	stations map[string]*station
}

// Result a result to be broadcast to listeners.
type Result struct {
	// the session ID of the broadcaster. enables listeners to identify the broadcaster
	// for the purposes of correlating logs in Splunk.
	BroadcasterID string
	Err           error
	Data          interface{}
}

// NewBroadcaster constructs a new Broadcaster instance.
func NewBroadcaster() *Broadcaster {
	return &Broadcaster{
		stations: make(map[string]*station),
	}
}

// Session describe a single client session with a unique ID and
// a key to identify the broadcast station it is listening on.
type Session struct {
	id  string
	key string
}

// String returns the session ID.
func (s Session) String() string {
	return s.id
}

// NewSession construct a new Session for the given key with a unique ID with the given prefix.
// The key is required but the idPrefix is optional.
func (b *Broadcaster) NewSession(key, idPrefix string) Session {
	if key == "" {
		panic("key cannot be empty")
	}
	id := uuid.New().String()
	if idPrefix != "" {
		id = idPrefix + "-" + id
	}

	return Session{
		id:  id,
		key: key,
	}
}

// TryBroadcast attempts to join the broadcast station as the broadcaster.
//
// If this is the first session in memory which attempts to broadcast, 'ok' return true. This session then becomes
// the broadcaster and is responsible for transmitting the result over the provided 'resultChan'. The 'resultChan' does
// not need to be closed by the caller.
//
// If another session is already broadcasting on this station the 'ok' return value will be false. The caller is automatically
// registered as a listener as long as the broadcast is joinable. Either way, the caller MUST subsequently call TryListen and
// wait for results if indicated. Otherwise, future broadcasts are temporarily blocked for the given station (10ms).
func (b *Broadcaster) TryBroadcast(ctx context.Context, session Session) (resultChan chan<- Result, ok bool) {
	b.mu.Lock()
	st, ok := b.stations[session.key]
	if ok {
		defer b.mu.Unlock()

		if !st.joinable {
			return nil, false
		}

		// joinable broadcast in progress. register session as listener.
		st.listeners = append(st.listeners, listener{
			session:   session,
			resultsCh: make(chan Result),
		})
		b.stations[session.key] = st

		return nil, false
	}

	// initialize the channel for listeners to join
	b.stations[session.key] = &station{
		joinable:  true,
		listeners: make([]listener, 0),
	}
	b.mu.Unlock()

	// initialize the channel for the first request to signal a result on. this channel needs
	// to be buffered to ensure the broadcaster doesn't block on send if transmit stops trying
	// to read (i.e. context cancellation).
	ch := make(chan Result, 1)

	// spin up goroutine for broadcast session to transmit result to all listeners
	go b.transmit(ctx, session, ch)

	return ch, true
}

// TryListen returns a channel to listen for the result of the broadcast. If the caller has not previously
// called TryBroadcast, 'ok' will be false. Otherwise, 'ok' will be true and the returned channel will
// receive the result of the broadcast.
//
// Listeners MUST read from the returned channel to prevent subsequent broadcasts from starting on the
// same station.
func (b *Broadcaster) TryListen(ctx context.Context, session Session) (result <-chan Result, ok bool) {
	logger := diagnostics.Logger(ctx)

	b.mu.RLock()
	defer b.mu.RUnlock()

	st, ok := b.stations[session.key]
	if !ok {
		// either broadcast session has ended (which should not be possible) or this session never called TryBroadcast.
		// either way, no result to listen for.
		logger.Info("no broadcast in progress for station", kvp.String("station", session.key))
		return nil, false
	}

	for _, listener := range st.listeners {
		if listener.session == session {
			return listener.resultsCh, true
		}
	}
	// unable to find listener for this session. this happens when there's an established broadcast which is no longer joinable.
	return nil, false
}

// transmits the result to all listeners and cleans up the broadcast session. should be called
// in a separate goroutine as it blocks for the result to be ready.
func (b *Broadcaster) transmit(ctx context.Context, broadcastSession Session, broadcastResult <-chan Result) {
	statter := diagnostics.Statter(ctx)

	var result Result
	var ok bool
	select {
	case result, ok = <-broadcastResult:
		// get result from broadcaster
		if !ok {
			// broadcast channel was closed before a result was transmitted.  something very bad happened here.
			result = Result{Err: ErrNoResult}
		}
		result.BroadcasterID = broadcastSession.id

	case <-ctx.Done():
		// broadcaster's context was cancelled before a result was transmitted. we need to handle this case explicitly
		// in case the broadcaster's goroutine exits unexpectedly (e.g. panics).
		result = Result{Err: ErrCancelled}
	}

	// grab the list of listeners and mark the station as no longer joinable
	b.mu.Lock()
	st := b.stations[broadcastSession.key]
	st.joinable = false
	b.mu.Unlock()

	statter.Histogram("broadcaster.listeners", nil, int64(len(st.listeners)))

	// transmit result to all listeners. will not exit until all listeners have received the result (or timeout).
	var wg sync.WaitGroup
	done := make(chan bool)
	for _, l := range st.listeners {
		wg.Add(1)
		go func(ch chan<- Result) {
			defer wg.Done()
			ch <- result
		}(l.resultsCh)
	}

	// need to signal wg is done by closing the done channel so we can add a timeout
	go func() {
		wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		// all listeners have received the result
		statter.Counter("broadcaster.transmit_complete", stats.Tags{"result": "success"}, 1)

	case <-time.After(transmitTimeout):
		// some client(s) didn't read the result in the allotted time. we need to clean up this broadcast to
		// 1. avoid leaking goroutines
		// 2. allow future broadcasts to this station
		statter.Counter("broadcaster.transmit_complete", stats.Tags{"result": "timeout"}, 1)
	}

	// terminate the station's broadcast session
	b.mu.Lock()
	defer b.mu.Unlock()
	delete(b.stations, broadcastSession.key)
}
