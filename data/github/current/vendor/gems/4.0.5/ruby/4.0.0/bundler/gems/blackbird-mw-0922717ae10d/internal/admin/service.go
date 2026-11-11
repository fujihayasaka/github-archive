package admin

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"math"
	"strconv"
	"sync"
	"time"

	"github.com/IBM/sarama"
	"github.com/cenkalti/backoff/v4"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging" //nolint:staticcheck
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	blackbird_pb "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	search_pb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	sitesapi "github.com/github/sitesapiclient"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/blackbird-mw/internal/auth/ong"
	"github.com/github/blackbird-mw/internal/background"
	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/chat"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/repofilter"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/healthcheck"
	"github.com/github/blackbird-mw/internal/ingest"
	"github.com/github/blackbird-mw/internal/kafka"
	pb "github.com/github/blackbird-mw/internal/proto/admin/v1"
	"github.com/github/blackbird-mw/internal/publish/backfill"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/search/blackbird"
	"github.com/github/blackbird-mw/internal/types"
	"github.com/github/blackbird-mw/internal/utils"
)

type adminService struct {
	searchClusters              *routing.SearchClusters
	cacheClusters               *routing.CacheClusters
	indexerClusters             *routing.IndexerClusters
	store                       db.Store
	pager                       cache.Store
	gitClient                   gitaccess.Client
	githubClient                github.InternalAPIClient
	chatClient                  chat.Client
	kafkaClusterResolver        routing.ClusterResolver
	blackbirdKafkaAdminProvider func(routing.Corpus) sarama.ClusterAdmin
	sharedKafkaClient           sarama.Client
	topicConfig                 routing.TopicConfig
	backfiller                  *backfill.Publisher
	repoPublisher               *repo.Publisher
	snapshotProducers           map[routing.Region]sarama.SyncProducer
	quotaRateEstimator          quota.RateEstimator
	assignmentsReader           kafka.AssignmentsReader
	sitesAPIClient              *sitesapi.Client
	stamp                       routing.Stamp
	prober                      *healthcheck.Prober
	cgManager                   kafka.ConsumerGroupManager
}

func NewService(
	searchClusters *routing.SearchClusters,
	cacheClusters *routing.CacheClusters,
	indexerClusters *routing.IndexerClusters,
	store db.Store,
	pager cache.Store,
	gitClient gitaccess.Client,
	githubClient github.InternalAPIClient,
	chatClient chat.Client,
	kafkaClusterResolver routing.ClusterResolver,
	blackbirdKafkaAdminProvider func(routing.Corpus) sarama.ClusterAdmin,
	sharedKafkaClient sarama.Client,
	topicConfig routing.TopicConfig,
	backfiller *backfill.Publisher,
	repoPublisher *repo.Publisher,
	snapshotProducers map[routing.Region]sarama.SyncProducer,
	quotaRateEstimator quota.RateEstimator,
	assignmentsReader kafka.AssignmentsReader,
	sitesAPIClient *sitesapi.Client,
	stamp routing.Stamp,
	tsReader *kafka.DelayedTimestampReader,
	cgManager kafka.ConsumerGroupManager,
) pb.AdminAPI {
	return &adminService{
		searchClusters:              searchClusters,
		cacheClusters:               cacheClusters,
		indexerClusters:             indexerClusters,
		store:                       store,
		pager:                       pager,
		gitClient:                   gitClient,
		githubClient:                githubClient,
		chatClient:                  chatClient,
		kafkaClusterResolver:        kafkaClusterResolver,
		blackbirdKafkaAdminProvider: blackbirdKafkaAdminProvider,
		sharedKafkaClient:           sharedKafkaClient,
		topicConfig:                 topicConfig,
		backfiller:                  backfiller,
		repoPublisher:               repoPublisher,
		snapshotProducers:           snapshotProducers,
		quotaRateEstimator:          quotaRateEstimator,
		assignmentsReader:           assignmentsReader,
		sitesAPIClient:              sitesAPIClient,
		stamp:                       stamp,
		prober:                      healthcheck.NewProber(store, pager, gitClient, stamp, searchClusters, indexerClusters, sharedKafkaClient, githubClient, repoPublisher, tsReader, topicConfig),
		cgManager:                   cgManager,
	}
}

func (s *adminService) DeleteRepoEmbeddings(ctx context.Context, req *pb.DeleteRepoEmbeddingsRequest) (*pb.DeleteRepoEmbeddingsResponse, error) {
	ctx = logging.With(ctx, kvp.String("nwo", req.RepoNwo))
	logging.Info(ctx, "deleting repo embeddings in all embeddings-only epochs")
	repo, err := s.getRepoByNWO(ctx, req.RepoNwo)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("failed to get repository"), err)
	}
	if repo == nil {
		return nil, twirp.NotFoundError("repository not found")
	}

	status, err := s.githubClient.DeleteCopilotIndexedRepository(ctx, true, &github.CopilotIndexedRepository{
		RepositoryID: repo.RepoID,
	})
	if err != nil {
		logging.Error(ctx, "delete request to github internal api failed", kvp.Int("status", status), kvp.Err(err))
		return nil, twirp.InternalError("delete request to github internal api failed")
	}

	err = s.repoPublisher.PublishChange(ctx, repo.RepoID, search_pb.RepositoryChanged_ADMIN_REPAIR, "")
	if err != nil {
		logging.Error(ctx, "delete repo embeddings publish failed", kvp.Err(err))
		return nil, twirp.InternalError(err.Error())
	}

	s.say(ctx, fmt.Sprintf("queued to delete repo embeddings for repo=%q, repo_id=%d, internal API status code=%d", req.RepoNwo, repo.RepoID, status))

	return &pb.DeleteRepoEmbeddingsResponse{}, nil
}

func (s *adminService) GetRepoStatus(ctx context.Context, req *pb.GetRepoStatusRequest) (*pb.GetRepoStatusResponse, error) {
	corpora := []routing.Corpus{}
	c, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		corpora = append(corpora, s.stamp.EnabledCorpora()...)
	} else {
		corpora = append(corpora, c)
	}

	var repo *db.Repository
	if req.RepoNwo != "" {
		repo, err = s.getRepoByNWO(ctx, req.RepoNwo)
	} else {
		repo, err = s.getRepoByID(ctx, req.RepoId)
	}

	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("failed to get repository"), err)
	}

	if repo == nil {
		nwo, err := types.NewNWO(req.RepoNwo)
		if err != nil {
			return nil, twirp.InvalidArgumentError("repo_nwo", "repo not in db and repo_nwo is not valid")
		}
		// Fetch this repo from github so that we can pickup repos that aren't in our
		// database yet.
		githubRepo, err := s.githubClient.GetRepositoryByNWO(ctx, nwo)
		if err != nil {
			switch err {
			case github.ErrRepoNotFound, github.ErrRepoDisabled, github.ErrRepoBlocked:
				logging.Error(ctx, "repository not found, disabled, or blocked", kvp.Err(err))
				return nil, twirp.NotFoundError("repository not found, disabled, or blocked")
			default:
				return nil, twirp.WrapError(twirp.InternalError("could not fetch this repository from github.com"), err)
			}
		}
		if githubRepo == nil {
			return nil, twirp.InternalError("could not fetch this repository from github.com")
		}
		s.say(ctx, fmt.Sprintf("%s is not indexed by blackbird", req.RepoNwo))
		return &pb.GetRepoStatusResponse{
			RepoId:   uint32(githubRepo.ID),
			RepoNwo:  githubRepo.NWO(),
			IsPublic: githubRepo.Public,
			GithubDetails: &pb.GitHubRepositoryAPIResponse{
				Repository: &pb.GitHubRepositoryDetails{
					Id:              uint32(githubRepo.ID),
					NetworkId:       uint32(githubRepo.NetworkID),
					OwnerId:         githubRepo.OwnerID,
					OwnerLogin:      githubRepo.OwnerLogin,
					Name:            githubRepo.Name,
					Public:          githubRepo.Public,
					Archived:        githubRepo.Archived,
					DiskUsage:       githubRepo.DiskUsage,
					PushedAt:        timestamppb.New(githubRepo.PushedAt),
					CreatedAt:       timestamppb.New(githubRepo.CreatedAt),
					LicenseName:     githubRepo.LicenseName,
					NumWatchers:     int32(githubRepo.NumWatchers),
					NumStars:        int32(githubRepo.NumStars),
					HasReadme:       githubRepo.HasReadme,
					PublicForkCount: int32(githubRepo.PublicForkCount),
					PayingCustomer:  githubRepo.PayingCustomer,
					BusinessId:      githubRepo.BusinessID,
					BusinessSlug:    githubRepo.BusinessSlug,
				},
			},
		}, nil
	}

	var githubResp *pb.GitHubRepositoryAPIResponse
	if s.githubClient == nil {
		githubResp = &pb.GitHubRepositoryAPIResponse{
			Error: "cannot check repository status without internal API client",
		}
	} else if githubRepo, err := s.githubClient.GetRepository(ctx, repo.RepoID); err != nil {
		githubResp = &pb.GitHubRepositoryAPIResponse{
			Error: err.Error(),
		}
	} else {
		githubResp = &pb.GitHubRepositoryAPIResponse{
			Repository: &pb.GitHubRepositoryDetails{
				Id:              uint32(githubRepo.ID),
				NetworkId:       uint32(githubRepo.NetworkID),
				OwnerId:         githubRepo.OwnerID,
				OwnerLogin:      githubRepo.OwnerLogin,
				OwnerSpammy:     githubRepo.OwnerSpammy,
				Name:            githubRepo.Name,
				Public:          githubRepo.Public,
				Archived:        githubRepo.Archived,
				DiskUsage:       githubRepo.DiskUsage,
				PushedAt:        timestamppb.New(githubRepo.PushedAt),
				CreatedAt:       timestamppb.New(githubRepo.CreatedAt),
				LicenseName:     githubRepo.LicenseName,
				NumWatchers:     int32(githubRepo.NumWatchers),
				NumStars:        int32(githubRepo.NumStars),
				HasReadme:       githubRepo.HasReadme,
				PublicForkCount: int32(githubRepo.PublicForkCount),
				PayingCustomer:  githubRepo.PayingCustomer,
				IsFork:          githubRepo.IsFork,
				Experiments:     githubRepo.Experiments,
				UpdatedAt:       timestamppb.New(githubRepo.UpdatedAt),
				BusinessId:      githubRepo.BusinessID,
				BusinessSlug:    githubRepo.BusinessSlug,
			},
		}
	}
	indexerIngests, servingIngests, err := fetchIngests(s, ctx, corpora, repo.RepoID)
	if err != nil {
		return nil, err
	}

	return &pb.GetRepoStatusResponse{
		RepoId:         uint32(repo.RepoID),
		RepoNwo:        repo.OwnerLogin + "/" + repo.Name,
		IsPublic:       repo.IsPublic,
		ServingIngests: servingIngests,
		IndexerIngests: indexerIngests,
		GithubDetails:  githubResp,
		DeletedAt:      pbTimestamp(repo.DeletedAt),
		DatabaseRepository: &pb.DatabaseRepository{
			RepoId:          uint32(repo.RepoID),
			OwnerId:         repo.OwnerID,
			OwnerLogin:      repo.OwnerLogin,
			Name:            repo.Name,
			IsPublic:        repo.IsPublic,
			SourceTopic:     repo.SourceTopic.String,
			DeletedAt:       pbTimestamp(repo.DeletedAt),
			IsArchived:      repo.IsArchived,
			PushedAt:        pbTimestamp(repo.PushedAt),
			CreatedAt:       pbTimestamp(repo.CreatedAt),
			HasLicense:      repo.HasLicense.Bool,
			NumWatchers:     repo.NumWatchers.Int32,
			NumStars:        repo.NumStars.Int32,
			HasReadme:       repo.HasReadme.Bool,
			PublicForkCount: repo.PublicForkCount.Int32,
			CommitSeqNo:     repo.CommitSeqNo.Int64,
			CommitOid:       hex.EncodeToString(repo.CommitOID),
			NetworkId:       repo.NetworkID.Int32,
			LicenseName:     repo.LicenseName.String,
			IsFork:          repo.IsFork.Bool,
			Experiments:     repo.Experiments,
			RepoSeqNo:       repo.RepoSeqNo.Int64,
			BusinessId:      uint64(repo.BusinessID.Int64),
			BusinessSlug:    repo.BusinessSlug.String,
		},
	}, nil
}

