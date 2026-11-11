// Package core provides types and functions for managing memory identifiers.
package core

import (
	"cmp"
	"context"
	"errors"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
)

// MemoryID represents a unique identifier for a memory resource.
type MemoryID string

// nowFunc returns the current wall-clock time used by Memory operations such
// as AddVote and PruneVotes. It is a package-level variable so tests can
// freeze time via the coretest subpackage. Production code must not mutate it.
var nowFunc = func() time.Time { return time.Now().UTC() }

// SetNowFunc overrides the wall-clock used by Memory operations. It returns a
// restore function that reverts to the previous clock. This is exported only
// so the coretest helper subpackage can drive deterministic time in tests;
// production code must not call it.
func SetNowFunc(fn func() time.Time) (restore func()) {
	prev := nowFunc
	nowFunc = fn
	return func() { nowFunc = prev }
}

// NewMemoryID generates a new MemoryID.
func NewMemoryID() MemoryID {
	return MemoryID(uuid.NewString())
}

// String returns the string representation of the MemoryID.
func (id MemoryID) String() string {
	return string(id)
}

// RepoNWO represents a repository identifier in the format of "owner/repo".
type RepoNWO struct {
	Owner string
	Repo  string
}

// NewRepoNWO creates a new RepoNWO instance from owner and repo strings.
func NewRepoNWO(owner, repo string) (*RepoNWO, error) {
	if owner == "" {
		return nil, ErrEmptyRepoOwner
	}
	if repo == "" {
		return nil, ErrEmptyRepoName
	}
	return &RepoNWO{
		Owner: owner,
		Repo:  repo,
	}, nil
}

// NewRepoNWOFromString parses a string in the format "owner/repo" into a RepoNWO struct.
func NewRepoNWOFromString(nwo string) (*RepoNWO, error) {
	if nwo == "" {
		return nil, ErrEmptyRepoNWO
	}
	parts := strings.SplitN(nwo, "/", 2)
	if len(parts) != 2 {
		return nil, ErrInvalidRepoNWO
	}
	return NewRepoNWO(parts[0], parts[1])
}

// String returns the string representation of the RepoNWO.
func (r RepoNWO) String() string {
	return r.Owner + "/" + r.Repo
}

// User represents a user in the context of a memory operation.
type User struct {
	ID    uint64 `json:"id"`
	Login string `json:"login"`
}

// NewUser creates a new User instance.
func NewUser(id uint64, login string) User {
	return User{
		ID:    id,
		Login: login,
	}
}

// MemorySource represents the source of a memory, including the interaction ID,
// repository NWO, user, and agent that created it.
type MemorySource struct {
	InteractionID string  `json:"interactionId"`
	NWO           RepoNWO `json:"nwo"`
	User          User    `json:"user"`
	Agent         string  `json:"agent"`
	CommitSHA     string  `json:"commitSha,omitempty"`
	BaseModel     string  `json:"baseModel,omitempty"`
}

// VoteValue represents the direction of a vote.
type VoteValue int8

const (
	// UpVote represents an upvote (+1).
	UpVote VoteValue = 1
	// DownVote represents a downvote (-1).
	DownVote VoteValue = -1
)

// IsValid reports whether v is a recognised vote direction.
func (v VoteValue) IsValid() bool {
	return v == UpVote || v == DownVote
}

// String returns the human-readable name of the vote direction.
func (v VoteValue) String() string {
	switch v {
	case UpVote:
		return "upvote"
	case DownVote:
		return "downvote"
	default:
		return "unknown"
	}
}

// ErrInvalidVoteDirection indicates the vote direction is not UpVote or DownVote.

// VoteWindowDays is the number of days over which votes are retained.
const VoteWindowDays = 28

// VoteWindow is the duration over which votes are retained and decay is applied.
const VoteWindow = VoteWindowDays * 24 * time.Hour

// MaxVotes is the maximum number of votes retained per memory.
// When exceeded, the oldest votes are pruned to stay within this limit.
const MaxVotes = 500

