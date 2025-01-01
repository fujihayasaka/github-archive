package consumers

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/pkg/errors"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"google.golang.org/protobuf/proto"

	cshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entities "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

type CodeQLRequirement interface {
	IsCodeQLRequired(ctx context.Context, repoID ts.RepositoryEID, ref ts.Ref) (bool, error)
}

type ExpectedCodeqlRunPublisher interface {
	ExpectedCodeqlRunEvent(context.Context, *cshydro.ManagedAnalysesExpectedCodeqlRun) error
}

// DELAY_FOR_PR_ANALYSIS is the delay we introduce before enqueuing job to dispatch the workflow run.
// This is mostly meant to avoid race conditions with launch. See https://github.com/github/code-scanning/issues/12399
const DELAY_FOR_PR_ANALYSIS = 5 * time.Second

// AnalysisTriggerProcessor is responsible for processing and reacting to push and pr events and triggering ManagedAnalysis jobs.
// It implements the HydroProcessor interface.
type AnalysisTriggerProcessor struct {
	hydroPublisher    ExpectedCodeqlRunPublisher
	ma                managedanalyses.CodeqlDB
	aqueduct          aqueduct.JobPerformer
	repos             *RepositorySet
	codeQLRequirement CodeQLRequirement
	useNextGRID       bool
}

// Verify that AnalysisTriggerProcessor implements the HydroProcessor interface
var _ hydroProcessor = (*AnalysisTriggerProcessor)(nil)

// RepositorySet is an in-memory set of all enabled repository IDs
type RepositorySet struct {
	mu          sync.Mutex
	enabled     map[ts.RepositoryEID]struct{}
	mas         managedanalyses.CodeqlDB
	refreshedAt *time.Time
}

func (rs *RepositorySet) Contains(id ts.RepositoryEID) bool {
	rs.mu.Lock()
	defer rs.mu.Unlock()
	_, ok := rs.enabled[id]
	return ok
}

func (rs *RepositorySet) FullRefresh(ctx context.Context) error {
	repos, updatedAt, err := rs.mas.GetPotentiallyOnboardedRepositoryIDs(ctx, nil)
	if err != nil {
		return err
	}
	newEnabledRepos := make(map[ts.RepositoryEID]struct{})
	for _, r := range repos {
		newEnabledRepos[r] = struct{}{}
	}

	rs.mu.Lock()
	rs.enabled = newEnabledRepos
	rs.mu.Unlock()

	rs.refreshedAt = updatedAt
	return nil
}

func (rs *RepositorySet) IncrementalRefresh(ctx context.Context) error {
	repos, updatedAt, err := rs.mas.GetPotentiallyOnboardedRepositoryIDs(ctx, rs.refreshedAt)
	if err != nil {
		return err
	}

	rs.mu.Lock()
	for _, r := range repos {
		rs.enabled[r] = struct{}{}
	}
	rs.mu.Unlock()

	rs.refreshedAt = updatedAt
	return nil
}

func NewAnalysisTriggerProcessor(hydroPublisher ExpectedCodeqlRunPublisher, ma managedanalyses.CodeqlDB, aqueduct aqueduct.JobPerformer, codeQLRequirement CodeQLRequirement, useNextGRID bool) *AnalysisTriggerProcessor {

	repoMap := &RepositorySet{
		enabled: make(map[ts.RepositoryEID]struct{}),
		mas:     ma,
	}

	return &AnalysisTriggerProcessor{
		hydroPublisher:    hydroPublisher,
		ma:                ma,
		aqueduct:          aqueduct,
		repos:             repoMap,
		codeQLRequirement: codeQLRequirement,
		useNextGRID:       useNextGRID,
	}
}

func (p *AnalysisTriggerProcessor) ProcessorName() string {
	return "AnalysisTriggerProcessor"
}

