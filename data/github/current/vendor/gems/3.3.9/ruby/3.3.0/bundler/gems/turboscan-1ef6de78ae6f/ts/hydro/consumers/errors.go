package consumers

import (
	"github.com/pkg/errors"
)

var (
	ErrRepoDisabled         = errors.New("repo_disabled")
	ErrIgnoredEvent         = errors.New("ignored_event")
	ErrDependabotEvent      = errors.New("dependabot_event")
	ErrForkedRepoEvent      = errors.New("forked_repo_event")
	ErrNoMatchingAlertLinks = errors.New("no_matching_alert_links")
)
