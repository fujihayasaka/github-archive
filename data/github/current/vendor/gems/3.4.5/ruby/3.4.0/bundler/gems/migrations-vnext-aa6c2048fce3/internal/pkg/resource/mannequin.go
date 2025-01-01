package resource

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/twitchtv/twirp"
)

type mannequin struct {
	baseHandler
	pb            *v1.Mannequin
	importedLogin string
}

var _ handler = (*mannequin)(nil)

func newMannequin(pb *v1.Mannequin, logger log.Logger) *mannequin {
	return &mannequin{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (m *mannequin) resourceID() string {
	return m.pb.ResourceId
}

func (m *mannequin) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(m.pb.OrgResourceId)
	return deps, nil
}

func (m *mannequin) load(ctx context.Context, importer client.Importer, deps resolvedIDsByResource) error {
	k, err := keys.ToMannequinKey(m.resourceID())
	if err != nil {
		return fmt.Errorf("could not parse mannequin key: %w", err)
	}

	req := &octov1.CreateMannequinRequest{
		SourceLogin: k.UserLogin,
		OwnerId:     deps[m.pb.OrgResourceId].int64Val,
		ProfileName: m.pb.ProfileName,
		Email:       m.pb.Email,
	}

	res, err := importer.CreateMannequin(ctx, req)
	if err == nil {
		m.importedLogin = res.Mannequin.Login

		return nil
	}

	if !isTwirpMannequinAlreadyCreatedError(err) {
		return fmt.Errorf("could not create mannequin: %w", err)
	}

	found, err := importer.FindMannequin(ctx, &octov1.FindMannequinRequest{
		SourceLogin: k.UserLogin,
		OwnerId:     deps[m.pb.OrgResourceId].int64Val,
	})
	if err != nil {
		return fmt.Errorf("could not find mannequin: %w", err)
	}

	m.importedLogin = found.Mannequin.Login

	return nil
}

// isTwirpMannequinAlreadyCreatedError returns true if the error is the
// octoshift_error_code is ALREADY_EXISTS
func isTwirpMannequinAlreadyCreatedError(err error) bool {
	var twerr twirp.Error
	if !errors.As(err, &twerr) {
		return false
	}
	return twerr.Meta("octoshift_error_code") == "ALREADY_EXISTS"
}

func (m *mannequin) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		m.resourceID(): &transformedValues{
			strVal: m.importedLogin,
		},
	}
}
