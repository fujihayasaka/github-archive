package healthcheck

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/blackbird/crates/linguist/pkg/linguist"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	spokes "github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/google/uuid"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/parser"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/search/blackbird"
	"github.com/github/blackbird-mw/internal/types"
)

type PathProber struct {
	index   *blackbird.Cluster
	repo    *db.Repository
	headOID gitaccess.ObjectID

	*Prober
}

func NewPathProber(index *blackbird.Cluster, repo *db.Repository, headOID gitaccess.ObjectID, prober *Prober) *PathProber {
	return &PathProber{index, repo, headOID, prober}
}

func (p *PathProber) Check(ctx context.Context, path string) error {
	ctx = statting.WithTags(ctx, stats.Tags{"corpus": p.index.CorpusName(), "epoch_mode": p.index.EpochMode().String(), "prober": "path"})
	ctx = logging.With(ctx,
		kvp.String("corpus", p.index.CorpusName()),
		kvp.String("prober", "path"),
		kvp.String("prober_id", uuid.New().String()),
		kvp.Int("repo_id", int(p.repo.RepoID)),
		kvp.String("nwo", p.repo.NWO()),
		kvp.String("head_oid", p.headOID.String()),
		kvp.String("path", path),
		kvp.Int("epoch", int(p.index.EpochID())),
		kvp.String("epoch_mode", p.index.EpochMode().String()),
		kvp.Int64("serving_ts", p.index.ServingTs().UnixMilli()),
		kvp.Int64("serving_offset", int64(p.index.ServingOffset())),
	)

	// Required to match ingest settings.
	ctx = experiments.WithCluster(ctx,
		&experiments.ClusterEnv{
			EpochID:     p.index.EpochID(),
			ClusterName: p.index.ClusterName(),
			CorpusName:  p.index.CorpusName(),
		})

	// Search blackbird for this repo+path
	q := parser.And(parser.RepoID(int(p.repo.RepoID)), parser.Path(path))
	ctx = logging.With(ctx, kvp.String("q", parser.Serialize(q)))
	res, err := p.search(ctx, q)
	if err != nil {
		return err
	}

	for _, doc := range res.Documents {
		for _, loc := range doc.Locations {
			if loc.Path == path {
				// Success: this file is indexed by blackbird
				return nil
			}
		}
	}

	// File not found in blackbird, why?

	// Check that it actually exists in the git repo
	blobOID, err := p.findBlobInGit(ctx, path)
	if err != nil {
		return err
	}

	// Check if any of the QoS filters excluded it or if it is excluded due to our rules
	contentErr := fmt.Errorf(
		"%s isn't indexed because due to one or more QoS filters: non-utf8, binary, %d < file size < %d",
		path,
		gitaccess.MinBlobSize,
		gitaccess.MaxBlobSize)
	if err := p.gitClient.GetBlobs(ctx, p.repo.RepoID, []*spokes.ObjectID{{Id: blobOID.String()}}, func(blob *gitaccess.BlobEntry) {
		isIndexable, reason, err := linguist.IsIndexable(path, blob.Content, uint32(p.index.NumShards()))
		if err != nil {
			logging.Error(ctx, "isIndexable failed", kvp.Err(err), kvp.String("path", path))
			contentErr = fmt.Errorf("%s: cannot determine indexable status: %w", path, err)
		} else if !isIndexable {
			contentErr = fmt.Errorf("%s is detected not suitable for indexing: %s", path, reason)
		} else {
			contentErr = nil
		}
	}); err != nil {
		return err
	}

	return contentErr
}

func (p *PathProber) search(ctx context.Context, q *parser.Query) (*pb.QueryResponse, error) {
	const bigLimit = 10000
	queryCtx := search.BuildQueryContext(
		&models.Actor{AccessiblePrivateRepoIDs: types.RepoIDSet{p.repo.RepoID: true}},
		search.QueryLimits{
			RequestedDocs:  bigLimit,
			RequestedLocs:  blackbirdLocationLimit,
			LocationsLimit: blackbirdLocationLimit,
			TermMatchLimit: 0, // NB: No need for any term matches
			ToRetrieve:     bigLimit,
			ToScore:        bigLimit,
			ToReturn:       bigLimit,
			WithContent:    0, // NB: Set to 0 to tell blackbird not to bother sending any content
		},
		3, /* retries */
		search.ProbersUnavailableShardsPercent,
		search.DefaultTimeout,
		search.QueryTypePath,
		search.QuerySourceProber,
		parser.GetScopeRepoIDs(q),
		nil, /* snippetOptions */
		nil, /* paginationOptions */
		parser.Serialize(q),
		false, /* returnEnclosingSymbols */
	)

	rid := uuid.New().String()
	ctx = logging.With(requestid.WithGitHubRequestID(ctx, rid), kvp.String("request_id", rid))
	res, err := p.index.Search(ctx, parser.ConvertToProto(q), queryCtx)
	if err == nil {
		for _, e := range res.QueryErrors {
			logging.Error(ctx, "query error", kvp.String("query_error", e.Message), kvp.String("query_error_type", e.Type.String()))
			return nil, errors.New(e.Message)
		}
	}
	return res, err
}

func (p *PathProber) findBlobInGit(ctx context.Context, path string) (*gitaccess.ObjectID, error) {
	head := spokes.NewTreeishWithObjectID(spokes.NewObjectID(p.headOID.String()))
	diffEntries, err := p.gitClient.Diff(ctx, 0, nil, &gitaccess.Treeish{RepoID: p.repo.RepoID, Treeish: head})
	if err != nil {
		return nil, err
	}

	for _, entries := range diffEntries {
		for _, entry := range entries {
			if entry.Path == path {
				return &entry.OID, nil
			}
		}
	}

	return nil, fmt.Errorf("%s not found in repo %s@%s", path, p.repo.NWO(), p.headOID.String())
}
