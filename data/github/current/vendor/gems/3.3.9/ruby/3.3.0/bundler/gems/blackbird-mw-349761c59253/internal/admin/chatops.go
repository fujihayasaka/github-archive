package admin

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	chatops "github.com/github/go-chatops/v2"
	"github.com/github/go-chatops/v2/security"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/go-chi/chi/v5"
	"github.com/pkg/errors"
	"golang.org/x/text/language"
	"golang.org/x/text/message"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/reflect/protoreflect"

	"github.com/github/blackbird-mw/internal/background"
	"github.com/github/blackbird-mw/internal/chat"
	"github.com/github/blackbird-mw/internal/env"
	pb "github.com/github/blackbird-mw/internal/proto/admin/v1"
	"github.com/github/blackbird-mw/internal/utils"
)

type ChatopsServer struct {
	cfg        env.Config
	adminAPI   pb.AdminAPI
	chatClient chat.Client
}

func NewChatopsService(cfg env.Config, adminAPI pb.AdminAPI, chatClient chat.Client) *ChatopsServer {
	return &ChatopsServer{cfg, adminAPI, chatClient}
}

func (s *ChatopsServer) RegisterCommands(r chi.Router) {
	ns := chatops.NewNamespace("blackbird")
	ns.Help = "Commands for managing blackbird code search"

	ch, err := chatops.NewHandler(ns, s.cfg.GetChatopsBaseURL())
	if err != nil {
		panic(fmt.Errorf("chatops: failed to create handler: %w", err))
	}

	pem := s.cfg.GetChatopsPublicKey()

	ch.AddBot(pem)
	ch.Setup(r)

	securityConfig, err := security.LoadSecurityConfig("/config/security-config.yaml")
	if err != nil {
		panic(fmt.Errorf("chatops: failed to load security config: %w", err))
	}

	// .ldap group blackbird
	ldapClient, err := security.InitializeLDAPClient("/config/ldap-config.yaml", s.cfg.GetChatopsLDAPPassword())
	if err != nil {
		panic(fmt.Errorf("chatops: failed to initialize LDAP client: %w", err))
	}

	validator := &security.Validator{
		Config: *securityConfig,
		LDAP:   ldapClient,
	}

	s.register(ns,
		"ping",
		"ping - Check if blackbird chatops is alive.",
		`ping`,
		s.chatPingHandler)

	s.register(ns,
		"status",
		"status [<owner>[/<repo>]] [--corpus <corpus>] [--probe] [--path <path>] - Check status of all clusters, a user, or a repo. Pass --probe when checking the status of a repo to also kick off a completeness prober job.",
		// Regexes are processed by the slack client (not this app) and passed via cmd.Params
		`status(\s+(?<owner>[^\s/]+)(\/(?<repo>[^\s/]+))?)?`,
		s.chatStatusHandler)

	s.register(ns,
		"corpus",
		"(enable|disable) (indexing|serving|blob-filtering) <corpus> [--force] - Configure a corpus.",
		// Regexes are processed by the slack client (not this app) and passed via cmd.Params
		`(?<cmd>(enable|disable))(\s+(?<target>(indexing|serving|blob-filtering)))?\s+(?<corpus>[^\s]+)`,
		security.WrapWithAuthorization(validator, nil, s.chatConfigureCorpus))

	s.register(ns,
		"pin",
		"<corpus> --ts <ts> - Pin a corpus and pin to a specific time stamp.",
		// Regexes are processed by the slack client (not this app) and passed via cmd.Params
		`pin\s+(?<corpus>[^\s]+)`,
		security.WrapWithAuthorization(validator, nil, s.chatPin))

	s.register(ns,
		"upin",
		"<corpus> - Unpin a corpus",
		// Regexes are processed by the slack client (not this app) and passed via cmd.Params
		`upin\s+(?<corpus>[^\s]+)`,
		security.WrapWithAuthorization(validator, nil, s.chatUnpin))

	s.register(ns,
		"set-cache-cluster",
		"<corpus> --cluster <cluster> - Set the cache cluster for a corpus.",
		// Regexes are processed by the slack client (not this app) and passed via cmd.Params
		`set-cache-cluster\s+(?<corpus>[^\s]+)`,
		security.WrapWithAuthorization(validator, nil, s.chatSetCacheCluster))

	s.register(ns,
		"backfill",
		"backfill <corpus> [--reason <reason>] [--limit <n>] [--epoch <n>] [--num-masks <n>] [--query <q>] - Backfill a corpus.",
		// Regexes are processed by the slack client (not this app) and passed via cmd.Params
		`backfill\s+(?<corpus>[^\s]+)`,
		security.WrapWithAuthorization(validator, nil, s.chatBackfill))

	s.register(ns,
		"index",
		"index <owner>/<repo> [--reindex] [--corpus <corpus>] - Index a repository.",
		// Regexes are processed by the slack client (not this app) and passed via cmd.Params
		`index\s+(?<owner>[^\s/]+)(\/(?<repo>[^\s/]+))`,
		security.WrapWithAuthorization(validator, nil, s.chatIndexRepo))

	s.register(ns,
		"sim-search",
		"sim-search <corpus> <repo> [--epoch <epoch_id>] [--num-snapshots <num_snapshots>] [--entries-per-snapshot <entries_per_snapshot>] - Performs a sim search for the provided repo and returns repos similar to it.",
		`sim-search\s+(?<corpus>[^\s]+)\s+(?<repo>[^\s]+)`,
		security.WrapWithAuthorization(validator, nil, s.simSearch))

	s.register(ns,
		"compute-mst",
		"compute-mst [--limit <n>] [--epoch <n>] [--num-masks <n>] [--query <q>] - Create a minimum spanning tree from repository similarities and report some stats about it",
		`compute-mst`,
		security.WrapWithAuthorization(validator, nil, s.chatComputeMST))

	s.register(ns,
		"compact",
		"compact [--corpus <corpus>] [--type <type>]",
		`compact`,
		security.WrapWithAuthorization(validator, nil, s.compact))

	s.register(ns,
		"reset-quota",
		"reset-quota <login> - Resets a user's rate limit quota.",
		`reset-quota\s+(?<login>[^\s/]+)`,
		security.WrapWithAuthorization(validator, nil, s.resetQuota))

	s.register(ns,
		"change-epoch",
		"change-epoch <epoch> --cluster <cluster> - Triggers change epoch for the requested cluster cluster.",
		`change-epoch\s+(?<epoch>[^\s]+)`,
		security.WrapWithAuthorization(validator, nil, s.changeEpoch))
}

