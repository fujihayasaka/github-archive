package newsiesservice

import (
	"context"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
)

func Test_Watch(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	userID := int64(1)
	refID := int64(1)

	setup := func(settingsSvc routing.SettingsService, subscriptionsSvc subscriptions.Service) *Service {
		return &Service{
			statter:          stats.NullStatter,
			clock:            clock.New(),
			routingSvc:       settingsSvc,
			subscriptionsSvc: subscriptionsSvc,
		}
	}

	ignoreCfQuery := ignoreQuery(refID)
	watchCfQuery := watchQuery(refID)

	cases := []struct {
		name  string
		setup func(t *testing.T) (routing.SettingsService, subscriptions.Service)
	}{
		{
			name: "without existing ignores",
			setup: func(t *testing.T) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{},
						mock.MatchedBy(settingsQueryMatcher(t, ignoreCfQuery)),
					).Return([]int64{}, nil)

				subscription, err := newSubscription(userID, []ThreadType{}, refID, "Repository", []subscriptions.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				})
				r.NoError(err)

				subscriptionsSvc.
					On(
						"BatchReplace", mock.Anything, userID,
						[]*subscriptions.MetaSubscription{subscription},
						mock.MatchedBy(subscriptionsQueryMatcher(t, watchCfQuery)),
					).
					Return([]int64{}, nil)

				return settingsSvc, subscriptionsSvc
			},
		},
		{
			name: "with existing ignores",
			setup: func(t *testing.T) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{},
						mock.MatchedBy(settingsQueryMatcher(t, ignoreCfQuery)),
					).Return([]int64{}, nil)

				subscription, err := newSubscription(userID, []ThreadType{}, refID, "Repository", []subscriptions.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				})
				r.NoError(err)

				subscriptionsSvc.
					On(
						"BatchReplace", mock.Anything, userID,
						[]*subscriptions.MetaSubscription{subscription},
						mock.MatchedBy(subscriptionsQueryMatcher(t, watchCfQuery)),
					).Return([]int64{}, nil)

				return settingsSvc, subscriptionsSvc
			},
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			settingsSvc, subscriptionsSvc := test.setup(t)
			svc := setup(settingsSvc, subscriptionsSvc)

			err := svc.Watch(ctx, userID, refID, "Repository", []ThreadType{}, []subscriptions.CustomField{
				{Name: "owner_id", Value: "1"},
				{Name: "owner_type", Value: "user"},
			})
			r.NoError(err)
		})
	}

	errCases := []struct {
		name  string
		setup func(*testing.T, error) (routing.SettingsService, subscriptions.Service)
		error error
	}{
		{
			name: "cleaning up ignores fails",
			setup: func(t *testing.T, err error) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{},
						mock.MatchedBy(settingsQueryMatcher(t, ignoreCfQuery)),
					).Return([]int64{}, err)

				return settingsSvc, subscriptionsSvc
			},
			error: errors.New("deleting meta routing settings"),
		},
		{
			name: "adding new subscription fails",
			setup: func(t *testing.T, err error) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{},
						mock.MatchedBy(settingsQueryMatcher(t, ignoreCfQuery)),
					).Return([]int64{}, nil)

				subscriptionsSvc.
					On("BatchReplace", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(nil, err)

				return settingsSvc, subscriptionsSvc
			},
			error: errors.New("adding new subscription failed"),
		},
	}

	for _, test := range errCases {
		t.Run(test.name, func(t *testing.T) {
			settingsSvc, subscriptionsSvc := test.setup(t, test.error)
			svc := setup(settingsSvc, subscriptionsSvc)

			err := svc.Watch(ctx, userID, refID, "Repository", []ThreadType{}, []subscriptions.CustomField{
				{Name: "owner_id", Value: "1"},
				{Name: "owner_type", Value: "user"},
			})
			r.ErrorIs(err, test.error)
		})
	}
}