func (p *AnalysisTriggerProcessor) ProcessEnvelope(ctx context.Context, envelope *envelope.Envelope, topic string) error {
	startTime := time.Now()

	var err error
	var repoID uint32

	switch topic {
	case topics.PostReceive:
		var msg tshydro.PostReceive
		if err = proto.Unmarshal(envelope.Message, &msg); err != nil {
			return errors.Wrap(err, "unmarshalling post receive event message")
		}
		repoID = msg.Repository.Id
		err = p.ProcessPostReceive(ctx, &msg)
	case topics.PullRequestSynchronize:
		var msg tshydro.PullRequestSynchronize
		if err = proto.Unmarshal(envelope.Message, &msg); err != nil {
			return errors.Wrap(err, "unmarshalling pull request synchronize event message")
		}
		repoID = msg.Repository.Id
		err = p.ProcessPullRequestSynchronize(ctx, &msg)

	case topics.PullRequestCreate:
		var msg tshydro.PullRequestCreate
		if err = proto.Unmarshal(envelope.Message, &msg); err != nil {
			return errors.Wrap(err, "unmarshalling pull request create event message")
		}
		repoID = msg.Repository.Id
		err = p.ProcessPullRequestCreate(ctx, &msg)
	}

	duration := time.Since(startTime)
	skipped := errors.Is(err, ErrRepoDisabled) || errors.Is(err, ErrIgnoredEvent) || errors.Is(err, ErrDependabotEvent)
	tags := stats.Tags{
		"success": strconv.FormatBool(err == nil || skipped),
		"skipped": strconv.FormatBool(skipped),
		"topic":   topic,
	}
	if skipped {
		tags["reason"] = err.Error()
	}
	appctx.Stats(ctx).DistributionMs("analysis_trigger_processor.message", tags, duration)
	if skipped {
		return nil
	}

	// Only log processed messages
	appctx.Logger(ctx).WithError(err).WithFields(
		kvp.String("gh.turboscan.msg_id", envelope.GetId()),
		ts.RepositoryEID(repoID).AsKVP(),
		kvp.String("gh.operation.name", "process_envelope"),
		kvp.Float64("gh.operation.duration", float64(duration)),
	).Info("processed analysis trigger message")

	return err
}

func (p *AnalysisTriggerProcessor) ProcessPostReceive(ctx context.Context, msg *tshydro.PostReceive) error {
	// Ignore repositories that don't have the feature enabled
	if !p.repos.Contains(ts.RepositoryEID(msg.Repository.Id)) {
		return ErrRepoDisabled
	}

	// Ignore events with no actor
	if msg.Actor == nil {
		return ErrIgnoredEvent
	}

	// Ignore commits from Dependabot
	if msg.Actor.Login == "dependabot[bot]" {
		return ErrIgnoredEvent
	}

	repoID := ts.RepositoryEID(msg.Repository.Id)

	eventTimestamp := gormext.ConvertPBTime(msg.PushedAt)
	if eventTimestamp == nil {
		appctx.Logger(ctx).Debug("EventTimestamp not extracted",
			repoID.AsKVP(),
			kvp.String("gh.turboscan.method", "ProcessPostReceive"))
	}

	ignoredEvent := true
	for _, ref := range msg.RefUpdates {
		if !strings.HasPrefix(ref.RefName, "refs/heads/") {
			continue
		}
		runJob := false
		branch := strings.TrimPrefix(ref.RefName, "refs/heads/")
		inDefaultBranch := false
		if branch == msg.Repository.DefaultBranch {
			runJob = true
			inDefaultBranch = true
		}
		if !runJob {
			required, err := p.codeQLRequirement.IsCodeQLRequired(ctx, repoID, []byte(ref.RefName))
			if err != nil {
				return err
			}
			runJob = required
		}
		if runJob {
			ignoredEvent = false
			err := p.hydroPublisher.ExpectedCodeqlRunEvent(ctx, &cshydro.ManagedAnalysesExpectedCodeqlRun{
				RepositoryId:        int64(repoID),
				OwnerId:             int64(msg.Owner.GetId()),
				TriggeringEventTime: msg.PushedAt,
				TriggeringEventType: "post_receive",
				Ref:                 []byte(ref.RefName),
				CommitOid:           ref.CurrentRefOid,
				DefaultBranch:       inDefaultBranch,
			})
			if err != nil {
				return err
			}
			job := jobs.RunCodeqlOnPush{
				RepoID:          repoID,
				OwnerID:         ts.OwnerEID(msg.Owner.GetId()),
				Ref:             ts.Ref(ref.RefName),
				Sha:             ts.ToSha(ref.CurrentRefOid), // TODO: This should error if the SHA is not a valid SHA
				ActorLogin:      msg.Actor.Login,
				ActorGRID:       actorGRID(msg, p.useNextGRID),
				InDefaultBranch: inDefaultBranch,
				EventTimeStamp:  eventTimestamp,
			}
			_, err = p.aqueduct.PerformLater(ctx, job)
			if err != nil {
				return err
			}
		}
	}
	if ignoredEvent {
		return ErrIgnoredEvent
	}
	return nil
}