// VoteSource contains metadata about what triggered a vote.
type VoteSource struct {
	Agent         string  `json:"agent,omitempty"`
	RepoNWO       RepoNWO `json:"nwo"`
	CommitSHA     string  `json:"commitSha,omitempty"`
	InteractionID string  `json:"interactionId,omitempty"`
	UserID        uint64  `json:"userId,omitempty"`
	UserLogin     string  `json:"userLogin,omitempty"`
	BaseModel     string  `json:"baseModel,omitempty"`
	Reason        string  `json:"reason,omitempty"`
}

// Vote represents a single upvote or downvote event with its metadata.
type Vote struct {
	Direction VoteValue  `json:"direction"`
	Timestamp time.Time  `json:"timestamp"`
	Source    VoteSource `json:"source"`
}

// MemoryScope represents whether a memory is scoped to a user or a repository.
type MemoryScope string

const (
	// MemoryScopeRepository indicates the memory is scoped to a repository.
	MemoryScopeRepository MemoryScope = "repository"
	// MemoryScopeUser indicates the memory is scoped to a user.
	MemoryScopeUser MemoryScope = "user"
)

// Memory represents a stored memory entry with its associated metadata.
type Memory struct {
	ID        MemoryID     `json:"id"`
	Subject   string       `json:"subject"`
	Fact      string       `json:"fact"`
	Citations []string     `json:"citations"`
	Reason    string       `json:"reason"`
	Source    MemorySource `json:"source"`
	Scope     MemoryScope  `json:"scope"`
	CreatedAt time.Time    `json:"createdAt"`
	UpdatedAt time.Time    `json:"updatedAt"`
	ExpiresAt time.Time    `json:"expiresAt"`
	Votes     []Vote       `json:"votes"`
	// BillingOrganizationID is the ID of the organization providing the Copilot license.
	// Set once at creation time; zero means not applicable (e.g. CfI or direct business seat).
	BillingOrganizationID uint64 `json:"billingOrganizationId"`
	// BillingEnterpriseID is the ID of the enterprise providing the Copilot license.
	// Set once at creation time; zero means not applicable (e.g. CfI or standalone org).
	BillingEnterpriseID uint64 `json:"billingEnterpriseId"`
	// ETag is used for optimistic concurrency control in the backing store.
	// It is populated by the store on read and checked on write.
	ETag string `json:"-"`
}

// NewMemory creates a new Memory instance with the given parameters.
// The initial creation counts as one upvote.
func NewMemory(id MemoryID, subject, fact, reason string, citations []string, source MemorySource) *Memory {
	now := time.Now().UTC()
	return &Memory{
		ID:        id,
		Subject:   subject,
		Fact:      fact,
		Citations: citations,
		Reason:    reason,
		Source:    source,
		CreatedAt: now,
		UpdatedAt: now,
		ExpiresAt: now.Add(VoteWindow),
		Votes: []Vote{{
			Direction: UpVote,
			Timestamp: now,
			Source: VoteSource{
				Agent:     source.Agent,
				RepoNWO:   source.NWO,
				CommitSHA: source.CommitSHA,
				BaseModel: source.BaseModel,
				UserID:    source.User.ID,
				UserLogin: source.User.Login,
				Reason:    reason,
			},
		}},
	}
}

// AddVote appends a vote and prunes old votes.
// If the vote is an upvote, ExpiresAt is reset to 28 days from now.
//
// Invariants enforced here:
//   - vote.Timestamp is normalised to max(now, m.UpdatedAt) if it is zero, in
//     the future (clock skew, attacker-controlled input), or before m.UpdatedAt.
//     This guarantees UpdatedAt is monotonically non-decreasing across the
//     lifetime of a Memory, including already-poisoned rows whose UpdatedAt is
//     ahead of wall-clock now, and prevents an upvote from accidentally
//     shortening ExpiresAt.
//   - PruneVotes is anchored to wall-clock "now" rather than vote.Timestamp,
//     so a backdated or replayed vote cannot retroactively shrink the
//     retention window and evict legitimate recent votes.
func (m *Memory) AddVote(vote Vote) error {
	if !vote.Direction.IsValid() {
		return ErrInvalidVoteDirection
	}
	now := nowFunc()
	if vote.Timestamp.IsZero() || vote.Timestamp.After(now) || vote.Timestamp.Before(m.UpdatedAt) {
		vote.Timestamp = now
		if vote.Timestamp.Before(m.UpdatedAt) {
			vote.Timestamp = m.UpdatedAt
		}
	}
	m.Votes = append(m.Votes, vote)
	m.UpdatedAt = vote.Timestamp
	if vote.Direction == UpVote {
		m.ExpiresAt = vote.Timestamp.Add(VoteWindow)
	}
	m.PruneVotes(now)
	return nil
}

