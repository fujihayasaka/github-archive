package t2022_05_12_team_ship_notification_filters //nolint:revive,stylecheck // allow underscores

import (
	"github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/routing"
)

// team contains usernames and their corresponding user IDs
var team = map[string]int64{
	"abeaumont":       80059,
	"almaleksia":      1885174,
	"dev-tim":         5173831,
	"franciscoj":      186087,
	"geramirez":       4596845,
	"gerbenjacobs":    715095,
	"irynakulakova":   52420926,
	"jezcommits":      8514581,
	"jhbabon":         280452,
	"mrsimonfletcher": 1643158,
	"mrtazz":          68183,
}

var mutedUsers = map[string]int32{
	"not-artem": 107037492,
}

// global users are going to participate in not busy repos so it's fine to enable them
var globalEnabledUsers = map[string]int32{
	"artem-artem":   73656928,
	"guppy-ramirez": 89043693,
	"ksenia-ksenia": 96623832,
}

// repos contains owner/repo names along with their repository ID
var repos = map[string]int{
	"github/notifyd":                              345743061, // failed - email, success - nothing
	"team-discussions/a-repo":                     89946774,  // failed - nothing, success - email, non existing use-case
	"team-discussions/notifications-go-test-repo": 346647269, // success - email, failed - email
	"team-discussions/react":                      409895466, // do not notify anybody on this repo
}

// usecases contains all the use cases we want to check
var usecases []*routing.MetaSetting

// init is run when this file is loaded and will create our use cases
func init() { //nolint:gochecknoinits // preserve historical transition
	for login := range team {
		// For Notifyd repo we are matching default settings
		usecases = append(usecases,
			mrsFailedCIActivity(login, []string{"github/notifyd"}, []string{"ci_activity", "approval_requested"}, channelEmail(true)),

			// For team-discussions/a-repo repo we are want to match only success notifications
			mrsSuccessOnlyCIActivity(login, []string{"team-discussions/a-repo"}, []string{"ci_activity", "approval_requested"}, channels(b(true), b(true))),
			mrsFailedCIActivity(login, []string{"team-discussions/a-repo"}, []string{"ci_activity", "approval_requested"}, channelEmail(false)),

			// For team-discussions/notifications-go-test-repo we enable all the cases
			mrsCIActivity(login, []string{"team-discussions/notifications-go-test-repo"}, []string{"ci_activity", "approval_requested"}, channelEmail(true)),

			// team-discussions/react
			mrsCIActivity(login, []string{"team-discussions/react"}, []string{"ci_activity", "approval_requested"}, channelEmail(false)),
		)
	}

	for login := range mutedUsers {
		usecases = append(usecases, mrsCIActivity(login, []string{}, []string{"ci_activity", "approval_requested"}, channelEmail(false)))
	}

	for login := range globalEnabledUsers {
		usecases = append(usecases, mrsCIActivity(login, []string{}, []string{"ci_activity", "approval_requested"}, channelEmail(false)))
	}
}

func channels(email, push *bool) dto.ChannelsMap {
	res := make(dto.ChannelsMap)
	if push != nil {
		res["PUSH"] = &dto.Channel{Channel: "PUSH", Enabled: *push}
	}

	if email != nil {
		res["EMAIL"] = &dto.Channel{Channel: "EMAIL", Enabled: *email}
	}

	return res
}

func channelEmail(email bool) dto.ChannelsMap {
	return channels(b(email), b(false))
}

func b(b bool) *bool {
	boolVar := b
	return &boolVar
}