func Test_Unwatch(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	userID := int64(1)
	refID := int64(1)

	setup := func(settingsSvc routing.SettingsService, subscriptionsSvc subscriptions.Service) *Service {
		return &Service{
			statter:          stats.NullStatter,
			clock:            clock.New(),
			routingSvc:       settingsSvc,
			subscriptionsSvc: subscriptionsSvc,
		}
	}

	ignoreCfQuery := ignoreQuery(refID)
	watchCfQuery := watchQuery(refID)
	labelsCfQuery := labelsQuery(refID)

	cases := []struct {
		name  string
		setup func(t *testing.T) (routing.SettingsService, subscriptions.Service)
	}{
		{
			name: "ignore settings and subscriptions are being replaced",
			setup: func(t *testing.T) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{},
						mock.MatchedBy(settingsQueryMatcher(t, ignoreCfQuery)),
					).Return([]int64{}, nil)

				subscriptionsSvc.
					On(
						"BatchReplace", mock.Anything, userID,
						[]*subscriptions.MetaSubscription{},
						mock.MatchedBy(subscriptionsQueryMatcher(t, watchCfQuery)),
					).Return([]int64{}, nil)

				subscriptionsSvc.
					On(
						"BatchReplace", mock.Anything, userID,
						[]*subscriptions.MetaSubscription{},
						mock.MatchedBy(subscriptionsQueryMatcher(t, labelsCfQuery)),
					).Return([]int64{}, nil)

				return settingsSvc, subscriptionsSvc
			},
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			settingsSvc, subscriptionsSvc := test.setup(t)
			svc := setup(settingsSvc, subscriptionsSvc)

			err := svc.Unwatch(ctx, userID, []int64{refID}, "Repository")
			r.NoError(err)
		})
	}

	errCases := []struct {
		name  string
		setup func(*testing.T, error) (routing.SettingsService, subscriptions.Service)
		error error
	}{
		{
			name: "cleaning up ignores fails",
			setup: func(t *testing.T, err error) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{},
						mock.MatchedBy(settingsQueryMatcher(t, ignoreCfQuery)),
					).Return([]int64{}, err)

				return settingsSvc, subscriptionsSvc
			},
			error: errors.New("deleting meta routing settings"),
		},
		{
			name: "deleting subscription fails",
			setup: func(t *testing.T, err error) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{},
						mock.MatchedBy(settingsQueryMatcher(t, ignoreCfQuery)),
					).Return([]int64{}, nil)

				subscriptionsSvc.
					On("BatchReplace", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(nil, err)

				return settingsSvc, subscriptionsSvc
			},
			error: errors.New("adding new subscription failed"),
		},
	}

	for _, test := range errCases {
		t.Run(test.name, func(t *testing.T) {
			settingsSvc, subscriptionsSvc := test.setup(t, test.error)
			svc := setup(settingsSvc, subscriptionsSvc)

			err := svc.Unwatch(ctx, userID, []int64{refID}, "Repository")
			r.ErrorIs(err, test.error)
		})
	}
}

func Test_UnwatchAll(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	userID := int64(1)

	setup := func(settingsSvc routing.SettingsService, subscriptionsSvc subscriptions.Service) *Service {
		return &Service{
			statter:          stats.NullStatter,
			clock:            clock.New(),
			routingSvc:       settingsSvc,
			subscriptionsSvc: subscriptionsSvc,
		}
	}

	ignoreCfQuery := ignoreQuery(0)
	watchCfQuery := watchQuery(0)
	labelsCfQuery := labelsQuery(0)

	cases := []struct {
		name  string
		setup func(t *testing.T) (routing.SettingsService, subscriptions.Service)
	}{
		{
			name: "subscriptions and settings are replaced",
			setup: func(t *testing.T) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{},
						mock.MatchedBy(settingsQueryMatcher(t, ignoreCfQuery)),
					).Return([]int64{}, nil)

				subscriptionsSvc.
					On(
						"BatchReplace", mock.Anything, userID,
						[]*subscriptions.MetaSubscription{},
						mock.MatchedBy(subscriptionsQueryMatcher(t, watchCfQuery)),
					).
					Return([]int64{}, nil)

				subscriptionsSvc.
					On(
						"BatchReplace", mock.Anything, userID,
						[]*subscriptions.MetaSubscription{},
						mock.MatchedBy(subscriptionsQueryMatcher(t, labelsCfQuery)),
					).
					Return([]int64{}, nil)

				return settingsSvc, subscriptionsSvc
			},
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			settingsSvc, subscriptionsSvc := test.setup(t)
			svc := setup(settingsSvc, subscriptionsSvc)

			err := svc.UnwatchAll(ctx, userID, "Repository")
			r.NoError(err)
		})
	}

	errCases := []struct {
		name  string
		setup func(*testing.T, error) (routing.SettingsService, subscriptions.Service)
		error error
	}{
		{
			name: "cleaning up ignores fails",
			setup: func(t *testing.T, err error) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{},
						mock.MatchedBy(settingsQueryMatcher(t, ignoreCfQuery)),
					).Return([]int64{}, err)

				return settingsSvc, subscriptionsSvc
			},
			error: errors.New("deleting meta routing settings"),
		},
		{
			name: "deleting subscription fails",
			setup: func(t *testing.T, err error) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{},
						mock.MatchedBy(settingsQueryMatcher(t, ignoreCfQuery)),
					).Return([]int64{}, nil)

				subscriptionsSvc.
					On("BatchReplace", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(nil, err)

				return settingsSvc, subscriptionsSvc
			},
			error: errors.New("adding new subscription failed"),
		},
	}

	for _, test := range errCases {
		t.Run(test.name, func(t *testing.T) {
			settingsSvc, subscriptionsSvc := test.setup(t, test.error)
			svc := setup(settingsSvc, subscriptionsSvc)

			err := svc.UnwatchAll(ctx, userID, "Repository")
			r.ErrorIs(err, test.error)
		})
	}
}