func (s *adminService) GetFilesetStatus(ctx context.Context, req *pb.GetFilesetStatusRequest) (*pb.GetFilesetStatusResponse, error) {
	corpora := []routing.Corpus{}
	c, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		corpora = append(corpora, s.stamp.EnabledCorpora()...)
	} else {
		corpora = append(corpora, c)
	}

	var fileset *db.Fileset
	nwo, err := types.NewNWO(req.Fileset)
	if err != nil {
		fileset, err = s.store.GetFirstFileset(ctx, uint64(req.RepoId))
	} else {
		fileset, err = s.store.GetFirstFilesetByNWO(ctx, nwo)
	}
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("failed to get fileset"), err)
	}

	indexerIngests, servingIngests, err := fetchIngests(s, ctx, corpora, types.RepoID(fileset.RepositoryId))
	if err != nil {
		return nil, err
	}

	return &pb.GetFilesetStatusResponse{
		RepoId:         uint32(fileset.RepositoryId),
		Fileset:        fileset.Fileset,
		ServingIngests: servingIngests,
		IndexerIngests: indexerIngests,
		DeletedAt:      pbTimestamp(fileset.DeletedAt),
	}, nil
}

func (s *adminService) FindAnything(ctx context.Context, req *pb.FindAnythingRequest) (*pb.FindAnythingResponse, error) {
	repositories := []*pb.GitHubRepository{}
	filesets := []*pb.Fileset{}
	owners := []*pb.GitHubOwner{}
	nwo, err := types.NewNWO(req.Q)
	if err == nil {
		err := s.store.LoadRepositories(ctx, repofilter.NWO(nwo), func(ctx context.Context, repo *db.Repository) bool {
			repositories = append(repositories, &pb.GitHubRepository{
				RepoId:    uint32(repo.RepoID),
				RepoNwo:   repo.NWO(),
				DeletedAt: pbTimestamp(repo.DeletedAt),
			})
			return true
		})
		if err != nil {
			logging.Error(ctx, "failed to load repositories in FindAnything", kvp.Err(err))
		}
		fileset, err := s.store.GetFirstFilesetByNWO(ctx, nwo)
		if err == nil && fileset != nil {
			filesets = append(filesets, &pb.Fileset{
				RepoId:    fileset.RepositoryId,
				OwnerId:   fileset.OwnerId,
				Fileset:   fileset.Fileset,
				DeletedAt: pbTimestamp(fileset.DeletedAt),
			})
		}
	}

	id, err := strconv.ParseUint(req.Q, 10, 64)
	if err == nil {
		repo, err := s.store.GetFirstRepository(ctx, repofilter.ID(types.RepoID(id)))
		if err == nil && repo != nil {
			repositories = append(repositories, &pb.GitHubRepository{
				RepoId:    uint32(repo.RepoID),
				RepoNwo:   repo.NWO(),
				DeletedAt: pbTimestamp(repo.DeletedAt),
			})
		}
		fileset, err := s.store.GetFirstFileset(ctx, id)
		if err == nil && fileset != nil {
			filesets = append(filesets, &pb.Fileset{
				RepoId:    fileset.RepositoryId,
				OwnerId:   fileset.OwnerId,
				Fileset:   fileset.Fileset,
				DeletedAt: pbTimestamp(fileset.DeletedAt),
			})
		}
	} else {
		user, err := s.githubClient.GetUser(ctx, req.Q)
		if err != nil {
			logging.Error(ctx, "failed to get user", kvp.Err(err))
		} else {
			owners = append(owners, &pb.GitHubOwner{OwnerId: uint32(user.GetID()), Login: user.GetLogin()})
		}
	}

	return &pb.FindAnythingResponse{Repositories: repositories, Filesets: filesets, Owners: owners}, nil
}

func (s *adminService) IndexRepo(ctx context.Context, req *pb.IndexRepoRequest) (*pb.IndexRepoResponse, error) {
	var repoID types.RepoID
	var repoIdentifier string
	var ownerID uint32

	// If the request's RepoId is not set (meaning it defaults to uint32 zero value),
	// then we expect the RepoNwo to be set.
	if req.RepoId == 0 {
		nwo, err := types.NewNWO(req.RepoNwo)
		if err != nil {
			return nil, twirp.InvalidArgumentError("repo_nwo", "is not a valid NWO")
		}

		// Fetch this repo from github so that we can pickup repos that aren't in our
		// database yet.
		repo, err := s.githubClient.GetRepositoryByNWO(ctx, nwo)
		if err != nil {
			switch err {
			case github.ErrRepoNotFound, github.ErrRepoDisabled, github.ErrRepoBlocked:
				logging.Error(ctx, "repository not found, disabled, or blocked", kvp.Err(err))
				return nil, twirp.NotFoundError("repository not found, disabled, or blocked")
			default:
				return nil, twirp.WrapError(twirp.InternalError("could not fetch this repository from github.com"), err)
			}
		}
		if repo == nil {
			return nil, twirp.InternalError("could not fetch this repository from github.com")
		}
		repoID = repo.ID
		repoIdentifier = req.RepoNwo
		ownerID = repo.OwnerID
	} else {
		repoID = types.RepoID(req.RepoId)
		repoIdentifier = fmt.Sprintf("%d", repoID)
	}

	resp := &pb.IndexRepoResponse{}
	resp.RepositoryId = uint32(repoID)

	if req.IndexEmbeddings {
		enablerUsername := ong.GetUsername(ctx)

		if ownerID == 0 {
			repo, err := s.githubClient.GetRepository(ctx, repoID)
			if err != nil {
				logging.Error(ctx, "could not find repository for indexing", kvp.Err(err), kvp.Uint("repo_id", uint(repoID)))
				return nil, twirp.WrapError(twirp.InternalError("could not find repository for indexing"), err)
			}
			ownerID = repo.OwnerID
		}

		status, err := s.githubClient.IndexEmbeddings(ctx, repoID, ownerID)
		if err != nil {
			logging.Error(ctx, "failed to index embeddings", kvp.Err(err), kvp.Uint("repo_id", uint(repoID)), kvp.String("username", enablerUsername))
			return nil, twirp.WrapError(twirp.InternalError("failed to index embeddings"), err)
		}

		logging.Info(ctx, "enabling embeddings indexing on behalf of repo owner", kvp.String("repo", repoIdentifier), kvp.String("username", enablerUsername))
		s.say(ctx, fmt.Sprintf("triggered embeddings indexing for repo=%q, repo_id=%d, status=%d", repoIdentifier, repoID, status))
		return resp, nil
	}

	if req.ForceReindex {
		if err := s.repoPublisher.PublishChange(ctx, repoID, search_pb.RepositoryChanged_ADMIN_REPAIR, req.Corpus); err != nil {
			logging.Error(ctx, "failed to publish message to reindex repo", kvp.Err(err), kvp.Uint("repo_id", uint(repoID)), kvp.String("nwo", req.RepoNwo))
			return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("failed to publish message to reindex repo %q", repoIdentifier)), err)
		}
	} else {
		if err := s.repoPublisher.Publish(ctx, repoID, req.Corpus); err != nil {
			logging.Error(ctx, "failed to publish message to index repo", kvp.Err(err), kvp.Uint("repo_id", uint(repoID)), kvp.String("nwo", req.RepoNwo))
			return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("failed to publish message to index repo %q", repoIdentifier)), err)
		}
	}

	corpusDisplay := req.Corpus
	if corpusDisplay == "" {
		corpusDisplay = "all"
	}

	result := fmt.Sprintf("queued for indexing, repo=%q, repo_id=%d, force_reindex=%t, corpus=%s", repoIdentifier, repoID, req.ForceReindex, corpusDisplay)
	s.say(ctx, result)

	return resp, nil
}

