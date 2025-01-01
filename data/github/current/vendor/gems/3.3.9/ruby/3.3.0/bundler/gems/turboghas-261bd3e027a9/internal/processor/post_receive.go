// Package processor contains the advanced security post receive processor that tracks contributions.
package processor

import (
	"context"
	"fmt"
	"strings"
	"time"
	"unicode"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	turboghasv0 "github.com/github/hydro-schemas-go/hydro/schemas/turboghas/v0"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fields"
	"github.com/github/turboghas/internal/fromctx"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/twirperr"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"golang.org/x/exp/maps"
	"golang.org/x/text/runes"
	"golang.org/x/text/transform"
	"golang.org/x/text/unicode/norm"
)

var _ = Topic("cp1-iad.ingest.github.v1.PostReceive")
var LargePostReceiveTopic = LowPriorityTopic("turboghas.v0.LargePostReceive")
var PostReceiveQueue = Queue(&githubv1.PostReceive{})

type PostReceiveDependencies interface {
	GetEmailsFromRefUpdates(ctx context.Context, repositoryID uint64, refUpdates []*githubv1.PostReceive_RefUpdate) ([]*commits.Contributor, error)
}

func IsBillable(ctx context.Context, postReceive *githubv1.PostReceive) bool {
	if fromctx.Env.Value(ctx).IsEnterprise() {
		return true
	}
	return postReceive.Repository.Visibility != entities.Repository_PUBLIC &&
		(postReceive.Owner.Type == entities.User_ORGANIZATION || (postReceive.Owner.Type == entities.User_USER && postReceive.Owner.IsEnterpriseManaged))
}

func IsEntityTooLarge(ctx context.Context, businessID *uint64, ownerID uint64, repoID uint32) (bool, error) {
	if fromctx.Env.Value(ctx).IsEnterprise() {
		return false, nil
	}
	var actorID string
	if businessID != nil {
		actorID = fmt.Sprintf("Business:%d", *businessID)
	} else {
		actorID = fmt.Sprintf("User:%d", ownerID)
	}
	tooLarge, err := fromctx.Flipper.Value(ctx).IsEnabled(ctx, "turboghas_entity_too_large", actorID)
	if !tooLarge && err == nil {
		return fromctx.Flipper.Value(ctx).IsEnabled(ctx, "turboghas_entity_too_large", fmt.Sprintf("Repository:%d", repoID))
	}
	return tooLarge, err
}

// Filter returns the values where predicate returns true.
func Filter[T any](items []T, predicate func(T) bool) []T {
	if items == nil {
		return nil
	}

	result := make([]T, 0, len(items))

	for _, item := range items {
		if ok := predicate(item); ok {
			result = append(result, item)
		}
	}

	return result
}

func Map[T, V any](items []T, fn func(T) V) []V {
	if items == nil {
		return nil
	}
	out := make([]V, 0, len(items))
	for _, item := range items {
		out = append(out, fn(item))
	}
	return out
}

func EmailKey(email []byte) string {
	key := string(email)

	user, domain, found := strings.Cut(key, "@")
	idx := strings.LastIndexByte(user, '+')
	if idx > 0 {
		user = user[:idx]
	}

	out := user
	if found {
		domain, _, _ = strings.Cut(domain, "@")

		out = user + "@" + domain
	}

	// try and emulate utf8mb3_general_ci
	pipe := transform.Chain(
		norm.NFKD,
		runes.Remove(runes.In(unicode.Mn)),
		runes.Remove(runes.Predicate(unicode.IsSpace)),
		runes.Map(unicode.ToLower),
	)

	if transformed, _, err := transform.String(pipe, out); err == nil {
		out = transformed
	}

	return out
}

