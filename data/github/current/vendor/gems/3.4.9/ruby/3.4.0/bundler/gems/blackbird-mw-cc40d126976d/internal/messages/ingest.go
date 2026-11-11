package messages

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/github/blackbird/crates/core/pkg/epoch"
	hydro_schemas_blackbird_v0_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	search_pb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

// Ingest indicates a repository to index in Blackbird.
type Ingest struct {
	// Kafka
	Topic     string
	Partition int32
	Offset    int64
	Timestamp time.Time
	HydroID   string
	Change    search_pb.RepositoryChanged_Change

	// Repo
	RepoID                   types.RepoID
	ParentRepoID             types.RepoID
	CommitSHA                []byte
	ParentCommitSHA          []byte
	ParentGeometricXorFilter []byte
	Ancestors                []types.RepoID
	PreallocatedChildID      uint32
	RepoName                 string
	OwnerID                  uint32
	OwnerLogin               string
	IsPublic                 bool
	IsArchived               bool
	IsFork                   bool
	PayingCustomer           bool
	RepoScore                float32
	LicenseName              sql.NullString
	NumWatchers              int32
	NumStars                 int32
	HasReadme                bool
	PublicForkCount          int32
	NetworkID                types.NetworkID
	MaxRepoScore             float32
	DotcomExperiments        experiments.Experiments
	// RepoSeqNo is the global repository sequence number associated with a repository change that initiated an ingest event.
	RepoSeqNo types.RepoSeqNo

	Head *gitaccess.RefTip // HEAD ref tip

	// Corpus, epoch, and topic information
	Corpus        routing.Corpus
	EpochID       types.EpochID
	EpochMode     epoch.EpochMode
	IngestMode    db.IngestMode
	DocumentTopic routing.DocumentTopic
	SnapshotTopic routing.SnapshotTopic

	SnapshotBarrier *hydro_schemas_blackbird_v0_entities.TopicBarrier
	IngestStartedAt time.Time
	EntryID         uint64
	ParentEntryID   uint64
	// Lease represents the time a snapshot entry is valid to modify. A lease is
	// acquired from the successful response of the Index RPC. If expired,
	// ingest must stop. It can be extended by calling the Lease RPC.
	Lease            *Lease
	EntryExperiments experiments.Experiments
	ServingOffset    int64

	// Repository-scoped commit sequence number (used for IndexQueryAPI)
	CommitSeqNo uint64
}

func (i *Ingest) RepoNode() types.RepoNode {
	return types.RepoNode{RepoID: i.RepoID, PreallocatedChildID: i.PreallocatedChildID, Ancestors: i.Ancestors}
}

func (i *Ingest) NWO() string {
	return fmt.Sprintf("%s/%s", i.OwnerLogin, i.RepoName)
}

func (i *Ingest) IsReindex() bool {
	return i.Change == search_pb.RepositoryChanged_ADMIN_REPAIR
}