func (s *adminService) IndexRepoList(ctx context.Context, req *pb.IndexRepoListRequest) (*pb.IndexRepoListResponse, error) {
	repoIDs := req.GetRepoIds()
	if len(repoIDs) == 0 {
		return nil, twirp.InvalidArgumentError("repo_ids", "must contain at least one repo")
	}

	for _, repoID := range repoIDs {
		if err := s.repoPublisher.PublishChange(ctx, types.RepoID(repoID), search_pb.RepositoryChanged_ADMIN_REPAIR, req.Corpus); err != nil {
			logging.Error(
				ctx,
				"failed to publish message to index repo",
				kvp.Err(err), kvp.Uint("repo_id", uint(repoID)),
				kvp.String("corpus", req.Corpus),
			)

			return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("failed to publish message to index repo %q", repoID)), err)
		}
	}

	if len(req.Corpus) != 0 {
		s.say(ctx, fmt.Sprintf("queued %d repos for indexing in corpus %s", len(repoIDs), req.Corpus))
	} else {
		s.say(ctx, fmt.Sprintf("queued %d repos for indexing in all corpora", len(repoIDs)))
	}

	return &pb.IndexRepoListResponse{
		ReposQueued: uint32(len(repoIDs)),
	}, nil

}

func (s *adminService) ProbeRepo(ctx context.Context, req *pb.ProbeRepoRequest) (*pb.ProbeRepoResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		return nil, err
	}

	var repo *db.Repository
	if req.RepoId == 0 {
		repo, err = s.getRepoByNWO(ctx, req.RepoNwo)
	} else {
		repo, err = s.getRepoByID(ctx, req.RepoId)
	}
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("failed to get repository"), err)
	}
	if repo == nil {
		return nil, twirp.NotFoundError("repository not found")
	}

	cluster, err := blackbird.GetClusterWithoutBlobResolution(ctx, s.searchClusters, s.store, s.pager, corpus)
	if err != nil {
		return nil, err
	}

	headOID, err := s.getHeadOID(ctx, cluster, repo)
	if err != nil {
		return nil, err
	}

	if req.Path != "" {
		s.say(ctx, fmt.Sprintf("probing repo %q (single path) in %s", repo.NWO(), corpus.NameWithCluster()))
		// Probe just a single path
		prober := healthcheck.NewPathProber(cluster, repo, headOID, s.prober)
		if err := prober.Check(ctx, req.Path); err != nil {
			return nil, err
		}
		return &pb.ProbeRepoResponse{Verified: 1}, nil
	} else {
		s.say(ctx, fmt.Sprintf("probing repo %q in %s", repo.NWO(), corpus.NameWithCluster()))
		ctx = logging.With(ctx, kvp.Bool("is_public", repo.IsPublic), kvp.String("nwo", repo.NWO()))
		prober := healthcheck.NewCompletenessProber(cluster, repo.RepoID, headOID, s.prober)
		summary, err := prober.Check(ctx, true)
		if err != nil {
			return nil, err
		}

		return &pb.ProbeRepoResponse{
			Verified:         uint32(summary.Verified),
			Missing:          summary.Missing,
			Extra:            summary.Extra,
			NumTrailingZeros: uint32(summary.NumTrailingZeros),
		}, nil
	}
}

func (s *adminService) ListStamps(ctx context.Context, req *pb.ListStampsRequest) (*pb.ListStampsResponse, error) {
	stamps := []string{}
	for _, stamp := range routing.AllStamps {
		stamps = append(stamps, string(stamp))
	}
	return &pb.ListStampsResponse{Stamps: stamps}, nil
}

func (s *adminService) GetCorpusStatus(ctx context.Context, req *pb.GetCorpusStatusRequest) (*pb.GetCorpusStatusResponse, error) {
	statuses := []*pb.CorpusStatus{}
	activeEpochs := map[types.EpochID]bool{}
	for _, corpus := range s.stamp.EnabledCorpora() {
		state, err := s.store.GetCorpusState(ctx, corpus)
		if err != nil {
			return nil, twirp.WrapError(twirp.InternalError("failed to get corpus state"), err)
		}

		storeEpoch, err := s.store.GetEpoch(ctx, state.EpochID)
		if err != nil {
			return nil, twirp.WrapError(twirp.InternalError("failed to get epoch"), err)
		}

		cluster, err := s.prober.ComputeHealthSummary(ctx, corpus)
		if err != nil {
			return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("failed to get cluster status for %s", corpus.ClusterName())), err)
		}

		summary := cluster.Status
		var pinnedServingTs *wrapperspb.Int64Value
		if summary.PinnedServingTs != nil {
			pinnedServingTs = &wrapperspb.Int64Value{Value: *summary.PinnedServingTs}
		}

		// NOTE: The SitesAPI is the source of truth for this, but it's faster to return this static mapping here.
		region := s.kafkaClusterResolver.GetRegion(corpus.ClusterName())

		// TODO: This is not a valid way to determine if an epoch is active.
		activeEpochs[summary.Epoch] = true

		hosts := []*pb.HostStatus{}
		for hostname, status := range summary.HostStatuses {
			shards := []*pb.ShardStatus{}
			for _, shard := range status.Shards {
				shards = append(shards, &pb.ShardStatus{
					ShardId:       shard.Id,
					ServingTs:     shard.ServingTs,
					ServingOffset: shard.ServingOffset,
				})
			}
			hosts = append(hosts, &pb.HostStatus{
				Hostname:      hostname,
				EpochId:       status.EpochId,
				BinaryVersion: status.Sha,
				IndexVersion:  status.IndexVersion,
				Shards:        shards,
			})
		}

		statuses = append(statuses, &pb.CorpusStatus{
			BuildTs:                      summary.BuildTs.UnixMilli(),
			CorpusName:                   corpus.String(),
			ClusterName:                  corpus.ClusterName(),
			CorpusId:                     uint32(corpus),
			StalenessSeconds:             uint64(time.Since(summary.ServingTs).Seconds()),
			Indexing:                     summary.IsIndexing,
			EpochId:                      uint32(summary.Epoch),
			EpochMode:                    blackbird.ConvertEpochMode(summary.EpochMode),
			EpochDescription:             storeEpoch.Description,
			IngestMode:                   cluster.IngestMode.String(),
			Serving:                      summary.IsServing,
			InstantServing:               summary.IsInstantServing,
			FilterBlobs:                  summary.IsBlobFiltering,
			PinnedServingTs:              pinnedServingTs,
			CacheCluster:                 summary.CacheCluster,
			IndexVersion:                 summary.IndexVersion,
			BinaryVersion:                summary.BinaryVersion,
			ServingTs:                    summary.ServingTs.UnixMilli(),
			ServingOffset:                summary.ServingOffset,
			HealthScore:                  summary.HealthScore,
			MaxReposIndexed:              summary.MaxReposIndexed,
			Healing:                      summary.IsHealing,
			ShadowTrafficPercent:         summary.ShadowTrafficPercent,
			HealingRate:                  summary.HealingRate,
			EpochFeaturesOnlyEmbeddings:  epoch.EpochFeaturesOnlyEmbeddings.SupportedBy(summary.EpochMode),
			EpochFeaturesExternalContent: epoch.EpochFeaturesExternalContent.SupportedBy(summary.EpochMode),
			Region:                       region.String(),
			// ActiveEpoch:          true, // NB: This only applies to cache clusters
			Hosts:     hosts,
			NumShards: uint32(summary.NumShards),
		})
	}

	for i, cacheCluster := range routing.CacheClusterNames {
		// NB: Only cache-001 is supported in proxima
		if s.stamp != routing.Dotcom && i > 0 {
			break
		}
		summary, err := s.cacheClusters.Status(ctx, cacheCluster)
		if err != nil {
			return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("failed to get status for cache cluster %q", cacheCluster)), err)
		}

		epoch, err := s.store.GetEpoch(ctx, summary.Epoch)
		if err != nil {
			return nil, twirp.WrapError(twirp.InternalError("failed to get epoch"), err)
		}

		// NOTE: The SitesAPI is the source of truth for this, but it's faster to return this static mapping here.
		region := s.kafkaClusterResolver.GetRegion(cacheCluster)

		hosts := []*pb.HostStatus{}
		for hostname, status := range summary.HostStatuses {
			shards := []*pb.ShardStatus{}
			for _, s := range status.Shards {
				shards = append(shards, &pb.ShardStatus{
					ShardId:       s.Id,
					ServingTs:     s.ServingTs,
					ServingOffset: s.ServingOffset,
				})
			}
			hosts = append(hosts, &pb.HostStatus{
				Hostname:      hostname,
				EpochId:       status.EpochId,
				BinaryVersion: status.Sha,
				IndexVersion:  status.IndexVersion,
				Shards:        shards,
			})
		}

		_, activeEpoch := activeEpochs[summary.Epoch]

		statuses = append(statuses, &pb.CorpusStatus{
			BuildTs:          summary.BuildTs.UnixMilli(),
			CorpusName:       cacheCluster,
			ClusterName:      cacheCluster,
			CorpusId:         math.MaxUint32,
			StalenessSeconds: uint64(time.Since(summary.ServingTs).Seconds()),
			EpochId:          uint32(summary.Epoch),
			EpochMode:        blackbird.ConvertEpochMode(summary.EpochMode),
			EpochDescription: epoch.Description,
			IngestMode:       "n/a",
			IndexVersion:     summary.IndexVersion,
			BinaryVersion:    summary.BinaryVersion,
			ServingTs:        summary.ServingTs.UnixMilli(),
			ServingOffset:    summary.ServingOffset,
			HealthScore:      summary.HealthScore,
			ActiveEpoch:      activeEpoch,
			Hosts:            hosts,
			NumShards:        uint32(summary.NumShards),
			Region:           region.String(),

			// These fields are not relevant for cache clusters, and are explicitly set to false.
			Serving:        false,
			InstantServing: false,
			Indexing:       false,
			Healing:        false,
			FilterBlobs:    false,
		})
	}

	epochModes := []blackbird_entities.EpochMode{}
	for _, v := range blackbird_entities.EpochMode_value {
		epochMode := blackbird_entities.EpochMode(v)
		if epochMode == blackbird_entities.EpochMode_EPOCH_MODE_UNKNOWN {
			continue
		}
		epochModes = append(epochModes, epochMode)
	}

	return &pb.GetCorpusStatusResponse{DeployEnv: s.stamp.DeployEnv(), Statuses: statuses, EpochModes: epochModes}, nil
}

