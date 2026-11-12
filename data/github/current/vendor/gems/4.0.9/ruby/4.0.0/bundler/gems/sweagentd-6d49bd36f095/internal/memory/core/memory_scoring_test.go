package core_test

import (
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestScore_FreshUpvote(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now},
		},
	}
	// A brand-new upvote has weight 1.0, so score = 1.0
	assert.InDelta(t, 1.0, m.Score(now), 0.001)
}

func TestScore_HalfDecayedUpvote(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now.Add(-14 * 24 * time.Hour)},
		},
	}
	// 14-day-old upvote: weight = (28-14)/28 = 0.5, score = 0.5
	assert.InDelta(t, 0.5, m.Score(now), 0.001)
}

func TestScore_FullyDecayedVote(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now.Add(-28 * 24 * time.Hour)},
		},
	}
	// 28-day-old vote: weight = 0, score = 0
	assert.InDelta(t, 0.0, m.Score(now), 0.001)
}

func TestScore_Downvote(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{
		Votes: []core.Vote{
			{Direction: core.DownVote, Timestamp: now},
		},
	}
	// Fresh downvote: weight = 1.0, score = -1.0
	assert.InDelta(t, -1.0, m.Score(now), 0.001)
}

func TestScore_MixedVotes(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now},                            // weight 1.0, contribution +1.0
			{Direction: core.DownVote, Timestamp: now.Add(-7 * 24 * time.Hour)}, // weight 0.75, contribution -0.75
			{Direction: core.UpVote, Timestamp: now.Add(-21 * 24 * time.Hour)},  // weight 0.25, contribution +0.25
		},
	}
	// Expected score: 1.0 - 0.75 + 0.25 = 0.5
	assert.InDelta(t, 0.5, m.Score(now), 0.001)
}

func TestScore_NoVotes(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{Votes: []core.Vote{}}
	assert.InDelta(t, 0.0, m.Score(now), 0.001)
}

func TestScore_FutureVoteClamped(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now.Add(7 * 24 * time.Hour)}, // 7 days in the future
		},
	}
	// Future vote should be clamped to weight 1.0, not exceed it
	assert.InDelta(t, 1.0, m.Score(now), 0.001)
}

func TestSortByScore(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)

	zero := &core.Memory{
		ID:        "zero",
		CreatedAt: now,
		Votes:     []core.Vote{},
	}
	high := &core.Memory{
		ID:        "high",
		CreatedAt: now,
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now},
			{Direction: core.UpVote, Timestamp: now},
		},
	}

	memories := []*core.Memory{zero, high}
	result := core.SortByScore(memories, now)

	require.Len(t, result, 2)
	assert.Equal(t, core.MemoryID("high"), result[0].ID)
	assert.Equal(t, core.MemoryID("zero"), result[1].ID)
}

func TestSortByScore_TiebreakByCreatedAt(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)

	older := &core.Memory{
		ID:        "older",
		CreatedAt: now.Add(-24 * time.Hour),
		Votes:     []core.Vote{{Direction: core.UpVote, Timestamp: now}},
	}
	newer := &core.Memory{
		ID:        "newer",
		CreatedAt: now,
		Votes:     []core.Vote{{Direction: core.UpVote, Timestamp: now}},
	}

	memories := []*core.Memory{older, newer}
	result := core.SortByScore(memories, now)

	// Same score → newest first
	assert.Equal(t, core.MemoryID("newer"), result[0].ID)
	assert.Equal(t, core.MemoryID("older"), result[1].ID)
}

func TestSortByScore_FiltersNegativeScores(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)

	negative := &core.Memory{
		ID:        "negative",
		CreatedAt: now,
		Votes: []core.Vote{
			{Direction: core.DownVote, Timestamp: now},
		},
	}
	positive := &core.Memory{
		ID:        "positive",
		CreatedAt: now,
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now},
		},
	}
	zero := &core.Memory{
		ID:        "zero",
		CreatedAt: now,
		Votes:     []core.Vote{},
	}

	memories := []*core.Memory{negative, positive, zero}
	result := core.SortByScore(memories, now)

	require.Len(t, result, 2)
	assert.Equal(t, core.MemoryID("positive"), result[0].ID)
	assert.Equal(t, core.MemoryID("zero"), result[1].ID)
}

// TestScore_BoundedByVoteCount pins the invariant |Score(now)| <= len(Votes).
// Each vote contributes at most 1.0 in absolute weight (the future-clamp at
// memory.go bounds the weight to 1.0; the if weight > 0 check bounds it from
// below at 0.0). The sum therefore cannot exceed len(Votes) in magnitude.
func TestScore_BoundedByVoteCount(t *testing.T) {
	now := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)

	cases := []struct {
		name  string
		votes []core.Vote
	}{
		{name: "all fresh upvotes", votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now},
			{Direction: core.UpVote, Timestamp: now},
			{Direction: core.UpVote, Timestamp: now},
		}},
		{name: "mixed", votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now.Add(-1 * 24 * time.Hour)},
			{Direction: core.DownVote, Timestamp: now.Add(-7 * 24 * time.Hour)},
			{Direction: core.UpVote, Timestamp: now.Add(-20 * 24 * time.Hour)},
		}},
		{name: "all fully decayed", votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now.Add(-100 * 24 * time.Hour)},
			{Direction: core.DownVote, Timestamp: now.Add(-100 * 24 * time.Hour)},
		}},
		{name: "future timestamps clamped", votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now.Add(48 * time.Hour)},
			{Direction: core.UpVote, Timestamp: now.Add(48 * time.Hour)},
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := &core.Memory{Votes: tc.votes}
			score := m.Score(now)
			assert.LessOrEqual(t, score, float64(len(tc.votes)))
			assert.GreaterOrEqual(t, score, -float64(len(tc.votes)))
		})
	}
}

// TestScore_MonotonicDecayOverTime pins the invariant that for any single
// non-expired vote, advancing `now` strictly decreases the magnitude of its
// contribution to the score (until the vote ages out entirely). This is the
// behavioural anchor that justifies SortByScore returning newer-leaning
// rankings as votes age.
func TestScore_MonotonicDecayOverTime(t *testing.T) {
	t0 := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	m := &core.Memory{Votes: []core.Vote{{Direction: core.UpVote, Timestamp: t0}}}

	prev := m.Score(t0)
	for d := 1; d <= 27; d++ {
		now := t0.Add(time.Duration(d) * 24 * time.Hour)
		score := m.Score(now)
		assert.Less(t, score, prev, "score should strictly decrease at day %d", d)
		prev = score
	}
}