func (s *ChatopsServer) chatPingHandler(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	return &chatops.CommandResponse{
		Result: fmt.Sprintf("pong, %s!", cmd.User),
	}, nil
}

func (s *ChatopsServer) chatStatusHandler(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	ownerName, okOwner := cmd.Params["owner"]
	repoName, okRepo := cmd.Params["repo"]
	corpus := cmd.Params["corpus"]

	if okOwner && okRepo {
		nwo := ownerName + "/" + repoName
		resp, err := s.adminAPI.GetRepoStatus(ctx, &pb.GetRepoStatusRequest{
			RepoNwo: nwo,
			Corpus:  corpus,
		})
		if err != nil {
			return nil, errors.WithMessage(err, "unable to get repo status")
		}

		if _, ok := cmd.Params["probe"]; ok {
			s.respond(ctx, cmd, fmt.Sprintf("Kicking off completeness probe in the background for %s on the %s corpus...", nwo, corpus))

			bgCtx := background.Context(ctx) // new context is needed because the goroutine outlives the request
			go func() {
				defer utils.PanicLogger(bgCtx)

				res, err := s.adminAPI.ProbeRepo(bgCtx, &pb.ProbeRepoRequest{Corpus: corpus, RepoNwo: nwo, Path: cmd.Params["path"]})
				if err != nil {
					s.respond(bgCtx, cmd, fmt.Sprintf("failed to probe %s: %s", nwo, err.Error()))
				} else {
					msg := []string{fmt.Sprintf("Finished probing %s: %d documents verified, %d extra, %d not indexed (downsampled with %d trailing zero)", nwo, res.Verified, len(res.Extra), len(res.Missing), res.NumTrailingZeros)}
					if resp.IsPublic {
						if len(res.Extra) > 0 {
							msg = append(msg, "⚠️ blackbird returned results not found in the git repo ⚠️")
							msg = append(msg, "```")
							msg = append(msg, res.Extra...)
							msg = append(msg, "```")
						}

						if len(res.Missing) > 0 {
							msg = append(msg, "These blobs were not indexed:")
							msg = append(msg, "```")
							msg = append(msg, res.Missing...)
							msg = append(msg, "```")
						}
					} else if len(res.Extra) > 0 || len(res.Missing) > 0 {
						msg = append(msg, "_This repo is private: extra and missing path details hidden. See splunk logs instead._")
					}

					s.respond(bgCtx, cmd, strings.Join(msg, "\n"))
				}
			}()
		}
		return toCommandResponse(resp)
	} else if okOwner {
		res, err := s.adminAPI.GetRateLimitQuota(ctx, &pb.GetRateLimitQuotaRequest{Login: ownerName})
		if err != nil {
			return nil, errors.WithMessage(err, "unable to get quota")
		}
		return toCommandResponse(res)
	}

	resp, err := s.adminAPI.GetCorpusStatus(ctx, &pb.GetCorpusStatusRequest{})
	if err != nil {
		return nil, errors.WithMessage(err, "unable to get corpora status")
	}

	return toCommandResponse(resp)
}

