// Package dto contains data transfer objects for the match engine.
package dto

import (
	"github.com/github/notifyd/internal/pkg/mysql"
)

// ChannelsMap is a map of channel name to Channel.
type ChannelsMap map[string]*Channel

// Channel represents a channel.
type Channel struct {
	ID               int64  `db:"id"`
	RoutingSettingID int64  `db:"routing_setting_id" json:"-"`
	Channel          string `db:"channel"`
	Enabled          bool   `db:"enabled"`
	mysql.Timestamps
}

// MapChannelsByRoutingSettingID maps channels by RoutingSettingID.
func MapChannelsByRoutingSettingID(channels []*Channel) map[int64][]Channel {
	res := make(map[int64][]Channel)
	for _, c := range channels {
		if _, ok := res[c.RoutingSettingID]; !ok {
			res[c.RoutingSettingID] = make([]Channel, 0)
		}
		res[c.RoutingSettingID] = append(res[c.RoutingSettingID], *c)
	}

	return res
}
