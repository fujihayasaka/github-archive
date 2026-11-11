package core_test

import (
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/memory/core/coretest"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewMemory_InitializesVotingFields(t *testing.T) {
	source := core.MemorySource{
		Agent:     "copilot",
		NWO:       core.RepoNWO{Owner: "github", Repo: "github"},
		User:      core.User{ID: 123, Login: "testuser"},
		CommitSHA: "abc123",
	}

	m := core.NewMemory(core.NewMemoryID(), "subject", "fact", "reason", []string{"cite"}, source)

	assert.False(t, m.CreatedAt.IsZero())
	assert.False(t, m.UpdatedAt.IsZero())
	assert.False(t, m.ExpiresAt.IsZero())
	assert.Equal(t, m.CreatedAt, m.UpdatedAt)
	assert.Equal(t, m.CreatedAt.Add(core.VoteWindow), m.ExpiresAt)

	require.Len(t, m.Votes, 1)
	assert.Equal(t, core.UpVote, m.Votes[0].Direction)
	assert.Equal(t, "copilot", m.Votes[0].Source.Agent)
	assert.Equal(t, core.RepoNWO{Owner: "github", Repo: "github"}, m.Votes[0].Source.RepoNWO)
	assert.Equal(t, "abc123", m.Votes[0].Source.CommitSHA)
}

func TestAddVote_Upvote(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	coretest.FreezeNow(t, now.Add(24*time.Hour))
	m := &core.Memory{
		CreatedAt: now,
		UpdatedAt: now,
		ExpiresAt: now.Add(core.VoteWindow),
		Votes: []core.Vote{{
			Direction: core.UpVote,
			Timestamp: now,
		}},
	}

	voteTime := now.Add(24 * time.Hour)
	err := m.AddVote(core.Vote{Direction: core.UpVote, Timestamp: voteTime, Source: core.VoteSource{Agent: "agent2"}})
	require.NoError(t, err)

	assert.Len(t, m.Votes, 2)
	assert.Equal(t, voteTime, m.UpdatedAt)
	assert.Equal(t, voteTime.Add(core.VoteWindow), m.ExpiresAt)
}

func TestAddVote_Downvote_DoesNotResetExpiry(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	coretest.FreezeNow(t, now.Add(24*time.Hour))
	originalExpiry := now.Add(core.VoteWindow)
	m := &core.Memory{
		CreatedAt: now,
		UpdatedAt: now,
		ExpiresAt: originalExpiry,
		Votes: []core.Vote{{
			Direction: core.UpVote,
			Timestamp: now,
		}},
	}

	voteTime := now.Add(24 * time.Hour)
	err := m.AddVote(core.Vote{Direction: core.DownVote, Timestamp: voteTime, Source: core.VoteSource{Agent: "agent2"}})
	require.NoError(t, err)

	assert.Len(t, m.Votes, 2)
	assert.Equal(t, voteTime, m.UpdatedAt)
	assert.Equal(t, originalExpiry, m.ExpiresAt) // unchanged
}

func TestPruneVotes_RemovesOldVotes(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now.Add(-30 * 24 * time.Hour)},  // 30 days old, should be pruned
			{Direction: core.UpVote, Timestamp: now.Add(-27 * 24 * time.Hour)},  // 27 days old, should stay
			{Direction: core.DownVote, Timestamp: now.Add(-1 * 24 * time.Hour)}, // 1 day old, should stay
		},
	}

	m.PruneVotes(now)

	assert.Len(t, m.Votes, 2)
	assert.Equal(t, now.Add(-27*24*time.Hour), m.Votes[0].Timestamp)
	assert.Equal(t, now.Add(-1*24*time.Hour), m.Votes[1].Timestamp)
}

func TestPruneVotes_RemovesAllIfAllExpired(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now.Add(-30 * 24 * time.Hour)},
			{Direction: core.UpVote, Timestamp: now.Add(-29 * 24 * time.Hour)},
		},
	}

	m.PruneVotes(now)

	assert.Empty(t, m.Votes)
}

func TestPruneVotes_NilVotesDoesNotPanic(t *testing.T) {
	// Validates that PruneVotes handles nil Votes safely,
	// which can occur with legacy documents loaded from Cosmos.
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{Votes: nil}

	m.PruneVotes(now)

	assert.Empty(t, m.Votes)
}