func (s *ChatopsServer) chatPin(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	corpus := strings.ToLower(cmd.Params["corpus"])
	ts, err := parseInt64(cmd, "ts")
	if err != nil {
		return nil, errors.WithMessage(err, "failed to parse ts")
	}
	resp, err := s.adminAPI.PinCorpus(ctx, &pb.PinCorpusRequest{Corpus: corpus, ServingTs: ts})
	if err != nil {
		return nil, errors.WithMessage(err, "unable to pin corpus")
	}
	return toCommandResponse(resp)
}

func (s *ChatopsServer) chatUnpin(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	corpus := strings.ToLower(cmd.Params["corpus"])
	resp, err := s.adminAPI.UnpinCorpus(ctx, &pb.UnpinCorpusRequest{Corpus: corpus})
	if err != nil {
		return nil, errors.WithMessage(err, "unable to unpin corpus")
	}
	return toCommandResponse(resp)
}

func (s *ChatopsServer) chatSetCacheCluster(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	corpus := strings.ToLower(cmd.Params["corpus"])
	cluster := strings.ToLower(cmd.Params["cluster"])
	resp, err := s.adminAPI.SetCorpusCacheCluster(ctx, &pb.SetCorpusCacheClusterRequest{Corpus: corpus, CacheCluster: cluster})
	if err != nil {
		return nil, errors.WithMessage(err, "unable to set cache cluster")
	}
	return toCommandResponse(resp)
}

func (s *ChatopsServer) chatBackfill(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	req, err := newBackfillRequest(cmd)
	if err != nil {
		return nil, err
	}

	// Make sure that another corpus is enabled for serving
	if _, err := s.ensureAnotherServingCorpusAvailable(ctx, cmd, "This is the only corpus enabled for serving, cannot backfill."); err != nil {
		return nil, err
	}

	// Fire and forget goroutine that will update via the chat client (unless this pod dies)
	// TODO: Real background worker (if this doesn't cut it)
	ctx = background.Context(ctx) // new context is needed because the goroutine outlives the request
	go func() {
		defer utils.PanicLogger(ctx)
		start := time.Now()

		res, err := s.adminAPI.BackfillCorpus(ctx, req)
		if err != nil {
			logging.Error(ctx, "error backfilling", kvp.String("corpus", req.Corpus), kvp.Err(err))
			msg := fmt.Sprintf("Error backfilling %s corpus after %s: %s", req.Corpus, time.Since(start), err.Error())
			s.respond(ctx, cmd, msg)
			return
		}

		msg := fmt.Sprintf(
			"Epoch %d backfill on the %s corpus started. Published %s repositories to be backfilled in %s",
			res.EpochId,
			req.Corpus,
			message.NewPrinter(language.English).Sprintf("%d", res.NumRepositories),
			formatDuration(time.Since(start)),
		)

		s.respond(ctx, cmd, msg)
	}()

	return &chatops.CommandResponse{Result: fmt.Sprintf("Backfill for %s enqueued. Updates will be posted asynchronously.", req.Corpus)}, nil
}

func (s *ChatopsServer) changeEpoch(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	var epoch uint32
	if val, ok := cmd.Params["epoch"]; ok {
		e, err := strconv.ParseUint(val, 10, 32)
		if err != nil {
			return nil, errors.Wrapf(err, "Error parsing epoch %s", cmd.Params["epoch"])
		}

		epoch = uint32(e)
	}

	var cluster string
	if val, ok := cmd.Params["cluster"]; ok {
		cluster = val
	} else {
		return nil, errors.New("Please specify a cluster name")
	}

	_, err := s.adminAPI.ChangeEpoch(ctx, &pb.ChangeEpochRequest{EpochId: epoch, Cluster: cluster})
	if err != nil {
		return nil, err
	}

	return &chatops.CommandResponse{Result: fmt.Sprintf("Requested epoch change to %d for the %s cluster", epoch, cluster)}, nil
}