func (p *AnalysisTriggerProcessor) ProcessPullRequestSynchronize(ctx context.Context, msg *tshydro.PullRequestSynchronize) error {
	repoID := ts.RepositoryEID(msg.Repository.Id)

	// Ignore repositories that don't have the feature enabled
	if !p.repos.Contains(repoID) {
		return ErrRepoDisabled
	}

	// Ignore events with no actor
	if msg.Actor == nil {
		return ErrIgnoredEvent
	}

	if msg.Actor.Login == "dependabot[bot]" {
		return p.handleDependabotEvents(ctx, msg)
	}

	// Ignore events on fork repositories
	if msg.Repository.Id != msg.BaseRepository.Id {
		appctx.Stats(ctx).Counter("analysis_trigger_processor.skip_fork_pr", stats.Tags{"visibility": msg.BaseRepository.Visibility.String()}, 1)
		appctx.Logger(ctx).Debug("Skipping PR from fork",
			repoID.AsKVP(), visibilityAsKVP(msg.BaseRepository.Visibility),
			kvp.String("gh.turboscan.method", "ProcessPullRequestSynchronize"))
		return ErrIgnoredEvent
	}

	// Ignore events on PRs not based on a default or protected branch
	runJob := false
	branch := string(msg.PullRequest.BaseBranch)
	if branch == msg.BaseRepository.DefaultBranch {
		runJob = true
	}
	if !runJob {
		ref := append([]byte("refs/heads/"), msg.PullRequest.BaseBranch...)
		required, err := p.codeQLRequirement.IsCodeQLRequired(ctx, repoID, ref)
		if err != nil {
			return err
		}
		runJob = required
	}
	if !runJob {
		return ErrIgnoredEvent
	}
	err := p.hydroPublisher.ExpectedCodeqlRunEvent(ctx, &cshydro.ManagedAnalysesExpectedCodeqlRun{
		RepositoryId:        int64(repoID),
		OwnerId:             int64(msg.BaseRepository.GetOwnerId().GetValue()),
		TriggeringEventTime: msg.PullRequest.UpdatedAt,
		TriggeringEventType: "pull_request_synchronize",
		Ref:                 ts.Ref(fmt.Sprintf("refs/pull/%d/head", msg.Issue.Number)),
		CommitOid:           msg.PullRequest.HeadSha,
		DefaultBranch:       branch == msg.BaseRepository.DefaultBranch,
	})
	if err != nil {
		return err
	}

	eventTimeStamp := gormext.ConvertPBTime(msg.PullRequest.UpdatedAt)
	if eventTimeStamp == nil {
		appctx.Logger(ctx).Debug("EventTimestamp not extracted",
			repoID.AsKVP(),
			kvp.String("gh.turboscan.method", "ProcessPullRequestSynchronize"))
	}
	job := jobs.RunCodeqlOnPullRequest{
		RepoID:         repoID,
		OwnerID:        ts.OwnerEID(msg.BaseRepository.GetOwnerId().GetValue()),
		Sha:            ts.ToSha(msg.PullRequest.HeadSha), // TODO: This should error if the SHA is not a valid SHA
		ActorLogin:     msg.Actor.Login,
		ActorGRID:      actorGRID(msg, p.useNextGRID),
		PRNumber:       msg.Issue.Number,
		EventTimestamp: eventTimeStamp,
	}
	_, err = p.aqueduct.PerformLater(ctx, job)
	return err
}