func (s *adminService) SetCorpusInstantServingState(ctx context.Context, req *pb.SetCorpusInstantServingStateRequest) (*pb.SetCorpusInstantServingStateResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		logging.Info(ctx, "invalid corpus name", kvp.String("corpus", req.Corpus))
		return nil, err
	}

	if err = s.searchClusters.SetCorpusIsInstantServing(corpus, req.InstantServing); err != nil {
		return nil, err
	}

	s.say(ctx, fmt.Sprintf("%s instant serving in %s", boolToState(req.InstantServing), corpus.NameWithCluster()))

	return &pb.SetCorpusInstantServingStateResponse{}, nil
}

func (s *adminService) SetCorpusIndexingState(ctx context.Context, req *pb.SetCorpusIndexingStateRequest) (*pb.SetCorpusIndexingStateResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		logging.Info(ctx, "invalid corpus name", kvp.String("corpus", req.Corpus))
		return nil, err
	}

	if err = s.searchClusters.SetCorpusIndexingPaused(corpus, !req.Indexing); err != nil {
		return nil, err
	}

	s.say(ctx, fmt.Sprintf("%s indexing in %s", boolToState(req.Indexing), corpus.NameWithCluster()))

	return &pb.SetCorpusIndexingStateResponse{}, err
}

func (s *adminService) SetCorpusHealingState(ctx context.Context, req *pb.SetCorpusHealingStateRequest) (*pb.SetCorpusHealingStateResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		logging.Info(ctx, "invalid corpus name", kvp.String("corpus", req.Corpus))
		return nil, err
	}

	if err = s.searchClusters.SetCorpusIsHealing(corpus, req.Healing); err != nil {
		return nil, err
	}

	s.say(ctx, fmt.Sprintf("%s healing in %s", boolToState(req.Healing), corpus.NameWithCluster()))
	return &pb.SetCorpusHealingStateResponse{}, err
}

func (s *adminService) SetCorpusShadowTraffic(ctx context.Context, req *pb.SetCorpusShadowTrafficRequest) (*pb.SetCorpusShadowTrafficResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		logging.Info(ctx, "invalid corpus name", kvp.String("corpus", req.Corpus))
		return nil, err
	}

	percent := max(0, min(1, req.Percent))

	if err = s.searchClusters.SetCorpusShadowTraffic(corpus, percent); err != nil {
		return nil, err
	}

	s.say(ctx, fmt.Sprintf("set shadow traffic to %d%% in %s", int(percent*100), corpus.NameWithCluster()))
	return &pb.SetCorpusShadowTrafficResponse{}, err
}

func (s *adminService) SetCorpusHealingRate(ctx context.Context, req *pb.SetCorpusHealingRateRequest) (*pb.SetCorpusHealingRateResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		logging.Info(ctx, "invalid corpus name", kvp.String("corpus", req.Corpus))
		return nil, err
	}

	rate := max(0, req.HealingRate)

	if err = s.searchClusters.SetCorpusHealingRate(corpus, rate); err != nil {
		return nil, err
	}

	s.say(ctx, fmt.Sprintf("set healing rate to %.1f docs/sec in %s", rate, corpus.NameWithCluster()))
	return &pb.SetCorpusHealingRateResponse{}, err
}

func (s *adminService) SetCorpusQueryState(ctx context.Context, req *pb.SetCorpusQueryStateRequest) (*pb.SetCorpusQueryStateResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		logging.Info(ctx, "invalid corpus name", kvp.String("corpus", req.Corpus))
		return nil, err
	}

	if !req.Serving && !req.Force {
		isAnotherClusterServing := false
		for _, c := range routing.GetOtherCorpora(corpus, s.stamp) {
			client := s.searchClusters.ClientForCorpus(c)
			if client.IsServing() {
				isAnotherClusterServing = true
			}
		}

		if !isAnotherClusterServing {
			s.say(ctx, fmt.Sprintf("cannot disable serving in %s because it is the only serving cluster", corpus.NameWithCluster()))
			return nil, twirp.InvalidArgumentError("serving", fmt.Sprintf("cannot disable serving in %s because it is the only serving cluster", corpus.NameWithCluster()))
		}
	}

	if err = s.searchClusters.SetCorpusIsServing(corpus, req.Serving); err != nil {
		return nil, err
	}
	s.say(ctx, fmt.Sprintf("%s serving in %s", boolToState(req.Serving), corpus.NameWithCluster()))

	return &pb.SetCorpusQueryStateResponse{}, err
}

func (s *adminService) SetServingCorpus(ctx context.Context, req *pb.SetServingCorpusRequest) (*pb.SetServingCorpusResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		logging.Info(ctx, "invalid corpus name", kvp.String("corpus", req.Corpus))
		return nil, err
	}

	// TODO: How do we make this atomic?
	if err = s.searchClusters.SetCorpusIsServing(corpus, true); err != nil {
		return nil, err
	}
	for _, otherCorpus := range routing.GetOtherCorpora(corpus, s.stamp) {
		if err = s.searchClusters.SetCorpusIsServing(otherCorpus, false); err != nil {
			logging.Error(ctx, "failed to disable serving for other corpus", kvp.String("corpus", otherCorpus.String()), kvp.Err(err))
		}
	}

	s.say(ctx, fmt.Sprintf("set %s as the serving corpus", corpus.NameWithCluster()))
	return &pb.SetServingCorpusResponse{}, err
}

func (s *adminService) BeginBackfillCorpus(ctx context.Context, req *pb.BeginBackfillCorpusRequest) (*pb.BeginBackfillCorpusResponse, error) {
	username := ong.GetUsername(ctx)
	if req.Reason == "" && username != "" {
		req.Reason = fmt.Sprintf("Backfill started by %s on %v via the admin ui", username, time.Now().UTC().Format("2006-01-02"))
	} else if req.Reason == "" {
		return nil, twirp.InvalidArgumentError("reason", "is required")
	}

	if req.NumShards == 0 {
		return nil, twirp.InvalidArgumentError("num_shards", "must be greater than zero")
	}

	go func(ctx context.Context) {
		defer utils.PanicLogger(ctx)
		start := time.Now()

		res, err := s.BackfillCorpus(ctx, &pb.BackfillCorpusRequest{
			Corpus:          req.Corpus,
			Reason:          req.Reason,
			MstCacheCluster: req.MstCacheCluster,
			EpochMode:       req.EpochMode,
			Bootstrap:       req.Bootstrap,
			NumShards:       req.NumShards,
		})
		if err != nil {
			logging.Error(ctx, "error backfilling", kvp.String("corpus", req.Corpus), kvp.Err(err))
			s.say(ctx, fmt.Sprintf("Error backfilling %s corpus after %s: %s", req.Corpus, time.Since(start), err.Error()))
			return
		}

		logging.Info(ctx, "backfill started successfully", kvp.String("corpus", req.Corpus))
		s.say(ctx, fmt.Sprintf(
			"Epoch %d (%s) backfill on the %s corpus started.",
			res.EpochId,
			req.EpochMode.String(),
			req.Corpus,
		))
	}(backgroundContext(ctx)) // new context is needed because the goroutine outlives the request
	return &pb.BeginBackfillCorpusResponse{}, nil
}

