package routingsettingsserver

import (
	"github.com/github/notifyd/internal/pkg/errors"
)

var (
	errNoUserID                       = errors.New("user id must be specified")
	errNoTopic                        = errors.New("at least one topic must be specified")
	errInvalidTopic                   = errors.New("type and value must be specified for each topic")
	errInvalidFilter                  = errors.New("subject type and trigger must be specified for each filter")
	errInvalidMatchRule               = errors.New("attribute, value and match_rule must be specified for each match rule")
	errInvalidCustomFieldForSearching = errors.New("name must be specified for each custom field search")
	errInvalidCustomFieldForSaving    = errors.New("name and value be specified for each saved custom field")
	errInvalidNoChannels              = errors.New("channels must be provided for routing setting")
	errInvalidTooManyChannels         = errors.New("too many channels provided")
	errDuplicatedChannels             = errors.New("duplicated channels provided")
	errInvalidEmptyChannelName        = errors.New("channels should have valid non empty name")
)
