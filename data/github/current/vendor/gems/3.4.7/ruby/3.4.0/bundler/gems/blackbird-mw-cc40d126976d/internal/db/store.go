package db

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/db/repofilter"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

// Store defines an interface for repository and ingest state tracking and retrieval.
//
//go:generate counterfeiter . Store
type Store interface {
	// RepositorySequence returns the Repository after incrementing its sequence
	// number, if necessary. The callback should return the state from external
	// systems to be compared with what's in the store.
	RepositorySequence(ctx context.Context, repoID types.RepoID, fn RepoInfoFn) (*RepositoryResult, error)

	// ErroredRepositorySequence returns the next sequence numbers after creating
	// a repository row with placeholder values, if necessary. The repository
	// will be marked deleted if delete is true.
	//
	// This method is used when repository sequence numbers must be created,
	// but the repository information is not available, due to a failure.
	ErroredRepositorySequence(ctx context.Context, repoID types.RepoID, delete bool) (*SequenceNumbers, error)

	// Get/Set corpus state
	GetCorpusState(ctx context.Context, corpus routing.Corpus) (*CorpusState, error)
	SetCorpusIngestMode(ctx context.Context, corpus routing.Corpus, from, to IngestMode) (bool, error)

	// CreateEpoch creates a new epoch for the given corpus. If deltaIndex is
	// true, sets the corpus in backfill ingest mode.
	CreateEpoch(ctx context.Context, corpus routing.Corpus, description string) (*Epoch, error)
	GetEpoch(ctx context.Context, epochID types.EpochID) (*Epoch, error)
	UpdateEpochDescription(ctx context.Context, epochID types.EpochID, description string) error
	// GetEpochEndOffsets gets the set of end offsets for the epoch's backfill topic.
	GetEpochEndOffsets(ctx context.Context, epochID types.EpochID) (EpochOffsets, error)
	// SetEpochEndOffsets updates an epoch with the end offsets of the last Kafka messages published.
	SetEpochEndOffsets(ctx context.Context, epochID types.EpochID, offsets EpochOffsets) error

	// LoadRepositories loads every repository record that matches filter in the
	// store and passes each one to fn. If fn returns an error, LoadRepositories
	// will exit.
	LoadRepositories(ctx context.Context, filter repofilter.F, fn LoadRepoFn) error

	// LoadAllRepositoriesInBatches loads every repository record that matches
	// filter in the store and passes batches to fn. If fn returns an error,
	// LoadAllRepositoriesInBatches will exit.
	LoadRepositoriesInBatches(ctx context.Context, batchSize int, filter repofilter.F, fn LoadRepoBatchFn) error

	// Get a repository with a custom filter
	GetFirstRepository(ctx context.Context, filter repofilter.F) (*Repository, error)

	// GetRepositoryByNWO returns an active repository record from the store.
	//
	// If there is no active repository with the given NWO, nil, nil is
	// returned.
	GetRepositoryByNWO(ctx context.Context, nwo types.NWO) (*Repository, error)

	// GetRepositoryByID returns an active repository record from the store. See
	// also LoadRepositoriesByIDs; this version is more convenient with a single
	// repository ID.
	//
	// If there is no active repository with the given ID, nil, nil is returned.
	GetRepositoryByID(ctx context.Context, id types.RepoID) (*Repository, error)

	LoadRepositoriesByIDs(ctx context.Context, repos map[types.RepoID]*Repository) error

	RepositoryExists(ctx context.Context, repoID types.RepoID) (bool, error)

	// Delete repository marks a repository as deleted in the database. If it doesn't exist, this is a noop.
	DeleteRepository(ctx context.Context, repoID types.RepoID) error
}

// LoadRepoFn is the function signature for LoadAllRepositories. Return false to
// stop iterating.
type LoadRepoFn func(ctx context.Context, repo *Repository) bool

// LoadRepoBatchFn is the function signature for LoadAllRepositories. Return
// false to stop iterating.
type LoadRepoBatchFn func(ctx context.Context, repos []*Repository) bool

// RepoInfoFn is the signature for the RepositorySequence callback function.
type RepoInfoFn func(ctx context.Context, state RepoInfoState) (*SkipReason, *github.Repository, *gitaccess.RefTip, error)

// RepoInfoState is used to tell the RepoInfoFn the state of the repository passed in.
type RepoInfoState bool