func Test_Ignore(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	userID := int64(1)
	refID := int64(1)

	setup := func(settingsSvc routing.SettingsService, subscriptionsSvc subscriptions.Service) *Service {
		return &Service{
			statter:          stats.NullStatter,
			clock:            clock.New(),
			routingSvc:       settingsSvc,
			subscriptionsSvc: subscriptionsSvc,
		}
	}

	cases := []struct {
		name  string
		setup func(t *testing.T) (routing.SettingsService, subscriptions.Service)
	}{
		{
			name: "ignore settings are replaced",
			setup: func(t *testing.T) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				query := ignoreQuery(refID)

				ignore := newIgnore(userID, "Repository", refID, []routing.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				})

				settingsSvc.
					On("BatchReplace", mock.Anything,
						userID,
						[]*routing.MetaSetting{ignore},
						mock.MatchedBy(settingsQueryMatcher(t, query)),
					).Return([]int64{}, nil)

				watchCf := watchQuery(refID)
				subscriptionsSvc.
					On(
						"BatchReplace", mock.Anything, userID,
						[]*subscriptions.MetaSubscription{},
						mock.MatchedBy(subscriptionsQueryMatcher(t, watchCf)),
					).Return([]int64{}, nil)

				labelsCf := labelsQuery(refID)
				subscriptionsSvc.
					On(
						"BatchReplace", mock.Anything, userID,
						[]*subscriptions.MetaSubscription{},
						mock.MatchedBy(subscriptionsQueryMatcher(t, labelsCf)),
					).Return([]int64{}, nil)

				return settingsSvc, subscriptionsSvc
			},
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			settingsSvc, subscriptionsSvc := test.setup(t)
			svc := setup(settingsSvc, subscriptionsSvc)

			err := svc.Ignore(ctx, userID, refID, "Repository", []routing.CustomField{
				{Name: "owner_id", Value: "1"},
				{Name: "owner_type", Value: "user"},
			})
			r.NoError(err)
		})
	}

	errCases := []struct {
		name  string
		setup func(*testing.T, error) (routing.SettingsService, subscriptions.Service)
		error error
	}{
		{
			name: "upserting ignore fails",
			setup: func(t *testing.T, err error) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, err)

				return settingsSvc, subscriptionsSvc
			},
			error: errors.New("upserting ignore"),
		},
		{
			name: "deleting subscription fails",
			setup: func(t *testing.T, err error) (routing.SettingsService, subscriptions.Service) {
				settingsSvc := routing.NewServiceMock(t)
				subscriptionsSvc := subscriptions.NewServiceMock(t)

				settingsSvc.
					On("BatchReplace", mock.Anything,
						mock.Anything, mock.Anything, mock.Anything,
					).Return([]int64{}, nil)

				subscriptionsSvc.
					On("BatchReplace", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(nil, err)

				return settingsSvc, subscriptionsSvc
			},
			error: errors.New("cleaning up subscription failed"),
		},
	}

	for _, test := range errCases {
		t.Run(test.name, func(t *testing.T) {
			settingsSvc, subscriptionsSvc := test.setup(t, test.error)
			svc := setup(settingsSvc, subscriptionsSvc)

			err := svc.Ignore(ctx, userID, refID, "Repository", []routing.CustomField{
				{Name: "owner_id", Value: "1"},
				{Name: "owner_type", Value: "user"},
			})
			r.ErrorIs(err, test.error)
		})
	}
}

// NOTE: This set of mock matchers all return `interface{}` as it is the way that `mock.MatchedBy`
// expects the matcher to be passed.

// settingsQueryMatcher ensures that the expected slice of CustomFields and the received one are
// identical in terms of name/value pairs.
func settingsQueryMatcher(t *testing.T, expected []routing.CustomField) func(recv []routing.CustomField) bool {
	t.Helper()
	return func(recv []routing.CustomField) bool {
		for i, field := range recv {
			if expected[i].Name != field.Name || expected[i].Value != field.Value {
				return false
			}
		}
		return true
	}
}

// subscriptionsQueryMatcher ensures that the expected slice of CustomFields and the received one are
// identical in terms of name/value pairs.
func subscriptionsQueryMatcher(t *testing.T, expected []subscriptions.CustomField) interface{} {
	t.Helper()
	return func(recv []subscriptions.CustomField) bool {
		for i, field := range recv {
			if expected[i].Name != field.Name || expected[i].Value != field.Value {
				return false
			}
		}
		return true
	}
}
