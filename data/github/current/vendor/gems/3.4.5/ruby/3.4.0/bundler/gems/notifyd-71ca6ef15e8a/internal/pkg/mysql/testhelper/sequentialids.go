package testhelper

import (
	"strconv"
	"sync"
	"sync/atomic"
)

/*
SequentialIDs system: Generate new sequential IDs on demand and keep references to IDs created

The idea of this struct is to have a centralized place to generate IDs and keep references to them if necessary.
The IDs will be "global" to the instance, not all of the test suites. As long as the instance of SequentialIDs
is unique per test suite it should be enough to ensure each test in that test suite generates unique sequential IDs.

See testhelper.DatabaseSuite for a suite implementation that generates a SequentialIDs instance per test suite.
*/
type SequentialIDs struct {
	mut  sync.Mutex
	gids map[string]int64
	gid  int64
}

// NewSequentialIDs creates a new SequentialIDs instance.
func NewSequentialIDs() *SequentialIDs {
	return &SequentialIDs{
		gid:  0,
		gids: make(map[string]int64),
	}
}

/*
Get generates a new sequential Get as int64

Example:

	seqIDs := testhelper.NewSequentialIDs()
	first := seqIDs.Get()
	second := seqIDs.Get()

This is threadsafe
*/
func (t *SequentialIDs) Get() int64 {
	return atomic.AddInt64(&t.gid, 1)
}

/*
GetRef generates a new sequential ID as int64 with a reference (a name).

If the name was used already, reuse the ID.
This is essentially like saving an ID in a variable, but in some scenarios (like when defining data for tests) defining
variables to hold IDs gets messy, hence the reference tracking inside the SequentialIDs system. It will hold the variables for us.

Example:

	seqIDs := testhelper.NewSequentialIDs()
	first := seqIDs.GetRef("one")
	second := seqIDs.GetRef("two")
	firstAgain := seqIDs.GetRef("one") // same as first

This is threadsafe
*/
func (t *SequentialIDs) GetRef(ref string) int64 {
	t.mut.Lock()
	defer t.mut.Unlock()

	if id, ok := t.gids[ref]; ok {
		return id
	}

	id := t.Get()
	t.gids[ref] = id

	return id
}

// GetString generates an ID as an string
func (t *SequentialIDs) GetString() string {
	return strconv.FormatInt(t.Get(), 10)
}

// GetRefString generates an ID with a reference as an string
func (t *SequentialIDs) GetRefString(ref string) string {
	return strconv.FormatInt(t.GetRef(ref), 10)
}

// GetInt32 generates an ID as an int32
func (t *SequentialIDs) GetInt32() int32 {
	//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
	return int32(t.Get())
}

// GetRefInt32 generates an ID with a reference as an int32
func (t *SequentialIDs) GetRefInt32(ref string) int32 {
	//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
	return int32(t.GetRef(ref))
}