var (
	RepoInfoStateNew      RepoInfoState = true
	RepoInfoStateExisting RepoInfoState = false
)

func (r RepoInfoState) String() string {
	if r {
		return "new"
	} else {
		return "existing"
	}
}

type SkipReason string

func (s *SkipReason) String() string {
	if s == nil {
		return ""
	}

	return string(*s)
}

var (
	SkipMaxDiskSize           SkipReason = "repo exceeds max disk size"
	SkipRepoDenyList          SkipReason = "repo ID on deny list"
	SkipNetworkDenyList       SkipReason = "network ID on deny list"
	SkipOwnerDenyList         SkipReason = "owner ID on deny list"
	SkipInvalidTargetCorpus   SkipReason = "invalid target corpus"
	SkipNotTargetCorpus       SkipReason = "not target corpus"
	SkipUnknownRepo           SkipReason = "repo unknown to blackbird"
	SkipPermanentError        SkipReason = "repo has permanent error in index"
	SkipDefaultRefOIDNotFound SkipReason = "default ref OID not found"
	SkipEmbeddingsDisabled    SkipReason = "repo not enabled for embeddings"
)

type CorpusState struct {
	Corpus     routing.Corpus `db:"corpus_id"`
	EpochID    types.EpochID  `db:"epoch_id"`
	IngestMode IngestMode     `db:"ingest_mode"`
}

// IngestMode models the delta ingesting modes that are coordinated between the
// middleware and the shards.
// For more details see [ADR 31. Delta Ingest](https://github.com/github/blackbird/blob/fc4b68db042bbb31b95d1dd069331b434fad0b67/docs/adr/0031-delta-ingest.md)
type IngestMode int

const (
	// Legacy is used for the tech preview ingestion pipeline which does not have
	// this concept.
	IngestModeLegacy IngestMode = iota

	// Backfill mode is used to do the initial ingestion of all repositories,
	// building the best possible tree. Consumption of incremental events is paused.
	IngestModeBackfill

	// Upon draining the backfill topic, the mw switches to a catchup mode where
	// incremental events are consumed (with debounce) but the process still works
	// to build the best possible tree.
	IngestModeBackfillCatchup

	// Once we've caught up on the incremental topics, the admin service signals
	// intent to switch to incremental mode by changing to
	// IngestModeIncrementalTransition and sending a message on the snapshot
	// topic.
	IngestModeIncrementalTransition

	// Once the snapshot messages has actually been sent, we switch to incremental
	// mode. In incremental mode, the middleware will process any push event to a
	// repo known to blackbird (as defined by the db) by pushing OO (infinity)
	// nodes to the tree based on the prior tree entry of the repo. New repos
	// (newly created, or new due to onboarding) will be added to the root so that
	// these repos are correctly searchable once all shards have processed.
	IngestModeIncremental
)

func (m IngestMode) String() string {
	return [...]string{"Legacy", "Backfill", "BackfillCatchup", "IncrementalTransition", "Incremental"}[m]
}

type Epoch struct {
	EpochID     types.EpochID  `db:"id"`
	Corpus      routing.Corpus `db:"corpus_id"`
	Description string         `db:"description"`
}

// Represents the last offset of each partition in an epoch's backfill topic.
type EpochOffset struct {
	EpochID   types.EpochID `db:"epoch_id"`
	Partition int32         `db:"kafka_partition"`
	Offset    int64         `db:"kafka_offset"`
}

// Newtype wrapper for a map of last offsets for an epoch's backfill. It is
// **not** safe to access from multiple threads/goroutines.
//
//	key   = partition
//	value = last offset
type EpochOffsets map[int32]int64

// Set an offset for a partition. Only the max offset is retained.
func (e EpochOffsets) Set(partition int32, offset int64) {
	if _, ok := e[partition]; ok {
		if offset > e[partition] {
			e[partition] = offset
		}
	} else {
		e[partition] = offset
	}
}

// Merge with another EpochOffsets map.
func (e EpochOffsets) Merge(other EpochOffsets) {
	for partition, offset := range other {
		e.Set(partition, offset)
	}
}

// RepositoryResult holds details from an attempt to increment the repository
// sequence number.
//
// If successful, it will contain non-nil values for Repository,
// GitHubRepository and RefTip.
//
// If the repository should not be ingested, it will contain a non-nil
// SkipReason.
type RepositoryResult struct {
	Repository       *Repository
	GitHubRepository *github.Repository
	RefTip           *gitaccess.RefTip
	SkipReason       *SkipReason
}

