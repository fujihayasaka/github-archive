package routing

import (
	context "context"
	"fmt"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/github/notifyd/internal/pkg/featureflags"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	matchengine "github.com/github/notifyd/internal/pkg/notify/matchengine"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	testsuite "github.com/stretchr/testify/suite"
)

type RoutingSetChannelsSuite struct {
	testsuite.Suite
	testhelper.DatabaseSuite
}

func (suite *RoutingSetChannelsSuite) TestRoutingService_setChannels() {
	db := suite.DB()
	ctx := context.Background()

	setup := func() *storage {
		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_channels",
			"routing_setting_match_rules",
			"routing_setting_custom_fields",
		}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		store := NewStorage(clock.NewMock(), logs.NullTelem, db)
		if storage, ok := store.(*storage); ok {
			return storage
		}
		panic("failed to cast store to *storage")
	}

	storage := setup()

	featuresClient := new(featureflags.ClientMock)
	service := NewRoutingService(storage, logs.NullTelem, stats.NullStatter, featuresClient)

	matchEntries := []*matchengine.MatchedEntry{
		{UserID: 1, RefID: 1, Reason: "ci_activity", Attribute: "", Value: "", MatchRule: ""},
	}

	channels := []matchengine_dto.Channel{{
		ID:               1,
		RoutingSettingID: 1,
		Channel:          "EMAIL",
		Enabled:          false,
	}, {
		ID:               2,
		RoutingSettingID: 1,
		Channel:          "WEB",
		Enabled:          false,
	}}
	expected := map[string]*matchengine_dto.Channel{
		"EMAIL": &channels[0],
		"WEB":   &channels[1],
	}

	setting := MetaSetting{
		ID:     1,
		UserID: 1,
		Name:   "Global setting for CI activities - CheckSuite",
		Details: SettingDetails{
			Channels: expected,
			Topics: []Topic{
				{Type: "any", Value: "any"},
			},
			Filters: []SettingFilter{
				{Reason: "ci_activity"},
			},
		},
	}

	_, err := storage.Create(ctx, &setting)
	suite.Require().NoError(err)

	routingService := service.(routingService)
	err = routingService.setChannels(ctx, matchEntries, []int64{1})
	suite.Require().NoError(err)
	assertChannels(suite.Require(), matchEntries[0].Channels, expected)
}

func TestRoutingSettingsTestSuiteSetChannels(t *testing.T) {
	testsuite.Run(t, new(RoutingSetChannelsSuite))
}