func (s *adminService) BackfillCorpus(ctx context.Context, req *pb.BackfillCorpusRequest) (*pb.BackfillCorpusResponse, error) {
	corpus, err := validateBackfillCorpusRequest(req)
	if err != nil {
		return nil, err
	}

	// 1a. Make sure another corpus is serving (NOTE: This does not check the health). When
	// bootstraping, this check is skipped.
	if !req.Bootstrap {
		anyServing := false
		for _, otherCorpus := range routing.GetOtherCorpora(corpus, s.stamp) {
			clusterStatus, err := s.searchClusters.Status(ctx, otherCorpus)
			if err != nil {
				return nil, twirp.WrapError(twirp.InternalError("unable to get corpus status"), err)
			}
			if clusterStatus.IsServing {
				anyServing = true
				break
			}
		}

		if !anyServing {
			return nil, twirp.NewError(
				twirp.FailedPrecondition,
				fmt.Sprintf("Can't backfill %s, because no other corpus is serving", corpus),
			)
		}
	}

	// 1b. Ensure a cache cluster is configured. If not, set the first one. https://github.com/github/blackbird/issues/6590
	if s.searchClusters.ClientForCorpus(corpus).CacheCluster() == "" {
		defaultCache := routing.CacheClusterNames[0]
		if err := s.searchClusters.SetCorpusCacheCluster(corpus, defaultCache); err != nil {
			return nil, twirp.WrapError(twirp.InternalError("failed to set cache cluster"), err)
		}
		logging.Info(ctx, "no cache cluster configured, set to default cache cluster", kvp.String("corpus", corpus.String()), kvp.String("cache_cluster", defaultCache))
		s.say(ctx, fmt.Sprintf("no cache cluster was configured for %s, set to %s", corpus, defaultCache))
	}

	// 2. Disable indexing for the corpus to backfill
	err = s.searchClusters.SetCorpusIndexingPaused(corpus, true)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("Failed to pause indexing on the %s corpus", corpus)), err)
	}

	// 3. Create a new epoch for the given corpus in blackbird_epochs
	epoch, err := s.store.CreateEpoch(ctx, corpus, req.Reason)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("Failed to create an epoch for the %s corpus", corpus)), err)
	}

	// 4. Enable indexing for the corpus to backfill
	err = s.searchClusters.SetCorpusIndexingPaused(corpus, false)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("Failed to unpause indexing on the %s corpus", corpus)), err)
	}

	// 5. Send switch epoch message and call backfill RPC
	bootstrapMsg := ""
	if req.Bootstrap {
		bootstrapMsg = "empty (bootstrap) "
		cacheCluster := s.searchClusters.ClientForCorpus(corpus).CacheCluster()
		if cacheCluster == "" {
			cacheCluster = routing.CacheClusterNames[0] // NB: cache-001 always exists
			_, err := s.SetCorpusCacheCluster(ctx, &pb.SetCorpusCacheClusterRequest{Corpus: corpus.String(), CacheCluster: cacheCluster})
			if err != nil {
				return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("Failed to set %q as the cache cluster for corpus=%s", cacheCluster, corpus)), err)
			}
		}
		s.say(ctx, fmt.Sprintf("if this is the very first backfill, please manually change the epoch of %s to %d", cacheCluster, epoch.EpochID))
	}
	s.say(ctx, fmt.Sprintf("started %sbackfill of %s: epoch %d (%s)", bootstrapMsg, epoch.Corpus.NameWithCluster(), epoch.EpochID, req.EpochMode))
	start := time.Now()
	err = s.backfiller.Publish(ctx, req, epoch)
	if err != nil {
		s.say(ctx, fmt.Sprintf("failed to publish messages for all requested repositories for corpus:%s, error:%s", corpus.String(), err.Error()))
		logging.Error(
			ctx,
			"failed to publish messages for all requested repositories",
			kvp.String("corpus", corpus.String()),
			kvp.Any("duration", time.Since(start)),
			kvp.Any("duration_ms", time.Since(start)),
			kvp.Err(err),
		)
		return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("Epoch created, but failed to publish backfill messages for the %s corpus", corpus)), err)
	}

	return &pb.BackfillCorpusResponse{EpochId: uint32(epoch.EpochID), NumRepositories: 0}, nil
}

func (s *adminService) SetCorpusFilterBlobs(ctx context.Context, req *pb.SetCorpusFilterBlobsRequest) (*pb.SetCorpusFilterBlobsResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		logging.Info(ctx, "invalid corpus name", kvp.String("corpus", req.Corpus))
		return nil, err
	}

	if err = s.searchClusters.SetCorpusBlobFiltering(corpus, req.FilterBlobs); err != nil {
		return nil, err
	}

	s.say(ctx, fmt.Sprintf("%s filter-blobs in %s", boolToState(req.FilterBlobs), corpus.NameWithCluster()))
	return &pb.SetCorpusFilterBlobsResponse{}, nil
}

func (s *adminService) SetCorpusCacheCluster(ctx context.Context, req *pb.SetCorpusCacheClusterRequest) (*pb.SetCorpusCacheClusterResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		logging.Info(ctx, "invalid corpus name", kvp.String("corpus", req.Corpus))
		return nil, err
	}

	if req.CacheCluster == "" {
		return nil, twirp.InvalidArgumentError("cache_cluster", "cannot be empty")
	}

	if err = s.searchClusters.SetCorpusCacheCluster(corpus, req.CacheCluster); err != nil {
		return nil, err
	}

	s.say(ctx, fmt.Sprintf("set cache cluster to %q in %s", req.CacheCluster, corpus.NameWithCluster()))
	return &pb.SetCorpusCacheClusterResponse{}, nil
}

func (s *adminService) SetEpochDescription(ctx context.Context, req *pb.SetEpochDescriptionRequest) (*pb.SetEpochDescriptionResponse, error) {
	if len(req.Description) > 100 {
		return nil, twirp.InvalidArgumentError("description", "too long")
	}
	err := s.store.UpdateEpochDescription(ctx, types.EpochID(req.EpochId), req.Description)
	if err != nil {
		return nil, err
	}
	return &pb.SetEpochDescriptionResponse{}, nil
}

func (s *adminService) GetSimilarRepos(ctx context.Context, req *pb.GetSimilarReposRequest) (*pb.GetSimilarReposResponse, error) {
	nwo, err := types.NewNWO(req.RepoNwo)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("RepoNwo not valid"), err)
	}

	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("Could not resolve corpus"), err)
	}

	cluster, err := blackbird.GetCluster(ctx, s.searchClusters, s.store, s.pager, s.gitClient, corpus)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("failed to get cluster"), err)
	}

	epochId := cluster.EpochID()
	if req.EpochId > 0 && uint32(epochId) != req.EpochId {
		return nil, twirp.InternalError(fmt.Sprintf("requested epoch_id=%d, but %s is serving epoch_id=%d", req.EpochId, corpus, epochId))
	}

	resp, err := cluster.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
		QuerySource: string(search.QuerySourceAdmin),
		QueryAst: &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_REGEX,
			Domain:          querypb.Domain_DOMAIN_NWO,
			ValueString:     fmt.Sprintf("^%s$", nwo),
			DivorToRetrieve: search.RetrieveAllDocs,
			DivorToScore:    search.DefaultDocsToScore,
		},
		EpochId:           uint32(epochId),
		SnapshotsToReturn: search.DefaultDocsLimit,
		ServingOffset:     int64(cluster.ServingOffset()),
	})
	if err != nil {
		logging.Error(ctx, "failed to search snapshot", kvp.Stringer("nwo", nwo), kvp.Err(err))
		return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("snapshot search failed for repo: %s", nwo)), err)
	}
	if len(resp.Snapshots) == 0 {
		return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("No snapshots found: %s", nwo)), err)
	}
	if len(resp.Snapshots) != 1 {
		return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("More than one snapshots found for: %s", nwo)), err)
	}

	geoFilter := resp.Snapshots[0].GeometricXorFilter
	resp, err = cluster.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
		QuerySource: string(search.QuerySourceAdmin),
		QueryAst: &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_QUALIFIER,
			Domain:          querypb.Domain_DOMAIN_SIMILAR,
			ValueString:     fmt.Sprintf("[%s]", base64.StdEncoding.EncodeToString(geoFilter)),
			DivorToRetrieve: search.RetrieveAllDocs,
			DivorToScore:    search.DefaultDocsToScore,
		},
		EpochId:           uint32(epochId),
		SnapshotsToReturn: req.NumSnapshots,
		ServingOffset:     int64(cluster.ServingOffset()),
	})
	if err != nil {
		logging.Error(ctx, "similarity search failed", kvp.Stringer("nwo", nwo), kvp.Err(err))
		return nil, twirp.WrapError(twirp.InternalError("sim-search failed"), err)
	}

	simRepos := []*pb.SimilarRepo{}
	for _, s := range resp.Snapshots {
		for _, e := range s.Entries {
			simRepos = append(simRepos, &pb.SimilarRepo{
				RepoNwo:    e.Nwo,
				IsPublic:   e.IsRepoPublic,
				RepoId:     e.RepoId,
				IsArchived: e.IsRepoArchived,
				RepoScore:  e.RepoScore,
			})
		}
	}

	return &pb.GetSimilarReposResponse{SimilarRepos: simRepos}, nil
}

func (s *adminService) GetRateLimitQuota(ctx context.Context, req *pb.GetRateLimitQuotaRequest) (*pb.GetRateLimitQuotaResponse, error) {
	user, err := s.githubClient.GetUser(ctx, req.Login)
	if err != nil {
		logging.Error(ctx, "failed to get user", kvp.Err(err))
		return nil, err
	}

	rates, err := quota.GetRates(ctx, s.quotaRateEstimator, uint64(user.GetID()))
	if err != nil {
		return nil, err
	}

	quotas := []*pb.Quota{}
	for b, r := range rates {
		quotas = append(quotas, &pb.Quota{
			Type:          b.Name(),
			ShortTermRate: r.ShortTermRate,
			LongTermRate:  r.LongTermRate,
			BannedSeconds: r.BanTime(b.ShortTermRateLimit(), b.LongTermRateLimit()),
		})
	}

	return &pb.GetRateLimitQuotaResponse{Quotas: quotas}, nil
}

func (s *adminService) ResetRateLimitQuota(ctx context.Context, req *pb.ResetRateLimitQuotaRequest) (*pb.ResetRateLimitQuotaResponse, error) {
	user, err := s.githubClient.GetUser(ctx, req.Login)
	if err != nil {
		return nil, err
	}

	if err := quota.ResetRates(ctx, s.quotaRateEstimator, uint64(user.GetID())); err != nil {
		return nil, err
	}

	s.say(ctx, fmt.Sprintf("reset rate limits for user %q", req.Login))
	return &pb.ResetRateLimitQuotaResponse{}, nil
}