func (s *ChatopsServer) chatConfigureCorpus(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	command := strings.ToLower(cmd.Params["cmd"])
	target := strings.ToLower(cmd.Params["target"])
	corpus := strings.ToLower(cmd.Params["corpus"])
	errMsg := errors.New("Didn't understand the command. Try .blackbird (enable|disable) (serving|indexing|healing|blob-filtering) blue")

	enable := command == "enable"

	switch command {
	case "enable", "disable":
		switch target {
		case "serving":
			force := false
			if !enable {
				// If the command is to disable, make sure at least one other corpus is serving
				var err error
				force, err = s.ensureAnotherServingCorpusAvailable(ctx, cmd, fmt.Sprintf("Are you sure you want to %s %s on %s? No other corpora are enabled for %s. (Use --force to override.)", command, target, corpus, target))
				if err != nil {
					return nil, err
				}
			}

			_, err := s.adminAPI.SetCorpusQueryState(ctx, &pb.SetCorpusQueryStateRequest{Corpus: corpus, Serving: enable, Force: force})
			if err != nil {
				return nil, errors.Errorf("Failed to %s %s on %s", command, target, corpus)
			}
			return &chatops.CommandResponse{Result: fmt.Sprintf("OK, %s %sd for the %s corpus", target, command, corpus)}, nil
		case "indexing":
			_, err := s.adminAPI.SetCorpusIndexingState(ctx, &pb.SetCorpusIndexingStateRequest{Corpus: corpus, Indexing: enable})
			if err != nil {
				return nil, errors.Errorf("Failed to %s %s on %s", command, target, corpus)
			}
			return &chatops.CommandResponse{Result: fmt.Sprintf("OK, %s %sd for the %s corpus", target, command, corpus)}, nil
		case "healing":
			_, err := s.adminAPI.SetCorpusHealingState(ctx, &pb.SetCorpusHealingStateRequest{Corpus: corpus, Healing: enable})
			if err != nil {
				return nil, errors.Errorf("Failed to %s %s on %s", command, target, corpus)
			}
			return &chatops.CommandResponse{Result: fmt.Sprintf("OK, %s %sd for the %s corpus", target, command, corpus)}, nil
		case "blob-filtering":
			_, err := s.adminAPI.SetCorpusFilterBlobs(ctx, &pb.SetCorpusFilterBlobsRequest{Corpus: corpus, FilterBlobs: enable})
			if err != nil {
				return nil, errors.Errorf("Failed to %s %s on %s", command, target, corpus)
			}
			return &chatops.CommandResponse{Result: fmt.Sprintf("OK, %s %sd for the %s corpus", target, command, corpus)}, nil

		default:
			return nil, errMsg
		}
	}
	return nil, errMsg
}

func (s *ChatopsServer) chatIndexRepo(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	ownerName, okOwner := cmd.Params["owner"]
	repoName, okRepo := cmd.Params["repo"]
	_, reindex := cmd.Params["reindex"]
	corpus := cmd.Params["corpus"]

	if okOwner && okRepo {
		nwo := ownerName + "/" + repoName
		resp, err := s.adminAPI.IndexRepo(ctx, &pb.IndexRepoRequest{
			RepoNwo:      nwo,
			ForceReindex: reindex,
			Corpus:       corpus,
		})
		if err != nil {
			return nil, err
		}

		corpusDisplay := corpus
		if corpusDisplay == "" {
			corpusDisplay = "all"
		}

		result := fmt.Sprintf("Published onboarding topic message to index %s, repo_id=%d, force_reindex=%t, corpus=%s", nwo, resp.RepositoryId, reindex, corpusDisplay)
		return &chatops.CommandResponse{Result: result}, nil
	}
	return nil, errors.New("unable to parse repo nwo")
}

func (s *ChatopsServer) ensureAnotherServingCorpusAvailable(ctx context.Context, cmd *chatops.CommandRequest, overrideErrorMsg string) (bool, error) {
	_, force := cmd.Params["force"]

	resp, err := s.adminAPI.GetCorpusStatus(ctx, &pb.GetCorpusStatusRequest{})
	if err != nil {
		return force, errors.WithMessage(err, "unable to get corpora status")
	}

	anotherCorpusIsServing := false
	for _, s := range resp.Statuses {
		if !strings.EqualFold(s.CorpusName, cmd.Params["corpus"]) && s.Serving {
			anotherCorpusIsServing = true
			break
		}
	}

	if !anotherCorpusIsServing {
		if !force {
			return force, errors.New(overrideErrorMsg)
		}
	}

	return force, nil
}