func TestPruneVotes_CapsAtMaxVotes(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)

	// Create MaxVotes + 50 recent votes (all within the window)
	votes := make([]core.Vote, core.MaxVotes+50)
	for i := range votes {
		votes[i] = core.Vote{
			Direction: core.UpVote,
			Timestamp: now.Add(-time.Duration(len(votes)-1-i) * time.Minute), // oldest first
		}
	}
	m := &core.Memory{Votes: votes}

	m.PruneVotes(now)

	assert.Len(t, m.Votes, core.MaxVotes)
	// Should keep the most recent votes (the tail of the original slice)
	assert.Equal(t, votes[50].Timestamp, m.Votes[0].Timestamp)
	assert.Equal(t, votes[len(votes)-1].Timestamp, m.Votes[core.MaxVotes-1].Timestamp)
}

func TestAddVote_PrunesOnVote(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	coretest.FreezeNow(t, now)
	m := &core.Memory{
		CreatedAt: now.Add(-30 * 24 * time.Hour),
		UpdatedAt: now.Add(-30 * 24 * time.Hour),
		ExpiresAt: now,
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now.Add(-30 * 24 * time.Hour)}, // expired
			{Direction: core.UpVote, Timestamp: now.Add(-5 * 24 * time.Hour)},  // valid
		},
	}

	err := m.AddVote(core.Vote{Direction: core.UpVote, Timestamp: now, Source: core.VoteSource{Agent: "test"}})
	require.NoError(t, err)

	// Expired vote should be pruned, leaving 2: the 5-day old one + the new one
	assert.Len(t, m.Votes, 2)
	assert.Equal(t, now.Add(-5*24*time.Hour), m.Votes[0].Timestamp)
	assert.Equal(t, now, m.Votes[1].Timestamp)
}

func TestAddVote_PreservesVoteMetadata(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	coretest.FreezeNow(t, now)
	m := &core.Memory{
		CreatedAt: now,
		UpdatedAt: now,
		ExpiresAt: now.Add(core.VoteWindow),
		Votes:     []core.Vote{},
	}

	source := core.VoteSource{
		Agent:         "copilot",
		RepoNWO:       core.RepoNWO{Owner: "github", Repo: "github"},
		CommitSHA:     "deadbeef",
		InteractionID: "interaction-123",
	}
	err := m.AddVote(core.Vote{Direction: core.UpVote, Timestamp: now, Source: source})
	require.NoError(t, err)

	require.Len(t, m.Votes, 1)
	v := m.Votes[0]
	assert.Equal(t, core.UpVote, v.Direction)
	assert.Equal(t, now, v.Timestamp)
	assert.Equal(t, "copilot", v.Source.Agent)
	assert.Equal(t, core.RepoNWO{Owner: "github", Repo: "github"}, v.Source.RepoNWO)
	assert.Equal(t, "deadbeef", v.Source.CommitSHA)
	assert.Equal(t, "interaction-123", v.Source.InteractionID)
}

func TestAddVote_InvalidDirection(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{
		CreatedAt: now,
		UpdatedAt: now,
		ExpiresAt: now.Add(core.VoteWindow),
		Votes:     []core.Vote{},
	}

	err := m.AddVote(core.Vote{Direction: core.VoteValue(9), Timestamp: now, Source: core.VoteSource{Agent: "test"}})
	require.ErrorIs(t, err, core.ErrInvalidVoteDirection)
	assert.Empty(t, m.Votes)
}

func TestVoteValue_IsValid(t *testing.T) {
	assert.True(t, core.UpVote.IsValid())
	assert.True(t, core.DownVote.IsValid())
	assert.False(t, core.VoteValue(0).IsValid())
	assert.False(t, core.VoteValue(2).IsValid())
	assert.False(t, core.VoteValue(-2).IsValid())
}

// TestAddVote_BackdatedTimestampDoesNotRegressUpdatedAt pins the monotonicity
// invariant on Memory.UpdatedAt: a vote whose Timestamp is earlier than the
// memory's current UpdatedAt must not move UpdatedAt backwards. This protects
// against retried voting calls (executeVote re-uses the caller's *Vote across
// up to 3 attempts) and against client-supplied or clock-skewed timestamps.
func TestAddVote_BackdatedTimestampDoesNotRegressUpdatedAt(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	coretest.FreezeNow(t, now)
	m := &core.Memory{
		CreatedAt: now,
		UpdatedAt: now,
		ExpiresAt: now.Add(core.VoteWindow),
		Votes:     []core.Vote{{Direction: core.UpVote, Timestamp: now}},
	}

	backdated := core.Vote{Direction: core.DownVote, Timestamp: now.Add(-365 * 24 * time.Hour)}
	require.NoError(t, m.AddVote(backdated))

	assert.False(t, m.UpdatedAt.Before(now), "UpdatedAt regressed: was %v, now %v", now, m.UpdatedAt)
	require.Len(t, m.Votes, 2)
	// The persisted vote's timestamp was normalised to wall-clock now.
	assert.Equal(t, now, m.Votes[1].Timestamp)
}

