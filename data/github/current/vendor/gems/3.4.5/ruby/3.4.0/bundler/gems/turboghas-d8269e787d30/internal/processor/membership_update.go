package processor

import (
	"context"
	"time"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	lru "github.com/hashicorp/golang-lru/v2/expirable"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.MembershipUpdate")
var MembershipUpdateQueue = Queue(&githubv1.MembershipUpdate{})

var membershipUpdateDebouncer = lru.NewLRU[uint64, struct{}](1024, nil, 5*time.Second)

func (p *Processor) membershipUpdate(ctx context.Context, membershipUpdate *githubv1.MembershipUpdate) (err error) {
	if membershipUpdate.Context != githubv1.MembershipUpdate_ORGANIZATION {
		return nil
	}

	if membershipUpdateDebouncer.Contains(membershipUpdate.GroupId) {
		return nil
	}
	defer func() {
		if err == nil {
			membershipUpdateDebouncer.Add(membershipUpdate.GroupId, struct{}{})
		}
	}()

	// Membership updates often come in large bursts from big Enterprises.
	// By shifting the work to Aqueduct it allows us to continue to process other high priority messages when this
	// happens. Have quite a big max queue depth here (1000) as the sync job will catch any messages that are lost

	// The aqueduct job will be handled by membershipUpdateJob, below.
	return errors.Wrap(p.EnqueueJob(ctx, membershipUpdate, 1000), "failed to enqueue MembershipUpdate job")
}

func (p *Processor) membershipUpdateJob(ctx context.Context, membershipUpdate *githubv1.MembershipUpdate) error {
	return errors.Wrap(p.syncOrganization(ctx, membershipUpdate.GroupId), "failed to process MembershipUpdate")
}