func (s *ChatopsServer) simSearch(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	if _, ok := cmd.Params["repo"]; !ok {
		return nil, errors.New("must provide a repo")
	}
	if _, ok := cmd.Params["corpus"]; !ok {
		return nil, errors.New("must provide a corpus")
	}

	var numSnapshots uint32 = 10
	if val, ok := cmd.Params["num-snapshots"]; ok {
		s, err := strconv.ParseUint(val, 10, 32)
		if err != nil {
			return nil, errors.Wrapf(err, "error parsing num-snapshots %s", cmd.Params["num-snapshots"])
		}

		numSnapshots = uint32(s)
	}

	var entriesPerSnapshot uint32 = 2
	if val, ok := cmd.Params["entries-per-snapshot"]; ok {
		e, err := strconv.ParseUint(val, 10, 32)
		if err != nil {
			return nil, errors.Wrapf(err, "error parsing entries-per-snapshot %s", cmd.Params["entries-per-snapshot"])
		}

		entriesPerSnapshot = uint32(e)
	}

	var epoch uint32
	if val, ok := cmd.Params["epoch"]; ok {
		e, err := strconv.ParseUint(val, 10, 32)
		if err != nil {
			return nil, errors.Wrapf(err, "error parsing epoch %s", cmd.Params["epoch"])
		}

		epoch = uint32(e)
	}

	req := &pb.GetSimilarReposRequest{
		RepoNwo:            strings.ToLower(cmd.Params["repo"]),
		Corpus:             strings.ToLower(cmd.Params["corpus"]),
		EpochId:            epoch,
		NumSnapshots:       numSnapshots,
		EntriesPerSnapshot: uint32(entriesPerSnapshot),
	}
	response, err := s.adminAPI.GetSimilarRepos(ctx, req)
	if err != nil {
		return nil, errors.Wrap(err, "couldn't get similar repos")
	}

	return toCommandResponse(response)
}

func (s *ChatopsServer) chatComputeMST(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	limit, err := parseUint32(cmd, "limit")
	if err != nil {
		return nil, err
	}

	epochID, err := parseUint32(cmd, "epoch")
	if err != nil {
		return nil, err
	}

	numMasks, err := parseUint32(cmd, "num-masks")
	if err != nil {
		return nil, err
	}

	req := &pb.ComputeMstRequest{
		Limit:    limit,
		EpochId:  epochID,
		NumMasks: numMasks,
		Query:    cmd.Params["query"],
	}

	ctx = background.Context(ctx)
	go func() {
		defer utils.PanicLogger(ctx)

		start := time.Now()
		res, err := s.adminAPI.ComputeMst(ctx, req)
		if err != nil {
			logging.Error(ctx, "error getting MST stats", kvp.Err(err))
			s.respond(ctx, cmd, fmt.Sprintf("Error getting minimum spanning tree stats after %s: %+v", time.Since(start), err))
			return
		}

		// TODO: Shard MST RPC should include epoch it ran on
		epoch := "current epoch"
		if req.EpochId > 0 {
			epoch = fmt.Sprintf("epoch %d", req.EpochId)
		}

		msg := fmt.Sprintf(
			`Minimum spanning tree for %s created in %s on %q.

* Nodes: %d
* Flat cost: %d
* MST cost: %d
* MaxDepth: %d
* MaxEncodingSize: %d
* MaxSubtreeSize: %d
* RootChildren: %d
* Query time: %s
* MST calculation time: %s
* MST traversal time: %s`,
			epoch,
			res.TotalTime.AsDuration(),
			res.Host,
			res.NumRepos,
			res.FlatCost,
			res.MstCost,
			res.MaxDepth,
			res.MaxEncodingSize,
			res.MaxSubtreeSize,
			res.RootChildren,
			res.QueryTime.AsDuration(),
			res.MstTime.AsDuration(),
			res.TraverseTime.AsDuration())
		s.respond(ctx, cmd, msg)
	}()

	return &chatops.CommandResponse{Result: "Minimum spanning tree request enqueued. Results will be posted asynchronously."}, nil
}