// TestAddVote_BackdatedUpvoteDoesNotShortenExpiresAt pins the related invariant
// on ExpiresAt: an upvote with a backdated Timestamp must not shorten the
// memory's lifetime. Without normalisation, a stale retried upvote could move
// ExpiresAt earlier than its current value, causing a memory to expire sooner
// than intended.
func TestAddVote_BackdatedUpvoteDoesNotShortenExpiresAt(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	coretest.FreezeNow(t, now)
	originalExpiry := now.Add(core.VoteWindow)
	m := &core.Memory{
		CreatedAt: now,
		UpdatedAt: now,
		ExpiresAt: originalExpiry,
		Votes:     []core.Vote{{Direction: core.UpVote, Timestamp: now}},
	}

	stale := core.Vote{Direction: core.UpVote, Timestamp: now.Add(-24 * time.Hour)}
	require.NoError(t, m.AddVote(stale))

	assert.False(t, m.ExpiresAt.Before(originalExpiry),
		"upvote shortened ExpiresAt: was %v, now %v", originalExpiry, m.ExpiresAt)
}

// TestAddVote_FutureTimestampClampedToNow pins the invariant that a vote
// timestamp ahead of wall-clock now (clock skew, untrusted input) is rejected
// in favour of wall-clock now, so that a single bad caller cannot poison
// future ExpiresAt or pruning windows.
func TestAddVote_FutureTimestampClampedToNow(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	coretest.FreezeNow(t, now)
	m := &core.Memory{
		CreatedAt: now,
		UpdatedAt: now,
		ExpiresAt: now.Add(core.VoteWindow),
		Votes:     []core.Vote{{Direction: core.UpVote, Timestamp: now}},
	}

	future := core.Vote{Direction: core.UpVote, Timestamp: now.Add(48 * time.Hour)}
	require.NoError(t, m.AddVote(future))

	require.Len(t, m.Votes, 2)
	assert.Equal(t, now, m.Votes[1].Timestamp)
	assert.Equal(t, now, m.UpdatedAt)
	assert.Equal(t, now.Add(core.VoteWindow), m.ExpiresAt)
}

func TestAddVote_DoesNotRegressPoisonedFutureUpdatedAt(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	coretest.FreezeNow(t, now)
	futureUpdatedAt := now.Add(48 * time.Hour)
	m := &core.Memory{
		CreatedAt: now.Add(-24 * time.Hour),
		UpdatedAt: futureUpdatedAt,
		ExpiresAt: futureUpdatedAt.Add(core.VoteWindow),
		Votes:     []core.Vote{{Direction: core.UpVote, Timestamp: futureUpdatedAt}},
	}

	require.NoError(t, m.AddVote(core.Vote{Direction: core.UpVote, Timestamp: now}))

	require.Len(t, m.Votes, 2)
	assert.Equal(t, futureUpdatedAt, m.Votes[1].Timestamp)
	assert.Equal(t, futureUpdatedAt, m.UpdatedAt)
	assert.Equal(t, futureUpdatedAt.Add(core.VoteWindow), m.ExpiresAt)
}

// TestAddVote_PrunesAgainstWallClockNotVoteTimestamp pins the invariant that
// PruneVotes is anchored to wall-clock now rather than the supplied vote's
// timestamp. A legitimately-old caller-supplied timestamp (which the
// monotonicity check will normalise) must not retroactively shrink the
// retention window and evict newer votes.
func TestAddVote_PrunesAgainstWallClockNotVoteTimestamp(t *testing.T) {
	wallNow := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	coretest.FreezeNow(t, wallNow)
	m := &core.Memory{
		CreatedAt: wallNow.Add(-10 * 24 * time.Hour),
		UpdatedAt: wallNow.Add(-1 * time.Hour),
		ExpiresAt: wallNow.Add(core.VoteWindow),
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: wallNow.Add(-10 * 24 * time.Hour)}, // 10d old
			{Direction: core.UpVote, Timestamp: wallNow.Add(-5 * 24 * time.Hour)},  // 5d old
			{Direction: core.UpVote, Timestamp: wallNow.Add(-1 * time.Hour)},       // 1h old
		},
	}

	// Backdated vote — Timestamp is years old. Without the wall-clock pruning
	// invariant this would cause every other vote to be considered "future" and
	// evicted (or, depending on signedness, kept incorrectly). With it, the
	// 10d/5d/1h votes are all retained because each is well within VoteWindow
	// of wall-clock now.
	backdated := core.Vote{Direction: core.UpVote, Timestamp: wallNow.Add(-1000 * 24 * time.Hour)}
	require.NoError(t, m.AddVote(backdated))

	assert.Len(t, m.Votes, 4, "all in-window votes plus the new (normalised) vote should be retained")
}