func (s *adminService) CompactCorpus(ctx context.Context, req *pb.CompactCorpusRequest) (*pb.CompactCorpusResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		return nil, twirp.InvalidArgumentError("corpus", "is not valid")
	}

	if req.CompactionType == pb.CompactionType_COMPACTION_TYPE_INVALID {
		return nil, twirp.InvalidArgumentError("compaction_type", "is not valid")
	}

	corpusState, err := s.store.GetCorpusState(ctx, corpus)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("error getting corpus state"), err)
	}

	compationOperation := &blackbird_entities.CompactionOperation{}
	switch req.CompactionType {
	case pb.CompactionType_COMPACTION_TYPE_FULL:
		compationOperation.CompactionType = blackbird_entities.CompactionOperation_FULL
	case pb.CompactionType_COMPACTION_TYPE_INCREMENTAL:
		compationOperation.CompactionType = blackbird_entities.CompactionOperation_INCREMENTAL

		if req.IncrementalOptions != nil {
			compationOperation.IncrementalOptions = &blackbird_entities.IncrementalCompactionOptions{
				Radix:              req.IncrementalOptions.Radix,
				MinSubtreeByteSize: req.IncrementalOptions.MinSubtreeByteSize,
			}
		}
	default:
		return nil, twirp.InvalidArgumentError("compaction_type", "is an unexpected value")
	}

	msg, err := ingest.EncodeSnapshotMessage(
		routing.SnapshotTopic{
			Corpus:  corpus,
			EpochID: corpusState.EpochID,
		},
		&blackbird_pb.SnapshotTreeUpdate{
			EpochId:             uint32(corpusState.EpochID),
			CompactionOperation: compationOperation,
		},
	)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("failed to encode snapshot message"), err)
	}

	region := s.kafkaClusterResolver.GetRegion(corpus.ClusterName())
	partition, offset, err := s.snapshotProducers[region].SendMessage(msg)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("failed to send snapshot message"), err)
	}

	if partition != 0 {
		// This should never happen, but if it did, simply reporting the offset wouldn't be good enough, so let's panic.
		panic(fmt.Sprintf("snapshot partition was not 0 (got %d)", partition))
	}

	s.say(ctx, fmt.Sprintf("sent message to compact %s in epoch %d", corpus.NameWithCluster(), corpusState.EpochID))
	return &pb.CompactCorpusResponse{
		EpochId:       uint32(corpusState.EpochID),
		ServingOffset: uint64(offset),
	}, nil
}

func (s *adminService) PinCorpus(ctx context.Context, req *pb.PinCorpusRequest) (*pb.PinCorpusResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		return nil, twirp.InvalidArgumentError("corpus", "is not valid")
	}

	if req.ServingTs == 0 {
		return nil, twirp.InvalidArgumentError("serving_ts", "is required")
	}

	// Pause indexing, then pin the corpus.
	err = s.searchClusters.SetCorpusIndexingPaused(corpus, true)
	if err != nil {
		return nil, err
	}
	if err = s.searchClusters.SetPin(corpus, req.ServingTs); err != nil {
		return nil, err
	}

	s.say(ctx, fmt.Sprintf("pinned %s to %d", corpus.NameWithCluster(), req.ServingTs))

	return &pb.PinCorpusResponse{}, nil
}

func (s *adminService) UnpinCorpus(ctx context.Context, req *pb.UnpinCorpusRequest) (*pb.UnpinCorpusResponse, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		return nil, twirp.InvalidArgumentError("corpus", "is not valid")
	}

	// Unpin the corpus, then resume indexing
	// TODO: Do we always want to resume indexing?
	if err = s.searchClusters.UnsetPin(corpus); err != nil {
		return nil, err
	}
	err = s.searchClusters.SetCorpusIndexingPaused(corpus, false)
	if err != nil {
		return nil, err
	}

	s.say(ctx, fmt.Sprintf("unpinned %s", corpus.NameWithCluster()))

	return &pb.UnpinCorpusResponse{}, nil
}

func (s *adminService) ShardAssignments(ctx context.Context, req *pb.ShardAssignmentsRequest) (*pb.ShardAssignmentsResponse, error) {
	var cluster string
	var epoch types.EpochID
	if routing.IsCacheCluster(req.Corpus) {
		c, err := s.cacheClusters.ClientForCluster(req.Corpus)
		if err != nil {
			return nil, err
		}
		cluster = req.Corpus
		epoch = types.EpochID(c.EpochInfo().EpochID)
	} else {
		corpus, err := routing.CorpusFromString(req.Corpus)
		if err != nil {
			return nil, twirp.InvalidArgumentError("corpus", "is invalid")
		}
		c := s.searchClusters.ClientForCorpus(corpus)
		cluster = corpus.ClusterName()
		epoch = types.EpochID(c.EpochInfo().EpochID)
	}

	offset := sarama.OffsetNewest
	if req.Offset != nil {
		offset = req.Offset.Value
	}

	snap, err := s.assignmentsReader.ReadAtOffset(ctx, cluster, epoch, offset)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("failed to get assignment snapshots"), err)
	}

	version := snap.Msg.Version

	assignments := []*pb.HostAssignment{}
	for _, a := range snap.Msg.Hosts {
		assignedShards := []*pb.AssignedShards{}
		for _, shard := range a.Shards {
			assignedShards = append(assignedShards, &pb.AssignedShards{
				ShardId: shard.ShardId,
				State:   shard.Operation.String(),
			})
		}
		assignments = append(assignments,
			&pb.HostAssignment{
				Hostname:       a.HostName,
				AssignedShards: assignedShards,
			})
	}

	return &pb.ShardAssignmentsResponse{
		HostAssignments:  assignments,
		AlgorithmVersion: version.AlgoVersion,
		EpochId:          version.EpochId,
		IndexVersion:     version.IndexVersion,
		SnapshotTime:     timestamppb.New(time.UnixMilli(snap.Msg.LastKafkaTimestamp).UTC()),
		Offset:           snap.KafkaOffset,
		Cluster:          cluster,
	}, nil
}

func (s *adminService) ClusterHosts(ctx context.Context, req *pb.ClusterHostsRequest) (*pb.ClusterHostsResponse, error) {
	var cluster string
	if routing.IsCacheCluster(req.Corpus) {
		cluster = req.Corpus
	} else {
		corpus, err := routing.CorpusFromString(req.Corpus)
		if err != nil {
			return nil, twirp.InvalidArgumentError("corpus", "is invalid")
		}
		cluster = corpus.ClusterName()
	}

	params := map[string]string{
		"app":                "blackbird",
		"app_role":           cluster,
		"github:environment": s.stamp.DeployEnv(),
	}
	instances, err := s.sitesAPIClient.ListInstances(ctx, params)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	var region string
	var vmSize string
	var availabilityZone string
	hostnames := make([]string, 0, len(instances))
	for _, instance := range instances {
		hostnames = append(hostnames, instance.Hostname)
		// Hosts in a cluster will all have the same values for these attributes, so just grab them from the first one.
		if availabilityZone == "" {
			availabilityZone = instance.Attributes["github:availability_zone"]
		}
		if region == "" {
			region = instance.Attributes["github:region"]
		}
		if vmSize == "" {
			vmSize = instance.Attributes["azure:vm_size"]
		}
	}
	return &pb.ClusterHostsResponse{Hosts: hostnames, AvailabilityZone: availabilityZone, Region: region, VmSize: vmSize}, nil
}

func (s *adminService) ChangeEpoch(ctx context.Context, req *pb.ChangeEpochRequest) (*pb.ChangeEpochResponse, error) {
	var topic string
	topic, err := routing.ShardAssignmentTopicForCluster(req.Cluster)
	if err != nil {
		return nil, twirp.InvalidArgumentError("cluster", "invalid")
	}

	numShards := req.NumShards
	if numShards == 0 {
		return nil, twirp.InvalidArgumentError("num_shards", "must be greater than zero")
	}

	assignment := &blackbird_pb.ShardAssignment{
		Epoch: &blackbird_entities.ChangeEpoch{
			EpochId:   req.EpochId,
			EpochMode: req.EpochMode,
			NumShards: numShards,
		},
	}

	payload, err := hydro.NewDefaultEncoder().Encode(assignment, time.Now())
	if err != nil {
		return nil, twirp.InternalErrorf("failed to encode hydro message: %w", err)
	}

	region := s.kafkaClusterResolver.GetRegion(req.Cluster)
	part, off, err := s.snapshotProducers[region].SendMessage(
		&sarama.ProducerMessage{
			Topic: topic,
			Value: sarama.ByteEncoder(payload),
		},
	)
	if err != nil {
		return nil, twirp.InternalErrorf("failed to send ChangeEpoch message: %w", err)
	}

	logging.Info(
		ctx,
		"sent ChangeEpoch for dynamic shard assignment",
		kvp.Uint("epoch_id", uint(req.EpochId)),
		kvp.String("epoch_mode", req.EpochMode.String()),
		kvp.Uint("num_shards", uint(numShards)),
		kvp.Int64("partition", int64(part)),
		kvp.Int64("offset", off),
		kvp.String("topic", topic),
	)

	s.say(ctx, fmt.Sprintf("sent message to change epoch to %d (%s) with %d numShards on topic %q, partition %d, offset %d", req.EpochId, req.EpochMode, numShards, topic, part, off))
	go func(ctx context.Context) {
		defer utils.PanicLogger(ctx)

		start := time.Now()
		const timeout = 1 * time.Hour
		attempts, err := s.cacheClusters.WaitForEpoch(ctx, req.Cluster, types.EpochID(req.EpochId), timeout)
		if err != nil {
			s.say(ctx, fmt.Sprintf("%s did not start serving epoch %d after %s (checked %d times). error:%v", req.Cluster, req.EpochId, time.Since(start), attempts, err))
			return
		}

		s.say(ctx, fmt.Sprintf("%s is now serving epoch %d after %s (checked %d times)", req.Cluster, req.EpochId, time.Since(start), attempts))

	}(backgroundContext(ctx)) // new context is needed because the goroutine outlives the request

	return &pb.ChangeEpochResponse{}, nil
}