func (r *RepositoryResult) IsSkip() bool {
	return r.SkipReason != nil
}

type Repository struct {
	RepoID          types.RepoID            `db:"id"`
	OwnerID         uint32                  `db:"owner_id"`
	OwnerLogin      string                  `db:"owner_login"`
	Name            string                  `db:"name"`
	IsPublic        bool                    `db:"is_public"`
	SourceTopic     sql.NullString          `db:"source_topic"`
	DeletedAt       sql.NullTime            `db:"deleted_at"`
	IsArchived      bool                    `db:"is_archived"`
	PushedAt        sql.NullTime            `db:"pushed_at"`
	CreatedAt       sql.NullTime            `db:"created_at"`
	HasLicense      sql.NullBool            `db:"has_license"`
	NumWatchers     sql.NullInt32           `db:"num_watchers"`
	NumStars        sql.NullInt32           `db:"num_stars"`
	HasReadme       sql.NullBool            `db:"has_readme"`
	PublicForkCount sql.NullInt32           `db:"public_fork_count"`
	CommitSeqNo     sql.NullInt64           `db:"seq_no"`     // NOTE: No sql.NullUint64
	CommitOID       []byte                  `db:"commit_oid"` // NOTE: No sql.NullBytes
	NetworkID       sql.NullInt32           `db:"network_id"` // NOTE: Should be Uint32, make sql.NullInt64 to fit?
	LicenseName     sql.NullString          `db:"license_name"`
	IsFork          sql.NullBool            `db:"is_fork"`
	Experiments     experiments.Experiments `db:"experiments"`
	RepoSeqNo       sql.NullInt64           `db:"repo_seq_no"` // NOTE: No sql.NullUint64
}

func (r *Repository) NWO() string {
	return fmt.Sprintf("%s/%s", r.OwnerLogin, r.Name)
}

func (r *Repository) IsDeleted() bool {
	return r.DeletedAt.Valid
}

// Returns true if the repo is public or if the actor has access through their
// AccessiblePrivateRepoIDs.
func (r *Repository) IsAccessibleBy(actor *models.Actor) bool {
	if r.IsPublic {
		return true
	}
	return actor != nil && actor.AccessiblePrivateRepoIDs[r.RepoID]
}

// RepoScoreAdjustment is a magical value the reason for which is lost to the
// mysts of time that is applied to all repo scores :shrug:
//
// Also: the default value for repository score if no scoring fields are set.
const RepoScoreAjustment = -3500

// Compute the RepoScore for this repository based on the SQL that was used
// originally (excluding Dependency Graph data, which we don't have).
//
// See: https://github.com/github/blackbird-repo-generator/blob/55ab9bcddc39e059386f7926ca5f04295c601328/compute_repos.sql#L40-L47
func (r *Repository) RepoScore() float32 {
	score := float32(RepoScoreAjustment)

	if r.PushedAt.Valid && r.CreatedAt.Valid {
		score += float32(r.PushedAt.Time.Year() - r.CreatedAt.Time.Year())
	}

	if r.HasLicense.Valid && r.HasLicense.Bool {
		score += 100.0
	}

	if r.HasReadme.Valid && r.HasReadme.Bool {
		score += 200.0
	}

	if r.NumStars.Valid && r.NumStars.Int32 > 0 {
		score += (100 * float32(math.Log2(float64(r.NumStars.Int32))))
	}

	if r.NumWatchers.Valid && r.NumWatchers.Int32 > 0 {
		score += (100 * float32(math.Log2(float64(r.NumWatchers.Int32))))
	}

	return score
}

// NewDummyRepository returns a minimal Repository record that can be inserted.
// It is used when we need to create a sequence number for a repository we
// haven't fetched information about yet, or can't fetch information about
// because it is deleted, disabled, or in an error state.
func NewDummyRepository(repoID types.RepoID) *Repository {
	return &Repository{
		RepoID:     repoID,
		OwnerID:    0,
		OwnerLogin: fmt.Sprintf("repo-%d-dummy-owner", repoID),
		Name:       fmt.Sprintf("repo-%d-dummy-name", repoID),
		DeletedAt:  sql.NullTime{Time: time.Now().UTC(), Valid: true},
	}
}

type SequenceNumbers struct {
	CommitSeqNo uint64          `db:"seq_no"`
	RepoSeqNo   types.RepoSeqNo `db:"repo_seq_no"`
}