func (s *ChatopsServer) compact(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {

	var corpus string
	if val, ok := cmd.Params["corpus"]; ok {
		corpus = val
	} else {
		return nil, errors.New("must provide a corpus")
	}

	var ct pb.CompactionType
	if val, ok := cmd.Params["type"]; ok {
		switch strings.ToLower(val) {
		case "full":
			ct = pb.CompactionType_COMPACTION_TYPE_FULL
		case "incremental":
			ct = pb.CompactionType_COMPACTION_TYPE_INCREMENTAL
		default:
			return nil, errors.Errorf("invalid compaction type: %s", val)
		}
	} else {
		return nil, errors.New("must provide compaction type [full, incremental]")
	}

	req := &pb.CompactCorpusRequest{
		Corpus:         corpus,
		CompactionType: ct,
	}
	response, err := s.adminAPI.CompactCorpus(ctx, req)
	if err != nil {
		return nil, errors.Wrap(err, "couldn't trigger compaction")
	}

	return toCommandResponse(response)
}

func (s *ChatopsServer) resetQuota(ctx context.Context, cmd *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	if login, ok := cmd.Params["login"]; ok {
		_, err := s.adminAPI.ResetRateLimitQuota(ctx, &pb.ResetRateLimitQuotaRequest{Login: login})
		if err != nil {
			return nil, err
		}
		return &chatops.CommandResponse{Result: fmt.Sprintf("Reset the %s's rate limit quota", login)}, nil
	}
	return nil, errors.New("unable to parse login")
}

func toCommandResponse(m protoreflect.ProtoMessage) (*chatops.CommandResponse, error) {
	val := protojson.MarshalOptions{
		Multiline:       true,
		EmitUnpopulated: true,
		UseProtoNames:   true,
	}.Format(m)
	return &chatops.CommandResponse{Result: val}, nil
}

// Register registers a chatops handler
func (s *ChatopsServer) register(ns *chatops.Namespace, name, help, regex string, handler chatops.CommandFunc) {
	h, err := ns.Add(name)
	if err != nil {
		panic(err)
	}
	h.Help = help
	h.Regex = regex
	h.On(handler)
}

func (s *ChatopsServer) respond(ctx context.Context, cmd *chatops.CommandRequest, msg string) {
	chat.Say(ctx, s.chatClient, cmd.RoomID, msg)
}

func formatDuration(took time.Duration) string {
	seconds := took / time.Second
	minutes := seconds / 60
	hours := minutes / 60
	return fmt.Sprintf("%02d:%02d:%02d", hours, minutes%60, seconds%60)
}

func newBackfillRequest(cmd *chatops.CommandRequest) (*pb.BackfillCorpusRequest, error) {
	corpus := strings.ToLower(cmd.Params["corpus"])
	reason := cmd.Params["reason"]
	if reason == "" {
		reason = fmt.Sprintf("Backfill started by %s on %v via chatops", cmd.User, time.Now().UTC().Format("2006-01-02"))
	}

	limit, err := parseUint32(cmd, "limit")
	if err != nil {
		return nil, err
	}

	epochID, err := parseUint32(cmd, "epoch")
	if err != nil {
		return nil, err
	}

	numMasks, err := parseUint32(cmd, "num-masks")
	if err != nil {
		return nil, err
	}

	return &pb.BackfillCorpusRequest{
		Corpus:   corpus,
		Reason:   reason,
		Limit:    limit,
		EpochId:  epochID,
		NumMasks: numMasks,
		Query:    cmd.Params["query"],
	}, nil
}

// Given a CRPC command and a parameter name, parse the parameter as a uint32 if
// present, or return an error.
func parseUint32(cmd *chatops.CommandRequest, name string) (uint32, error) {
	if cmd.Params[name] == "" {
		return 0, nil
	}

	parsed, err := strconv.ParseUint(cmd.Params[name], 10, 32)
	if err != nil {
		return 0, fmt.Errorf("%s must be greater than or equal to 0, got %s", name, cmd.Params[name])
	}

	return uint32(parsed), nil
}

func parseInt64(cmd *chatops.CommandRequest, name string) (int64, error) {
	if cmd.Params[name] == "" {
		return 0, nil
	}

	parsed, err := strconv.ParseInt(cmd.Params[name], 10, 64)
	if err != nil {
		return 0, fmt.Errorf("%s must be greater than or equal to 0, got %s", name, cmd.Params[name])
	}

	return int64(parsed), nil
}