func (p *AnalysisTriggerProcessor) ProcessPullRequestCreate(ctx context.Context, msg *tshydro.PullRequestCreate) error {
	repoID := ts.RepositoryEID(msg.Repository.Id)

	// Ignore repositories that don't have the feature enabled
	if !p.repos.Contains(repoID) {
		return ErrRepoDisabled
	}

	// Ignore events with no actor
	if msg.Actor == nil {
		return ErrIgnoredEvent
	}

	// Ignore events on fork repositories
	if msg.HeadRepository.Id != msg.Repository.Id {
		appctx.Stats(ctx).Counter("analysis_trigger_processor.skip_fork_pr", stats.Tags{"visibility": msg.HeadRepository.Visibility.String()}, 1)
		appctx.Logger(ctx).Debug("Skipping PR from fork",
			repoID.AsKVP(), visibilityAsKVP(msg.HeadRepository.Visibility),
			kvp.String("gh.turboscan.method", "ProcessPullRequestCreate"))
		return ErrIgnoredEvent
	}

	if msg.Actor.Login == "dependabot[bot]" {
		return p.handleDependabotEvents(ctx, msg)
	}

	// Ignore events on PRs not based on a default or protected branch
	runJob := false
	branch := string(msg.PullRequest.BaseBranch)
	if branch == msg.Repository.DefaultBranch {
		runJob = true
	}
	if !runJob {
		ref := append([]byte("refs/heads/"), msg.PullRequest.BaseBranch...)
		required, err := p.codeQLRequirement.IsCodeQLRequired(ctx, repoID, ref)
		if err != nil {
			return err
		}
		runJob = required
	}
	if !runJob {
		return ErrIgnoredEvent
	}
	err := p.hydroPublisher.ExpectedCodeqlRunEvent(ctx, &cshydro.ManagedAnalysesExpectedCodeqlRun{
		RepositoryId:        int64(repoID),
		OwnerId:             int64(msg.RepositoryOwner.Id),
		TriggeringEventTime: msg.PullRequest.CreatedAt,
		TriggeringEventType: "pull_request_create",
		Ref:                 ts.Ref(fmt.Sprintf("refs/pull/%d/head", msg.Issue.Number)),
		CommitOid:           msg.PullRequest.HeadSha,
		DefaultBranch:       branch == msg.Repository.DefaultBranch,
	})
	if err != nil {
		return err
	}

	eventTimestamp := gormext.ConvertPBTime(msg.PullRequest.CreatedAt)
	if eventTimestamp == nil {
		appctx.Logger(ctx).Debug("EventTimestamp not extracted",
			repoID.AsKVP(),
			kvp.String("gh.turboscan.method", "ProcessPullRequestCreate"))
	}
	job := jobs.RunCodeqlOnPullRequest{
		RepoID:         repoID,
		OwnerID:        ts.OwnerEID(msg.RepositoryOwner.GetId()),
		Sha:            ts.ToSha(msg.PullRequest.HeadSha), // TODO: This should error if the SHA is not a valid SHA
		ActorLogin:     msg.Actor.Login,
		ActorGRID:      actorGRID(msg, p.useNextGRID),
		PRNumber:       msg.Issue.Number,
		EventTimestamp: eventTimestamp,
	}
	_, err = p.aqueduct.PerformLater(ctx, job)
	return err
}