// RepositoryStateChanged returns true if any of the fields we care about for
// indexing is different from the API repository or ref tip.
//
// The repository IDs must match, or the function will panic.
func RepositoryStateChanged(ctx context.Context, dbr *Repository, apir *github.Repository, ref *gitaccess.RefTip) bool {
	if dbr.RepoID != apir.ID {
		panic(fmt.Sprintf("Database repository ID %d does not match API repository ID %d", dbr.RepoID, apir.ID))
	}

	// The repository was deleted, but if we got an API response, it's not any more.
	if dbr.DeletedAt.Valid {
		logging.Info(ctx, "repo change: deleted in database")
		return true
	}

	// NOTE: Repos that have not yet set a commit OID set need to be indexed to set it
	if len(dbr.CommitOID) == 0 {
		logging.Info(ctx, "repo change: database has no commit OID")
		return true
	}

	// The repo seq no check covers the repo metadata fields of owner id, repo name, is public, and is archived.
	if dbr.RepoSeqNo.Int64 == types.UnknownRepoSeqNo || dbr.RepoSeqNo.Int64 < int64(apir.RepoSeqNo) {
		logging.Info(ctx, "repo change: repo seq no", kvp.Int64("repo_seq_no.db", dbr.RepoSeqNo.Int64), kvp.Uint64("repo_seq_no.api", uint64(apir.RepoSeqNo)))
		return true
	}

	if dbr.OwnerLogin != apir.OwnerLogin {
		logging.Info(ctx, "repo change: owner login", kvp.String("owner_login.db", dbr.OwnerLogin), kvp.String("owner_login.api", apir.OwnerLogin))
		return true
	}

	if dbr.NetworkID.Int32 != int32(apir.NetworkID) {
		logging.Info(ctx, "repo change: network ID", kvp.Int("network_id.db", int(dbr.NetworkID.Int32)), kvp.Int("network_id.api", int(apir.NetworkID)))
		return true
	}

	if dbr.NumWatchers.Int32 != apir.NumWatchers {
		logging.Info(ctx, "repo change: num watchers", kvp.Int("num_watchers.db", int(dbr.NumWatchers.Int32)), kvp.Int("num_watchers.api", int(apir.NumWatchers)))
		return true
	}

	if dbr.NumStars.Int32 != apir.NumStars {
		logging.Info(ctx, "repo change: num stars", kvp.Int("num_stars.db", int(dbr.NumStars.Int32)), kvp.Int("num_stars.api", int(apir.NumStars)))
		return true
	}

	if dbr.HasReadme.Bool != apir.HasReadme {
		logging.Info(ctx, "repo change: has readme", kvp.Bool("has_readme.db", dbr.HasReadme.Bool), kvp.Bool("has_readme.api", apir.HasReadme))
		return true
	}

	if dbr.PublicForkCount.Int32 != apir.PublicForkCount {
		logging.Info(ctx, "repo change: public fork count", kvp.Int("public_fork_count.db", int(dbr.PublicForkCount.Int32)), kvp.Int("public_fork_count.api", int(apir.PublicForkCount)))
		return true
	}

	apiLicenseName := sql.NullString{String: apir.LicenseName, Valid: true}
	if dbr.LicenseName != apiLicenseName {
		logging.Info(ctx, "repo change: license name", kvp.Any("license_name.db", dbr.LicenseName), kvp.Any("license_name.api", apiLicenseName))
		return true
	}

	apiIsFork := sql.NullBool{Bool: apir.IsFork, Valid: true}
	if dbr.IsFork != apiIsFork {
		logging.Info(ctx, "repo change: is fork", kvp.Any("is_fork.db", dbr.IsFork), kvp.Any("is_fork.api", apiIsFork))
		return true
	}

	if !dbr.Experiments.Equal(apir.Experiments) {
		logging.Info(ctx, "repo change: experiments", kvp.String("experiments.db", dbr.Experiments.String()), kvp.String("experiments.api", apir.Experiments.String()))
		return true
	}

	dbCommitOID := gitaccess.NewObjectIDFromBytes(dbr.CommitOID)
	if !dbCommitOID.Equal(ref.CommitOID) {
		logging.Info(ctx, "repo change: commit OID", kvp.String("commit_oid.db", dbCommitOID.String()), kvp.String("commit_oid.api", ref.CommitOID.String()))
		return true
	}

	return false
}