func (p *Processor) postReceive(ctx context.Context, postReceive *githubv1.PostReceive) (err error) {
	statter := fromctx.Statter.Value(ctx)

	// the tracking will be handled by aqueduct
	// only report latency if we are not in the backfill
	if p.aqueduct != nil {
		startTime := postReceive.PushedAt.AsTime()
		defer func() {
			if err == nil {
				return
			}
			lifetime := time.Since(startTime)
			fromctx.SLOTracker.Track(ctx, "latency/p50-online-processor", lifetime < p50Threshold)
			fromctx.SLOTracker.Track(ctx, "latency/p99-online-processor", lifetime < p99Threshold)
		}()
	}

	var businessID *uint64
	if postReceive.Business.GetId() != nil {
		businessID = data.PtrTo(uint64(postReceive.Business.Id.Value))
	}

	if !IsBillable(ctx, postReceive) {
		statter.Counter("post_receive.message", stats.Tags{"billable": "false"}, 1)
		return nil
	}

	tooLarge, err := IsEntityTooLarge(ctx, businessID, uint64(postReceive.Owner.Id), postReceive.Repository.GetId())
	if err != nil {
		return errors.Wrap(err, "failed to check if entity is too large")
	}

	if tooLarge {
		statter.Counter("post_receive.message.skipped", nil, 1)
		return nil
	}

	// filter out any non-branch updates (e.g: tags)
	// doing this now reduces the size of message we put on Aqueduct
	branchUpdates := Filter(postReceive.RefUpdates, func(update *githubv1.PostReceive_RefUpdate) bool {
		return strings.HasPrefix(update.RefName, "refs/heads/")
	})

	statter.Counter("post_receive.ref_updates", stats.Tags{}, int64(len(postReceive.RefUpdates)))
	statter.Counter("post_receive.branch_updates", stats.Tags{}, int64(len(branchUpdates)))

	postReceive.RefUpdates = branchUpdates

	if outer := Hydro.Value(ctx); outer != nil && outer.Topic == LargePostReceiveTopic {
		// process large post receive tasks one at a time
		// this should not block other processors
		// setting a maxQueueDepth of zero causes synchronous processing
		return p.EnqueueJob(ctx, postReceive, 0)
	}

	// put large post receive messages a single partition queue
	if len(postReceive.RefUpdates) > 500 {
		return p.publisher.Publish(postReceive, hydro.WithTopic(LargePostReceiveTopic))
	}

	// The Aqueduct job will be handled by postReceiveJob, below.
	return p.EnqueueJob(ctx, postReceive, 250)
}

const (
	p50Threshold = 5 * time.Second
	p99Threshold = 15 * time.Minute
)