func (s *adminService) BranchEpoch(ctx context.Context, req *pb.BranchEpochRequest) (*pb.BranchEpochResponse, error) {
	if req.BranchTs == 0 {
		return nil, twirp.InvalidArgumentError("branch_ts", "is required")
	}
	now := time.Now()
	twoMonthsAgo := now.Add(-1460 * time.Hour)
	if req.BranchTs > now.UnixMilli() {
		return nil, twirp.InvalidArgumentError("branch_ts", "should not be in the future")
	}
	if req.BranchTs < twoMonthsAgo.UnixMilli() {
		return nil, twirp.InvalidArgumentError("branch_ts", "is too far in the past")
	}

	if req.NumShards == 0 {
		return nil, twirp.InvalidArgumentError("num_shards", "must be greater than zero")
	}

	if req.SourceEpoch == 0 {
		return nil, twirp.InvalidArgumentError("source_epoch", "is required")
	}

	sourceCorpus, err := routing.CorpusFromString(req.SourceCorpus)
	if err != nil {
		return nil, twirp.InvalidArgumentError("source corpus %s is not valid", req.SourceCorpus)
	}
	targetCorpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		return nil, twirp.InvalidArgument.Errorf("target corpus %s is not valid", req.Corpus)
	}

	sourceKafkaRegion := s.kafkaClusterResolver.GetRegion(sourceCorpus.ClusterName())
	targetKafkaRegion := s.kafkaClusterResolver.GetRegion(targetCorpus.ClusterName())
	if sourceKafkaRegion != targetKafkaRegion {
		return nil, twirp.NewErrorf(twirp.FailedPrecondition, "source corpus %s and target corpus %s must be in the same region, but source is in %v and target is in %v", req.SourceCorpus, req.Corpus, sourceKafkaRegion, targetKafkaRegion)
	}

	sourceTopic := &routing.SnapshotTopic{
		Corpus:  sourceCorpus,
		EpochID: types.EpochID(req.SourceEpoch),
	}
	sourceExists, err := kafka.IsSnapshotTopicPresent(s.blackbirdKafkaAdminProvider, sourceCorpus, sourceTopic)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("error checking snapshot topic existence"), err)
	}
	if !sourceExists {
		return nil, twirp.InternalErrorf("snapshot topic for source epoch: %d doesn't exist", req.SourceEpoch)
	}

	epoch, err := s.store.CreateEpoch(ctx, targetCorpus, req.Reason)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalErrorf("failed to create an epoch for the %s corpus", targetCorpus), err)
	}

	err = kafka.UpdateTopics(
		ctx,
		s.blackbirdKafkaAdminProvider,
		targetCorpus,
		epoch,
		s.topicConfig,
		int32(req.NumShards),
	)
	if err != nil {
		logging.Error(ctx, "error updating output topics", kvp.Err(err))
		return nil, twirp.WrapError(twirp.InternalError(fmt.Sprintf("failed to update epoch topics for the %s corpus epoch %d", targetCorpus, epoch.EpochID)), err)
	}

	err = s.backfiller.BootstrapEpochBranch(ctx, req, epoch)
	if err != nil {
		return nil, twirp.WrapError(twirp.InternalError("failed to bootstrap epoch branch"), err)
	}

	s.say(ctx, fmt.Sprintf(
		"Epoch branch initiated on cluster: %s using source_epoch: %d @ branch_ts: %d",
		targetCorpus.NameWithCluster(),
		req.SourceEpoch,
		req.BranchTs,
	))

	err = s.store.UpdateEpochDescription(ctx, types.EpochID(epoch.EpochID), fmt.Sprintf("Creating a new branch from: %s(%d)", sourceCorpus.ClusterName(), req.SourceEpoch))
	if err != nil {
		logging.Error(ctx, "error updating epoch description", kvp.Err(err))
		return nil, twirp.WrapError(twirp.InternalError("error updating epoch description"), err)
	}

	go func(ctx context.Context) {
		defer utils.PanicLogger(ctx)

		start := time.Now()
		const timeout = 5 * time.Hour
		attempts, err := s.searchClusters.WaitForEpochToServe(ctx, targetCorpus, types.EpochID(epoch.EpochID), timeout)
		duration := time.Since(start)

		if err != nil {
			s.say(
				ctx,
				fmt.Sprintf(
					"corpus %s did not start serving epoch %d after %s (checked %d times), error: %v",
					targetCorpus,
					epoch.EpochID,
					duration,
					attempts,
					err,
				))
			return
		}

		s.say(ctx, fmt.Sprintf("%s is now serving epoch %d after %s (checked %d times). Transitioning ingest to backfill catch up mode", targetCorpus.String(), epoch.EpochID, duration, attempts))
		kafkaInfos, err := getSourceKafkaInfos(ctx, s.indexerClusters, epoch.Corpus)
		if err != nil {
			s.say(ctx, fmt.Sprintf("branch failed, corpus: %s, could not extract offsets from source kafka info: %v. ", targetCorpus.NameWithCluster(), err))
			return
		}

		err = s.createConsumerGroup(ctx, convertSourceKafkaInfoToConsumerGroupOffsets(kafkaInfos), targetCorpus, epoch.EpochID)
		if err != nil {
			s.say(ctx, fmt.Sprintf("branch failed, corpus: %s, could not create consumer group: %v. ", targetCorpus.NameWithCluster(), err))
			return
		}

		s.say(ctx, fmt.Sprintf(
			"Epoch branch created on cluster: %s using source_epoch: %d. Ingest is unblocked and backfill catchup is initiated. This cluster no longer needs blackbird-mw to be locked.",
			targetCorpus.NameWithCluster(),
			req.SourceEpoch,
		))

		err = s.store.UpdateEpochDescription(ctx, types.EpochID(epoch.EpochID), fmt.Sprintf("Branched from: %s(%d) on %v", sourceCorpus.ClusterName(), req.SourceEpoch, time.Now().UTC().Format("2006-01-02")))
		if err != nil {
			logging.Error(ctx, "error updating epoch description")
		}
	}(backgroundContext(ctx))

	return &pb.BranchEpochResponse{
		EpochId: uint32(epoch.EpochID),
	}, nil
}

func (s *adminService) GetDeployAheadBehind(ctx context.Context, req *pb.GetDeployAheadBehindRequest) (*pb.GetDeployAheadBehindResponse, error) {
	const maxSHAs = 50
	if len(req.CommitShas) > maxSHAs {
		return nil, twirp.InvalidArgumentError("CommitShas", fmt.Sprintf("cannot pass more than %d commit shas", maxSHAs))
	}

	const blackbirdRepoID = types.RepoID(253831084)
	var blackbirdRepo = types.NWOFromString("github/blackbird")

	wg := sync.WaitGroup{}
	errors := make(chan error, 1+len(req.CommitShas))

	// Fetch the HEAD of the default branch
	var ref *gitaccess.RefTip
	wg.Add(1)
	go func() {
		defer utils.PanicLogger(ctx)
		defer wg.Done()

		var err error
		ref, err = s.gitClient.GetDefaultRef(ctx, blackbirdRepoID)
		if err != nil {
			logging.Error(ctx, "failed to get default ref", kvp.Err(err))
		}
		errors <- err
	}()

	// TODO: Return ahead/behind information.
	// See https://docs.github.com/en/rest/commits/commits?apiVersion=2022-11-28#list-pull-requests-associated-with-a-commit

	// Fetch the PR (if any) for each commit sha
	statuses := make([]*pb.DeployedShaStatus, len(req.CommitShas))
	mutex := sync.Mutex{}
	for i, sha := range req.CommitShas {
		if sha == "" {
			mutex.Lock()
			statuses[i] = &pb.DeployedShaStatus{CommitSha: sha}
			mutex.Unlock()
			continue
		}

		wg.Add(1)
		go func(idx int) {
			defer utils.PanicLogger(ctx)
			defer wg.Done()

			pulls, err := s.githubClient.GetPullsForCommit(ctx, blackbirdRepo, sha)
			if err != nil {
				logging.Error(ctx, "failed to get pull requests for commit", kvp.String("sha", sha), kvp.Err(err))
			} else {
				if len(pulls) == 0 {
					mutex.Lock()
					statuses[idx] = &pb.DeployedShaStatus{CommitSha: sha}
					mutex.Unlock()
				} else {
					pull := pulls[0]
					pr := &pb.DeployedPR{
						HtmlUrl: pull.GetHTMLURL(),
						Number:  uint32(pull.GetNumber()),
						Title:   pull.GetTitle(),
						Author:  github.ParseUserLogin(pull.GetUser()),
						Ref:     pull.GetHead().GetRef(),
					}
					mutex.Lock()
					statuses[idx] = &pb.DeployedShaStatus{CommitSha: sha, Pr: pr}
					mutex.Unlock()
				}
			}
			errors <- err
		}(i)
	}

	wg.Wait()
	close(errors)

	var anyErr error
	for err := range errors {
		// NB: must drain the errors channel to know that we're done
		if err != nil && anyErr == nil {
			anyErr = err
		}
	}

	if anyErr != nil {
		return nil, twirp.InternalErrorWith(anyErr)
	}

	return &pb.GetDeployAheadBehindResponse{
		HeadSha:  ref.CommitOID.String(),
		Statuses: statuses,
	}, nil
}

// Get the source kafka info from every shard.
//
// This function continues to retry if any shard returns with an empty source
// kafka info.
func getSourceKafkaInfos(ctx context.Context, indexClusters *routing.IndexerClusters, corpus routing.Corpus) ([]map[string]*servingpb.KafkaInfo, error) {
	out := []map[string]*servingpb.KafkaInfo{}
	op := func() error {
		kafkaInfos := []map[string]*servingpb.KafkaInfo{}
		s, err := indexClusters.Status(ctx, corpus)
		if err != nil {
			return err
		}
		for _, status := range s.HostStatuses {
			for _, shard := range status.Shards {
				kafkaInfo := shard.GetSourceKafkaInfo()
				if kafkaInfo == nil {
					logging.Error(ctx, "shard returned no source kafka info", kvp.Int("shard_id", int(shard.Id)))
					return fmt.Errorf("shard %d returned no source kafka info", shard.Id)
				}

				kafkaInfos = append(kafkaInfos, kafkaInfo)
			}
		}
		out = kafkaInfos
		return nil
	}

	err := backoff.Retry(op, retry.Forever(ctx))
	if err != nil {
		return nil, err
	}

	return out, nil
}

