package processor

import (
	"context"
	"time"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	lru "github.com/hashicorp/golang-lru/v2/expirable"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("github.v1.RepositoryAddMember")

var repositoryAddMemberDebouncer = lru.NewLRU[uint32, struct{}](1024, nil, 5*time.Second)

func (p *Processor) repositoryAddMember(ctx context.Context, repositoryAddMember *githubv1.RepositoryAddMember) (err error) {
	if repositoryAddMember.Repository.OwnerId == nil {
		return nil
	}

	if repositoryAddMemberDebouncer.Contains(repositoryAddMember.Repository.OwnerId.Value) {
		return nil
	}
	defer func() {
		if err == nil {
			repositoryAddMemberDebouncer.Add(repositoryAddMember.Repository.OwnerId.Value, struct{}{})
		}
	}()

	return errors.Wrap(p.syncOrganization(ctx, uint64(repositoryAddMember.Repository.OwnerId.Value)), "failed to process RepositoryAddMember")
}