func (p *Processor) postReceiveJob(ctx context.Context, postReceive *githubv1.PostReceive) (err error) {
	statter := fromctx.Statter.Value(ctx)

	// only report latency if we are not in the backfill
	if p.aqueduct != nil {
		startTime := postReceive.PushedAt.AsTime()
		defer func() {
			lifetime := time.Since(startTime)
			fromctx.SLOTracker.Track(ctx, "latency/p50-online-processor", lifetime < p50Threshold)
			fromctx.SLOTracker.Track(ctx, "latency/p99-online-processor", lifetime < p99Threshold)
		}()
	}

	var businessID *uint64
	if postReceive.Business.GetId() != nil {
		businessID = data.PtrTo(uint64(postReceive.Business.Id.Value))
	}

	logger := fromctx.Logger.Value(ctx).WithFields(
		kvp.Uint32("gh.repo.id", postReceive.Repository.Id),
		kvp.Uint32("gh.turboghas.owner_id", postReceive.Owner.Id),
		kvp.Uint64p("gh.turboghas.business_id", businessID),
		kvp.Any("pushed_at", postReceive.PushedAt),
	)

	defer func() {
		err = fields.Error(err,
			kvp.Uint32("gh.repo.id", postReceive.Repository.Id),
			kvp.Uint32("gh.turboghas.owner_id", postReceive.Owner.Id),
			kvp.Uint64p("gh.turboghas.business_id", businessID),
			kvp.Any("pushed_at", postReceive.PushedAt),
		)
	}()

	statter.Counter("post_receive.message", stats.Tags{"billable": "true", "enabled": "true"}, 1)

	if len(postReceive.RefUpdates) == 0 {
		statter.Counter("post_receive.missing_branch_updates", stats.Tags{}, 1)

		return nil
	}

	contributors, err := p.deps.GetEmailsFromRefUpdates(ctx, uint64(postReceive.Repository.Id), postReceive.RefUpdates)
	if err != nil {
		// it is likely the repository or business was deleted
		if twirperr.IsTwirpError(err, twirp.NotFound) {
			logger.Info("not found when fetching emails")
			return nil
		}
		return fields.Error(
			errors.Wrap(err, "failed to get emails from ref updates"),
			kvp.Strings("ref_updates", Map(postReceive.RefUpdates, func(update *githubv1.PostReceive_RefUpdate) string {
				return fmt.Sprintf("%s (%s..%s)", update.RefName, update.PreviousRefOid, update.PreviousRefOid)
			})),
		)
	}

	emails := Map(contributors, (*commits.Contributor).GetEmailBytes)

	statter.Counter("post_receive.emails", stats.Tags{}, int64(len(emails)))

	if len(emails) == 0 {
		statter.Counter("missing.emails", stats.Tags{}, 1)
		return nil
	}

	resp, err := p.githubAPI.FindUsersByEmails(ctx, &twirpTurboghas.FindUsersByEmailsRequest{
		Emails:       emails,
		BusinessId:   uint64(postReceive.BusinessId.GetValue()),
		RepositoryId: uint64(postReceive.Repository.Id),
		PushedAt:     postReceive.PushedAt,
	})
	if err != nil {
		// it is likely the repository or business was deleted
		if twirperr.IsTwirpError(err, twirp.NotFound) {
			logger.Info("not found when finding users")
			return nil
		}
		return errors.Wrap(err, "error fetching users")
	}

	statter.Counter("post_receive.users", stats.Tags{}, int64(len(resp.Users)))

	if len(resp.Users) == 0 {
		statter.Counter("missing.users", stats.Tags{}, 1)
		return nil
	}

	logger.Debug("Found contributions.", kvp.Strings("login", Map(resp.Users, (*twirpTurboghas.FindUsersByEmailsResponse_User).GetLogin)))

	// avoid hammering the endpoint as other cache invalidation triggers should keep tg_repositories up to date.
	hasCache, err := p.db.HasRepositoryCache(ctx, data.RepositoryID(postReceive.Repository.Id))
	if err != nil {
		return errors.Wrap(err, "failed to check repository cache")
	}
	if !hasCache {
		// we already checked if the repository was billable above
		// even if the repository has stopped existing we should continue to insert billable contributions
		// we can trust in the joins against repositories to not include them
		if _, syncErr := p.sync.Repository(ctx, uint64(postReceive.Repository.Id)); syncErr != nil {
			return errors.Wrap(syncErr, "failed to sync repository during post receive")
		}
	}

	for _, user := range resp.Users {
		if upsertErr := p.db.UpsertUser(ctx, data.UpsertUserArgs{
			UserID: data.UserID(user.Id),
			Login:  user.Login,
			Type:   twirpTurboghas.UserType_USER_TYPE_USER,
		}); upsertErr != nil {
			return fields.Error(errors.Wrap(upsertErr, "failed to update user"), kvp.Uint64("gh.user.id", user.Id))
		}
	}

	var business *turboghasv0.BillableContribution_Business
	if postReceive.Business != nil {
		business = &turboghasv0.BillableContribution_Business{
			Id:   postReceive.Business.Id,
			Name: postReceive.Business.Name,
		}
	}

	oids := make(map[string]string, len(contributors))
	for _, contributor := range contributors {
		oids[EmailKey(contributor.EmailBytes)] = contributor.CommitOid.GetId()
	}

	contribution := &turboghasv0.BillableContribution{
		Actor:      postReceive.Actor,
		Repository: postReceive.Repository,
		Owner:      postReceive.Owner,
		RefUpdates: Map(postReceive.RefUpdates, func(refUpdate *githubv1.PostReceive_RefUpdate) *turboghasv0.BillableContribution_RefUpdate {
			return &turboghasv0.BillableContribution_RefUpdate{
				PreviousRefOid: refUpdate.PreviousRefOid,
				CurrentRefOid:  refUpdate.CurrentRefOid,
				RefName:        refUpdate.RefName,
			}
		}),
		PushedAt: postReceive.PushedAt,
		Business: business,
		Committers: Map(resp.Users, func(user *twirpTurboghas.FindUsersByEmailsResponse_User) *turboghasv0.BillableContribution_Committer {
			commit := oids[EmailKey(user.Email)]
			if commit == "" {
				commitErr := errors.New("could not associate email address with commit")
				fromctx.ExceptionReporter.Report(ctx, commitErr, nil)
				have := make([]string, 0, 5)

				for n, email := range maps.Keys(oids) {
					// only ever include the first few commits
					if n > 5 {
						break
					}
					have = append(have, email+" = "+oids[email])
				}
				logger.WithError(commitErr).Error("could not associate commit with email",
					kvp.ByteString("want", user.Email),
					kvp.Strings("have", have),
				)
			}
			return &turboghasv0.BillableContribution_Committer{
				Email:     user.Email,
				UserId:    user.Id,
				Login:     user.Login,
				CreatedAt: user.CreatedAt,
				CommitOid: commit,
			}
		}),
	}

	if publishErr := p.PublishMessage(ctx, contribution); publishErr != nil {
		return errors.WithStack(publishErr)
	}

	return nil
}
