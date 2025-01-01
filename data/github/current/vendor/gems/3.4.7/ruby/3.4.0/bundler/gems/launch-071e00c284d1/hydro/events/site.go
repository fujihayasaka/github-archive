package events

import (
	errs "github.com/pkg/errors"

	"github.com/github/launch/utils/metadata"
)

// TODO: This is coming back, so ignoring linter for now.
func getSite() (string, error) { //nolint: deadcode,megacheck
	site := metadata.GetSite()
	if len(site) < 1 {
		// This should never happen, unless the current app forgot to call `metadata.Init()`. :(
		return "", errs.New("Site is not defined!")
	}
	return site, nil
}