// PruneVotes removes vote entries older than 28 days from the in-memory slice
// and caps the total number of votes at MaxVotes, keeping the most recent.
// This is an in-place filter that reuses the backing array of m.Votes to avoid
// allocation. Callers must not hold separate references to the old slice.
// Changes are persisted to Cosmos when the memory is subsequently saved via
// the store.
func (m *Memory) PruneVotes(now time.Time) {
	pruned := m.Votes[:0]
	for _, v := range m.Votes {
		if now.Sub(v.Timestamp) <= VoteWindow {
			pruned = append(pruned, v)
		}
	}
	if len(pruned) > MaxVotes {
		pruned = pruned[len(pruned)-MaxVotes:]
	}
	m.Votes = pruned
}

// Score calculates a weighted sum of the memory's votes. Each vote contributes
// its direction (+1 or -1) multiplied by a weight that decays linearly from 1
// to 0 over VoteWindowDays (28 days). Votes older than 28 days have zero weight.
//
// Invariants:
//   - |Score(now)| <= len(m.Votes), because each vote's weight is clamped to
//     [0, 1] (the min(weight, 1.0) guards future timestamps from clock skew;
//     the if weight > 0 filter discards expired votes).
//   - For any single non-expired vote, the magnitude of its contribution is
//     monotonically non-increasing in `now`.
func (m *Memory) Score(now time.Time) float64 {
	var score float64
	for _, v := range m.Votes {
		ageDays := now.Sub(v.Timestamp).Hours() / 24
		weight := (float64(VoteWindowDays) - ageDays) / float64(VoteWindowDays)
		weight = min(weight, 1.0) // clamp: future timestamps (clock skew) cannot exceed weight 1
		if weight > 0 {
			score += float64(v.Direction) * weight
		}
	}
	return score
}

// SortByScore sorts memories by their vote-based score in descending order
// and removes any memories with a negative score. Memories with equal scores
// are sorted by CreatedAt descending (newest first).
// Scores are precomputed to avoid redundant recalculation during sorting.
func SortByScore(memories []*Memory, now time.Time) []*Memory {
	scores := make(map[MemoryID]float64, len(memories))
	for _, m := range memories {
		scores[m.ID] = m.Score(now)
	}
	slices.SortStableFunc(memories, func(a, b *Memory) int {
		if c := cmp.Compare(scores[b.ID], scores[a.ID]); c != 0 {
			return c
		}
		// Tiebreaker: newest first
		return b.CreatedAt.Compare(a.CreatedAt)
	})
	// Filter out memories with negative scores.
	filtered := memories[:0]
	for _, m := range memories {
		if scores[m.ID] >= 0 {
			filtered = append(filtered, m)
		}
	}
	return filtered
}

// BatchDeleteResult holds the outcome of a batch delete operation, reporting
// which IDs were successfully deleted and which failed.
type BatchDeleteResult struct {
	Deleted []MemoryID
	Failed  []MemoryID
}

// BillingEntityMemoryFilter represents a billing scope filter for user-scoped memory queries.
// At least one of OrganizationID or EnterpriseID must be set. UserID is required
// so export queries stay within a single user partition. When both billing scope
// fields are set, both must match.
type BillingEntityMemoryFilter struct {
	OrganizationID uint64
	EnterpriseID   uint64
	UserID         uint64
}

// IsZero returns true when no billing scope was supplied.
func (f BillingEntityMemoryFilter) IsZero() bool {
	return f.OrganizationID == 0 && f.EnterpriseID == 0
}

