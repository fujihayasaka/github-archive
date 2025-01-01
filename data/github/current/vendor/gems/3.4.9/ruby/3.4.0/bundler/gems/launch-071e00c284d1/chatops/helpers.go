package chatops

import (
	"net/url"
	"strings"

	errs "github.com/pkg/errors"

	"github.com/github/launch/types"
)

func parseRepo(repo string) (types.RepositoryFullName, error) {
	if repoURL, err := url.ParseRequestURI(repo); err == nil {
		repo = strings.Trim(repoURL.Path, "/")
	}

	nwo, err := types.ParseNWO(repo)
	if err != nil {
		if strings.Contains(err.Error(), "Invalid RepositoryFullName") {
			err = errs.Errorf("%s is not a valid repository. Format should be `foo/bar` or `https://github.com/foo/bar`", repo)
		}
		return types.RepositoryFullName{}, err
	}

	return nwo, nil
}
