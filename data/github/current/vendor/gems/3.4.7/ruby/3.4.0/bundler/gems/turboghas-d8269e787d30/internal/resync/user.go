package resync

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fields"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/pkg/errors"
)

func (p *Sync) User(ctx context.Context, userID uint64) (bool, error) {
	resp, err := p.githubAPI.GetUsers(ctx, &twirpTurboghas.GetUsersRequest{
		UserIds: []uint64{userID},
	})
	if err != nil {
		return false, errors.Wrap(err, "failed to get user information")
	}

	return syncUser(ctx, p.db, userID, resp.GetUsers())
}

func syncUser(ctx context.Context, db *data.Data, userID uint64, users map[uint64]*twirpTurboghas.GetUsersResponse_User) (found bool, err error) {
	defer func() {
		err = fields.Error(err, kvp.Uint64("gh.user.id", userID))
	}()

	user, ok := users[userID]
	if !ok {
		return false, errors.Wrap(db.DeleteUser(ctx, data.UserID(userID)), "failed to delete user")
	}

	if upsertErr := db.UpsertUser(ctx, data.UpsertUserArgs{
		UserID: data.UserID(userID),
		Login:  user.Login,
		Type:   user.Type,
	}); upsertErr != nil {
		return false, errors.Wrap(upsertErr, "failed to update repository")
	}

	return true, nil
}

func (p *Sync) Users(ctx context.Context, userIDs []uint64) error {
	if len(userIDs) == 0 {
		return nil
	}

	resp, err := p.githubAPI.GetUsers(ctx, &twirpTurboghas.GetUsersRequest{
		UserIds: userIDs,
	})
	if err != nil {
		return err
	}

	users := resp.GetUsers()

	for _, userID := range userIDs {
		if _, err := syncUser(ctx, p.db, userID, users); err != nil {
			return err
		}
	}
	return nil
}