// MemoryPageRequest describes a bounded page request for memory reads.
type MemoryPageRequest struct {
	Limit             uint
	ContinuationToken string
	SnapshotTime      time.Time
}

// MemoryPage contains one bounded page of memories and the token for the next page.
type MemoryPage struct {
	Memories          []*Memory
	ContinuationToken string
}

// BillingEntityDeleteResult holds the outcome of a billing-entity-scoped
// bulk delete operation.
type BillingEntityDeleteResult struct {
	DeletedCount      uint
	ContinuationToken string
}

// MemoryStore defines the interface for memory storage operations.
// Methods are provided per scope type (repository, user).
// TODO: We can refactor to reduce the number of methods by enabling scope-agnostic DELETE methods, but this requires partitioning by memory ID.
type MemoryStore interface { //nolint:interfacebloat // Explicit per-scope methods are intentional
	SaveForRepository(ctx context.Context, repoID RepositoryID, memory *Memory) error
	SaveBatchForRepository(ctx context.Context, repoID RepositoryID, memories []*Memory) error
	FindByRepository(ctx context.Context, repoID RepositoryID) ([]*Memory, error)
	FindByFactForRepository(ctx context.Context, repoID RepositoryID, fact string) ([]*Memory, error)
	FindRecentByRepository(ctx context.Context, repoID RepositoryID, limit uint) ([]*Memory, error)
	DeleteForRepository(ctx context.Context, repoID RepositoryID, id MemoryID) error
	DeleteBatchForRepository(ctx context.Context, repoID RepositoryID, ids []MemoryID) (*BatchDeleteResult, error)
	DeleteAllForRepository(ctx context.Context, repoID RepositoryID) error
	CountByRepository(ctx context.Context, repoID RepositoryID) (int, error)
	CountByUser(ctx context.Context, userID uint64, billingFilter *BillingEntity) (int, error)
	SaveForUser(ctx context.Context, userID uint64, memory *Memory) error
	SaveBatchForUser(ctx context.Context, userID uint64, memories []*Memory) error
	FindByUser(ctx context.Context, userID uint64, billingFilter *BillingEntity) ([]*Memory, error)
	FindByFactForUser(ctx context.Context, userID uint64, fact string) ([]*Memory, error)
	FindRecentByUser(ctx context.Context, userID uint64, limit uint, billingFilter *BillingEntity) ([]*Memory, error)
	DeleteForUser(ctx context.Context, userID uint64, id MemoryID) error
	DeleteBatchForUser(ctx context.Context, userID uint64, ids []MemoryID) (*BatchDeleteResult, error)
	DeleteAllForUser(ctx context.Context, userID uint64) error
	ListBillingEntityMemories(ctx context.Context, filter BillingEntityMemoryFilter, pageRequest MemoryPageRequest) (*MemoryPage, error)
	DeleteBillingEntityMemories(ctx context.Context, filter BillingEntityMemoryFilter, pageRequest MemoryPageRequest) (*BillingEntityDeleteResult, error)
}

// Errors
var (
	ErrMemoryNotFound = errors.New("memory not found")
	// ErrMemoryFactNotFound indicates that a memory with the specified fact does not exist for the user or repository.
	ErrMemoryFactNotFound   = errors.New("memory with the specified fact not found")
	ErrConcurrencyConflict  = errors.New("memory was modified concurrently")
	ErrInvalidRepoNWO       = errors.New("invalid repository NWO format")
	ErrEmptyRepoNWO         = errors.New("repository NWO cannot be empty")
	ErrEmptyRepoOwner       = errors.New("repository owner cannot be empty")
	ErrEmptyRepoName        = errors.New("repository name cannot be empty")
	ErrInvalidBillingFilter = errors.New("billing entity filter is required")
	ErrInvalidSnapshotTime  = errors.New("snapshot time is required")
	ErrInvalidUserFilter    = errors.New("user filter is required")
	ErrInvalidContinuation  = errors.New("invalid continuation token")
	ErrMemoryStoreThrottled = errors.New("memory store throttled")
	ErrUnauthorized         = errors.New("unauthorized access")
	ErrInvalidVoteDirection = errors.New("invalid vote direction")
)