// convertSourceKafkaInfo converts the a list of source kafka info to a map of
// topic to partition to offset (including MarkedKafkaOffset conversion).
//
// The resulting map only contains the offsets for the incremental and onboard
// source topics. We only keep the minimum offset for each topic/partition pair.
func convertSourceKafkaInfoToConsumerGroupOffsets(kafkaInfos []map[string]*servingpb.KafkaInfo) map[string]map[int32]int64 {
	consumerGroupOffsets := make(map[string]map[int32]int64)
	for _, kafkaInfo := range kafkaInfos {
		for topic, ki := range kafkaInfo {
			if topic != routing.IncrementalSourceTopic && topic != routing.OnboardSourceTopic {
				continue
			}

			if consumerGroupOffsets[topic] == nil {
				consumerGroupOffsets[topic] = make(map[int32]int64)
			}

			for partition, po := range ki.GetPartitions() {
				mko := kafka.NewMarkedKafkaOffsetFromRaw(po.Offset)
				if offset, ok := consumerGroupOffsets[topic][partition]; !ok || offset > mko.Get() {
					consumerGroupOffsets[topic][partition] = mko.Get()
				}
			}
		}
	}

	return consumerGroupOffsets
}

func fetchIngests(s *adminService, ctx context.Context, corpora []routing.Corpus, repoID types.RepoID) ([]*pb.RepoIngest, []*pb.RepoIngest, error) {
	indexerIngests := []*pb.RepoIngest{}
	servingIngests := []*pb.RepoIngest{}
	for _, corpus := range corpora {
		corpusState, err := s.store.GetCorpusState(ctx, corpus)
		if err != nil {
			return nil, nil, err
		}

		if entries, err := s.getSnapshotsForRepoFromIndex(ctx, corpusState, repoID); err != nil {
			logging.Error(ctx, "failed to get snapshots for corpus from index", kvp.Err(err), kvp.String("corpus", corpus.String()))
		} else {
			indexerIngests = append(indexerIngests, &pb.RepoIngest{
				Corpus:          corpusState.Corpus.String(),
				EpochId:         uint32(corpusState.EpochID),
				SnapshotEntries: entries,
			})
		}

		if entries, err := s.getSnapshotsForRepoFromServing(ctx, corpusState, repoID); err != nil {
			logging.Error(ctx, "failed to get snapshots for corpus from serving cluster", kvp.Err(err), kvp.String("corpus", corpus.String()))
		} else {
			servingIngests = append(servingIngests, &pb.RepoIngest{
				Corpus:          corpusState.Corpus.String(),
				EpochId:         uint32(corpusState.EpochID),
				SnapshotEntries: entries,
			})
		}
	}
	return indexerIngests, servingIngests, nil
}

func (s *adminService) createConsumerGroup(ctx context.Context, cgo map[string]map[int32]int64, corpus routing.Corpus, epochID types.EpochID) error {
	for topic, offsets := range cgo {
		if err := s.cgManager.Create(ctx, topic, corpus.ConsumerGroup(epochID), offsets); err != nil {
			return err
		}
	}

	return nil
}

// get the indexed head OID from the serving index (NOT the indexer). We use the
// serving index because it needs to be searchable to probe.
func (s *adminService) getHeadOID(ctx context.Context, cluster *blackbird.Cluster, repo *db.Repository) (gitaccess.ObjectID, error) {
	corpusState, err := s.store.GetCorpusState(ctx, cluster.Corpus())
	if err != nil {
		return gitaccess.NullObjectID, err
	}

	res, err := s.searchSnapshots(ctx, corpusState, repo.RepoID)
	if err != nil {
		return gitaccess.NullObjectID, err
	}
	if len(res.Snapshots) != 1 {
		return gitaccess.NullObjectID, twirp.InvalidArgumentError("repo", "expected 1 snapshot for this repo")
	}

	if len(res.Snapshots[0].Entries) != 1 {
		return gitaccess.NullObjectID, twirp.InvalidArgumentError("repo", "expected 1 snapshot entry for this repo")
	}

	return gitaccess.NewObjectIDFromBytes(res.Snapshots[0].Entries[0].CommitSha), nil
}

func (s *adminService) getRepoByNWO(ctx context.Context, repoNWO string) (*db.Repository, error) {
	nwo, err := types.NewNWO(repoNWO)
	if err != nil {
		return nil, err
	}

	repo, err := s.store.GetRepositoryByNWO(ctx, nwo)
	if err != nil {
		return nil, err
	}

	// no active repo? Get the first deleted one
	if repo == nil {
		repo, err = s.store.GetFirstRepository(ctx, repofilter.NWO(nwo))
		if err != nil {
			return nil, err
		}
	}

	return repo, nil
}

func (s *adminService) getRepoByID(ctx context.Context, id uint32) (*db.Repository, error) {
	repo, err := s.store.GetFirstRepository(ctx, repofilter.ID(types.RepoID(id)))
	if err != nil {
		return nil, err
	}

	return repo, nil
}

func (s *adminService) say(ctx context.Context, msg string) {
	if actor := ong.GetUsername(ctx); actor != "" {
		msg = fmt.Sprintf("@%s %s", actor, msg)
	}
	// TODO: Make chat.Say part of the context like logger and do this in once place.
	chat.Say(ctx, s.chatClient, chat.BlackbirdOpsChannel, fmt.Sprintf("[%s] %s", s.stamp, msg))
}

func (s *adminService) searchSnapshots(ctx context.Context, corpusState *db.CorpusState, repoID types.RepoID) (*snapshotpb.SearchSnapshotsResponse, error) {
	cluster, err := blackbird.GetCluster(ctx, s.searchClusters, s.store, s.pager, s.gitClient, corpusState.Corpus)
	if err != nil {
		return nil, err
	}

	return cluster.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
		QuerySource: string(search.QuerySourceAdmin),
		QueryAst: &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_QUALIFIER,
			Domain:          querypb.Domain_DOMAIN_REPO_ID,
			ValueInt:        []int32{repoID.ToInt32()},
			DivorToRetrieve: search.RetrieveAllDocs,
			DivorToScore:    1,
		},
		TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
		ServingOffset:     int64(cluster.ServingOffset()),
		EpochId:           uint32(corpusState.EpochID),
		SnapshotsToReturn: 1,
	})
}

func (s *adminService) getSnapshotsForRepoFromIndex(ctx context.Context, corpusState *db.CorpusState, repoID types.RepoID) ([]*pb.SnapshotEntry, error) {
	ctx, cancel := context.WithTimeout(ctx, 1*time.Second)
	defer cancel()

	host, err := s.indexerClusters.GetCluster(corpusState.Corpus).GetHost()
	if err != nil {
		return nil, fmt.Errorf("could not get host for indexer snapshot query: %w", err)
	}

	req := &snapshotpb.SearchSnapshotsRequest{
		QuerySource: string(search.QuerySourceAdmin),
		QueryAst: &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_QUALIFIER,
			Domain:          querypb.Domain_DOMAIN_REPO_ID,
			ValueInt:        []int32{repoID.ToInt32()},
			DivorToRetrieve: search.RetrieveAllDocs,
			DivorToScore:    1,
		},
		EpochId:           uint32(corpusState.EpochID),
		ServingOffset:     int64(host.ServingOffset),
		SnapshotsToReturn: 1,
		ShardId:           host.ShardID,
	}

	res, err := host.SearchSnapshots(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("search snapshots failed: %w", err)
	}

	return convertSnapshots(res), nil
}

func (s *adminService) getSnapshotsForRepoFromServing(ctx context.Context, corpusState *db.CorpusState, repoID types.RepoID) ([]*pb.SnapshotEntry, error) {
	res, err := s.searchSnapshots(ctx, corpusState, repoID)
	if err != nil {
		return nil, err
	}

	return convertSnapshots(res), nil
}

func convertSnapshots(res *snapshotpb.SearchSnapshotsResponse) []*pb.SnapshotEntry {
	out := []*pb.SnapshotEntry{}
	for _, snapshot := range res.Snapshots {
		for _, entry := range snapshot.Entries {
			oid := gitaccess.NewObjectIDFromBytes(entry.CommitSha)
			for _, version := range entry.Versions {
				snap := &pb.SnapshotEntry{
					EntryId:        entry.EntryId,
					HeadOid:        oid.String(),
					Experiments:    entry.Experiments,
					RepoId:         entry.RepoId,
					OwnerId:        entry.OwnerId,
					NetworkId:      entry.NetworkId,
					Nwo:            entry.Nwo,
					IsRepoPublic:   entry.IsRepoPublic,
					IsRepoArchived: entry.IsRepoArchived,
					RepoScore:      entry.RepoScore,
					RefName:        entry.RefName,
					EntryState:     version.State.String(),
					ServingOffset:  version.OffsetId,
					PermanentError: entry.PermanentError,
					BusinessId:     entry.BusinessId,
					BusinessSlug:   entry.BusinessSlug,
				}
				out = append(out, snap)
			}
		}
	}

	return out
}

func boolToState(c bool) string {
	if c {
		return "enabled"
	} else {
		return "disabled"
	}
}

func validateBackfillCorpusRequest(req *pb.BackfillCorpusRequest) (routing.Corpus, error) {
	corpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		return -1, twirp.InvalidArgumentError("corpus", fmt.Sprintf("%q is not a valid corpus", req.Corpus))
	}

	if !req.Bootstrap {
		mstCacheCluster := req.MstCacheCluster
		if mstCacheCluster == "" {
			return -1, twirp.InvalidArgumentError("mst_cache_cluster", "is required for backfill")
		}

		if !routing.IsCacheCluster(mstCacheCluster) {
			return -1, twirp.InvalidArgumentError("mst_cache_cluster", "is invalid")
		}
	}

	return corpus, nil
}

// create a new context suitable for running in a goroutine.
func backgroundContext(ctx context.Context) context.Context {
	username := ong.GetUsername(ctx)
	ctx = background.Context(ctx)
	if username != "" {
		ctx = ong.SetUsername(ctx, username)
	}
	return ctx
}

func pbTimestamp(nt sql.NullTime) *timestamppb.Timestamp {
	var ts *timestamppb.Timestamp
	if nt.Valid {
		ts = timestamppb.New(nt.Time)
	}

	return ts
}