func (p *AnalysisTriggerProcessor) Topics() []string {
	return []string{topics.PostReceive, topics.PullRequestCreate, topics.PullRequestSynchronize}
}

func (p *AnalysisTriggerProcessor) HandleError(ctx context.Context, err error, m *hydro.Message) error {
	return handleError(ctx, err, m)
}

// PollEnabledRepos periodically polls the database for the list of enabled repositories and updates the `enabledRepos` map
func (p *AnalysisTriggerProcessor) PollEnabledRepos(ctx context.Context, interval time.Duration) error {
	tick := time.NewTicker(interval)
	defer tick.Stop()
	for {
		select {
		case <-tick.C:
			start := time.Now()
			err := p.repos.IncrementalRefresh(ctx)
			appctx.Stats(ctx).DistributionMs("analysis_trigger_processor.refresh_repos", stats.Tags{"failed": strconv.FormatBool(err != nil)}, time.Since(start))
			if err != nil {
				return err
			}
			appctx.Stats(ctx).Gauge("analysis_trigger_processor.enabled_repos", stats.Tags{}, int64(len(p.repos.enabled)))
		case <-ctx.Done():
			return nil
		}
	}
}

// Init initializes the processor by performing an initial repository update
func (p *AnalysisTriggerProcessor) Init(ctx context.Context) error {
	start := time.Now()

	err := p.repos.FullRefresh(ctx)

	appctx.Stats(ctx).DistributionMs("analysis_trigger_processor.init_repos", stats.Tags{"success": strconv.FormatBool(err == nil)}, time.Since(start))
	return err
}

type prMessage interface {
	GetRepository() *entities.Repository
	GetPullRequest() *entities.PullRequest
}

// handleDependabotEvents handles the event of a Dependabot PRs
func (p *AnalysisTriggerProcessor) handleDependabotEvents(ctx context.Context, msg prMessage) error {
	// We only care about events against the default branch.
	// However, dependabot only runs on the default branch, so we don't need
	// add an explicit check.
	job := jobs.SkipDependabot{
		RepoID:        ts.RepositoryEID(msg.GetRepository().Id),
		PullRequestID: msg.GetPullRequest().Id,
	}
	_, err := p.aqueduct.PerformLater(ctx, job)
	if err != nil {
		return err
	}
	// Return a special error to indicate that this event was processed
	// as a DependabotEvent and skip the rest of the processing.
	return ErrDependabotEvent
}

func (p *AnalysisTriggerProcessor) GetRetryPolicy() RetryPolicy {
	return RetryPolicy{MaxRetryElapsedTime: 0, RetryDelay: 0}
}

func (p *AnalysisTriggerProcessor) BeforeRetry(ctx context.Context, lastErr error, errCnt int, e *envelope.Envelope, m *hydro.Message) {
}

func (p *AnalysisTriggerProcessor) OnPermanentFailure(ctx context.Context, e *envelope.Envelope, m *hydro.Message) error {
	return nil
}

type msgWithActor interface {
	GetActor() *entities.User
}

func actorGRID(msg msgWithActor, useNextGRID bool) ts.ActorGRID {
	actor := msg.GetActor()
	if actor == nil {
		return ts.ActorGRID("")
	}
	if useNextGRID {
		return ts.ActorGRID(actor.NextGlobalId)
	}
	return ts.ActorGRID(actor.GlobalRelayId)
}

func visibilityAsKVP(v entities.Repository_Visibility) zapcore.Field {
	var str string
	switch v {
	case entities.Repository_INTERNAL:
		str = "INTERNAL"
	case entities.Repository_PRIVATE:
		str = "PRIVATE"
	case entities.Repository_PUBLIC:
		str = "PUBLIC"
	case entities.Repository_VISIBILITY_UNKNOWN:
		str = "unknown"
	}
	return zap.String("gh.repo.visibility", str)

}
