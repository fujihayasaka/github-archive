package notify

import (
	"context"
	"testing"
	"time"

	"github.com/benbjohnson/clock"
	ghaqueduct "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/go-stats"
	ghhydro "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	pbany "google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
	wrappers "google.golang.org/protobuf/types/known/wrapperspb"

	schema_pb_v0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	schema_pb_v1 "github.com/github/notifyd/hydro/schemas/notifyd/v1"
	schema_pb_v1_entities "github.com/github/notifyd/hydro/schemas/notifyd/v1/entities"

	entities_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"

	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/structpb"

	basicEmail "github.com/github/notifyd/internal/email/layout/basic"
	basicMobile "github.com/github/notifyd/internal/mobile/layout/basic"
	"github.com/github/notifyd/internal/pkg/aqueduct"
	"github.com/github/notifyd/internal/pkg/compress"
	"github.com/github/notifyd/internal/pkg/dotcom/policy"
	"github.com/github/notifyd/internal/pkg/featureflags"
	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/auth"
	"github.com/github/notifyd/internal/pkg/notify/stages"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

func Test_HandleMessage(t *testing.T) {
	r := require.New(t)
	now := time.Now()
	type testChecks struct {
		authzd bool
		policy bool
	}

	app := "notifyd-test"

	inflate := func(job *ghaqueduct.Job) ([]byte, error) {
		encoding := job.Headers["content-encoding"]
		if encoding == "" {
			return job.Payload, nil
		}

		return compress.Decompress(compress.Encoding(encoding), job.Payload)
	}

	// Test cases here are structured to cover all the different checks we do on the processing
	// pipeline.
	//
	// On each iteration we add a new recipient who passes just one more check. We do that until all
	// the checks are tested and then we add a last recipient that passes everything and receives a
	// notification.
	tests := []struct {
		name                              string
		authorizableRecipientIDs          []int64
		newPolicyChecks                   auth.PolicyCheckLookup
		expectedCheckRecipients           notify.RecipientIDToReasons
		policyCheckResult                 map[int64]policy.CheckResult
		notifyMessage                     *schema_pb_v0.Notify
		expectedPushes                    []*schema_pb_v0.DeliverMobilePush
		expectedEmailDelivery             []*schema_pb_v0.DeliverEmail
		expectedWeb                       []*schema_pb_v1.DeliverWeb
		checks                            testChecks
		subscriptionRecipientIDs          []int64
		subscriptionRecipientIDsToReasons notify.RecipientIDToReasons
		recipientDeliveryMetadata         notify.RecipientToDeliveryMetadata
		useNewSubscriptions               bool
	}{
		{
			name: "Sends nothing when no explicit recipients are provided",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:              &schema_pb_v0.Notify_Actor{Id: 1},
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{},
			},
			subscriptionRecipientIDs: []int64{},
		},
		{
			name: "Sends nothing if the actor of the notification is the only recipient",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:              &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId:     "test-notification-id",
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{{Reason: "mention", UserIds: []int32{1}}},
			},
			subscriptionRecipientIDs: []int64{},
		},
		{
			name: "Sends notification if the actor of only recipient with enabled notify_actor feature switch",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context:        getContext(t),
				Rendering:      getRendering(t),
				Authorization:  &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:       getTracking(t, now),
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{1}},
				},
				FeatureSwiches: map[string]bool{"notify_actor": true},
			},
			authorizableRecipientIDs: []int64{1},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 1, Status: auth.Allow},
			},
			subscriptionRecipientIDs: []int64{1},
			expectedCheckRecipients:  notify.RecipientIDToReasons{1: []string{"mention"}},
			policyCheckResult: map[int64]policy.CheckResult{
				1: {IsDeliverable: true},
			},
			recipientDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				1: {
					Channels: routing.ToChannelsMap(map[string]bool{"PUSH": true, "EMAIL": false}),
					Reasons:  []string{"subscribed"},
				},
			},
			expectedPushes: []*schema_pb_v0.DeliverMobilePush{
				{
					UserId:          1,
					NotificationId:  "test-notification-id",
					Reasons:         []*entities_pb.Reason{{Name: "subscribed"}},
					LayoutData:      getMobileLayout(t),
					SamlEnforcement: getSkipSAMLEnforcement(t),
					Tracking:        getTracking(t, now),
				},
			},
			expectedEmailDelivery: []*schema_pb_v0.DeliverEmail{},
			checks:                testChecks{authzd: true, policy: true},
		},
		{
			name: "Sends only one notification for actor with enabled notify_actor and disabled notify_subscribers feature switches",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context:        getContext(t),
				Rendering:      getRendering(t),
				Authorization:  &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:       getTracking(t, now),
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{1}},
				},
				FeatureSwiches: map[string]bool{"notify_actor": true, "notify_subscribers": false},
			},
			authorizableRecipientIDs: []int64{1},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 1, Status: auth.Allow},
			},
			subscriptionRecipientIDs: []int64{1, 2},
			expectedCheckRecipients:  notify.RecipientIDToReasons{1: []string{"mention"}},
			policyCheckResult: map[int64]policy.CheckResult{
				1: {IsDeliverable: true},
			},
			recipientDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				1: {
					Channels: routing.ToChannelsMap(map[string]bool{"PUSH": true, "EMAIL": false}),
					Reasons:  []string{"subscribed"},
				},
			},
			expectedPushes: []*schema_pb_v0.DeliverMobilePush{
				{
					UserId:          1,
					NotificationId:  "test-notification-id",
					Reasons:         []*entities_pb.Reason{{Name: "subscribed"}},
					LayoutData:      getMobileLayout(t),
					SamlEnforcement: getSkipSAMLEnforcement(t),
					Tracking:        getTracking(t, now),
				},
			},
			expectedEmailDelivery: []*schema_pb_v0.DeliverEmail{},
			checks:                testChecks{authzd: true, policy: true},
		},
		{
			name: "Sends nothing if the actor of only recipient with disabled notify_actor feature switch",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:              &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId:     "test-notification-id",
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{{Reason: "mention", UserIds: []int32{1}}},
				FeatureSwiches:     map[string]bool{"notify_actor": false},
			},
			subscriptionRecipientIDs: []int64{},
		},
		{
			name: "Sends nothing if the actor and subscriber recipients and notify_actor and notify_subscribers feature switches are disabled",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{1}},
				},
				FeatureSwiches: map[string]bool{"notify_actor": false, "notify_subscribers": false},
			},
			subscriptionRecipientIDs: []int64{2},
		},
		{
			name: "Sends nothing if recipients are not authorized",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{1}},
					{Reason: "mention", UserIds: []int32{2}},
				},
				Context:       getContext(t),
				Rendering:     getRendering(t),
				Authorization: &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:      getTracking(t, now),
			},
			authorizableRecipientIDs: []int64{2},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 2, Status: auth.Deny},
			},
			subscriptionRecipientIDs: []int64{},
			checks:                   testChecks{authzd: true, policy: false},
		},
		{
			name: "Sends nothing if recipient does not pass policy",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{1}},
					{Reason: "mention", UserIds: []int32{2}},
					{Reason: "mention", UserIds: []int32{3}},
				},
				Context:       getContext(t),
				Rendering:     getRendering(t),
				Authorization: &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:      getTracking(t, now),
			},
			authorizableRecipientIDs: []int64{2, 3},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 2, Status: auth.Deny},
				{UserID: 3, Status: auth.Allow},
			},
			subscriptionRecipientIDs: []int64{},
			expectedCheckRecipients:  notify.RecipientIDToReasons{3: []string{"mention"}},
			policyCheckResult:        map[int64]policy.CheckResult{3: {IsDeliverable: false}, 4: {IsDeliverable: false}},
			checks:                   testChecks{authzd: true, policy: true},
		},
		{
			name: "Sends nothing if recipients are not authorized v2",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{1}},
					{Reason: "mention", UserIds: []int32{2}},
				},
				Context:       getContext(t),
				Rendering:     getRendering(t),
				Authorization: &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:      getTracking(t, now),
			},
			authorizableRecipientIDs: []int64{2},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 2, Status: auth.Deny},
			},
			policyCheckResult:        map[int64]policy.CheckResult{},
			subscriptionRecipientIDs: []int64{},
			checks:                   testChecks{authzd: true, policy: false},
		},
		{
			name: "Notifies to recipient who is authorized, passes policy and not self mentioning",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{1}},
					{Reason: "mention", UserIds: []int32{2}},
					{Reason: "mention", UserIds: []int32{3}},
					{Reason: "mention", UserIds: []int32{4}},
				},
				Context:       getContext(t),
				Rendering:     getRendering(t),
				Authorization: &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:      getTracking(t, now),
			},
			authorizableRecipientIDs: []int64{2, 3, 4},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 2, Status: auth.Deny},
				{UserID: 3, Status: auth.Allow},
				{UserID: 4, Status: auth.Allow},
			},
			subscriptionRecipientIDs: []int64{},
			expectedCheckRecipients: notify.RecipientIDToReasons{
				3: []string{"mention"},
				4: []string{"mention"},
			},
			policyCheckResult: map[int64]policy.CheckResult{
				3: {IsDeliverable: false},
				4: {IsDeliverable: true},
			},
			recipientDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				4: {Channels: routing.ToChannelsMap(map[string]bool{"PUSH": true}), Reasons: []string{"mention"}},
			},
			expectedPushes: []*schema_pb_v0.DeliverMobilePush{
				{
					UserId:          4,
					NotificationId:  "test-notification-id",
					Reasons:         []*entities_pb.Reason{{Name: "mention"}},
					LayoutData:      getMobileLayout(t),
					SamlEnforcement: getSkipSAMLEnforcement(t),
					Tracking:        getTracking(t, now),
				},
			},
			checks: testChecks{authzd: true, policy: true},
		},
		{
			name: "Notifies to recipient who is authorized, passes policy and not self mentioning v2",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{1}},
					{Reason: "mention", UserIds: []int32{2}},
					{Reason: "mention", UserIds: []int32{3}},
					{Reason: "mention", UserIds: []int32{4}},
				},
				Context:       getContext(t),
				Rendering:     getRendering(t),
				Authorization: &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:      getTracking(t, now),
			},
			authorizableRecipientIDs: []int64{2, 3, 4},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 2, Status: auth.Deny},
				{UserID: 3, Status: auth.Allow},
				{UserID: 4, Status: auth.Allow},
			},
			policyCheckResult: map[int64]policy.CheckResult{
				3: {IsDeliverable: false},
				4: {IsDeliverable: true},
			},
			subscriptionRecipientIDs: []int64{},
			expectedCheckRecipients: notify.RecipientIDToReasons{
				3: []string{"mention"},
				4: []string{"mention"},
			},
			recipientDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				4: {Channels: routing.ToChannelsMap(map[string]bool{"PUSH": true}), Reasons: []string{"mention"}},
			},
			expectedPushes: []*schema_pb_v0.DeliverMobilePush{
				{
					UserId:          4,
					NotificationId:  "test-notification-id",
					Reasons:         []*entities_pb.Reason{{Name: "mention"}},
					LayoutData:      getMobileLayout(t),
					SamlEnforcement: getSkipSAMLEnforcement(t),
					Tracking:        getTracking(t, now),
				},
			},
			checks: testChecks{authzd: true, policy: true},
		},
		{
			name: "Does not deliver email if the email layout is missing",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{1}},
					{Reason: "mention", UserIds: []int32{2}},
					{Reason: "mention", UserIds: []int32{3}},
					{Reason: "mention", UserIds: []int32{4}},
				},
				Context:       getContext(t),
				Rendering:     &schema_pb_v0.Notify_Rendering{Mobile: getMobileLayout(t)},
				Authorization: &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:      getTracking(t, now),
			},
			authorizableRecipientIDs: []int64{2, 3, 4},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 2, Status: auth.Deny},
				{UserID: 3, Status: auth.Allow},
				{UserID: 4, Status: auth.Allow},
			},
			subscriptionRecipientIDs: []int64{},
			expectedCheckRecipients: notify.RecipientIDToReasons{
				3: []string{"mention"},
				4: []string{"mention"},
			},
			policyCheckResult: map[int64]policy.CheckResult{
				3: {IsDeliverable: false},
				4: {IsDeliverable: true},
			},
			recipientDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				4: {Channels: routing.ToChannelsMap(map[string]bool{"PUSH": true, "EMAIL": true}), Reasons: []string{"mention"}},
			},
			expectedPushes: []*schema_pb_v0.DeliverMobilePush{
				{
					UserId:          4,
					NotificationId:  "test-notification-id",
					Reasons:         []*entities_pb.Reason{{Name: "mention"}},
					LayoutData:      getMobileLayout(t),
					SamlEnforcement: getSkipSAMLEnforcement(t),
					Tracking:        getTracking(t, now),
				},
			},
			expectedEmailDelivery: []*schema_pb_v0.DeliverEmail{},
			checks:                testChecks{authzd: true, policy: true},
		},
		{
			name: "Does not deliver email for mentions",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{1}},
					{Reason: "mention", UserIds: []int32{2}},
				},
				Context:       getContext(t),
				Rendering:     getRendering(t),
				Authorization: &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:      getTracking(t, now),
			},
			authorizableRecipientIDs: []int64{2},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 2, Status: auth.Allow},
			},
			expectedCheckRecipients: notify.RecipientIDToReasons{2: []string{"mention"}},
			policyCheckResult: map[int64]policy.CheckResult{
				2: {IsDeliverable: true},
			},
			recipientDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				2: {Channels: routing.ToChannelsMap(map[string]bool{"PUSH": true, "EMAIL": false}), Reasons: []string{"mention"}}},
			expectedPushes: []*schema_pb_v0.DeliverMobilePush{
				{
					UserId:          2,
					NotificationId:  "test-notification-id",
					Reasons:         []*entities_pb.Reason{{Name: "mention"}},
					LayoutData:      getMobileLayout(t),
					SamlEnforcement: getSkipSAMLEnforcement(t),
					Tracking:        getTracking(t, now),
				},
			},
			checks: testChecks{authzd: true, policy: true},
		},
		{
			name: "Notifies to recipients that are subscribed excluding the actor",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context:        getContext(t),
				Rendering:      getRendering(t),
				Authorization:  &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:       getTracking(t, now),
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2}},
				},
				Subject: &schema_pb_v0.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb_v0.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			authorizableRecipientIDs: []int64{2, 5},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 2, Status: auth.Deny},
				{UserID: 5, Status: auth.Allow},
			},
			subscriptionRecipientIDsToReasons: notify.RecipientIDToReasons{1: {"subscribed"}, 5: {"subscribed"}},
			recipientDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				5: {
					Channels: routing.ToChannelsMap(map[string]bool{"PUSH": true, "EMAIL": true, "WEB": true}),
					Reasons:  []string{"subscribed"},
				},
			},
			expectedCheckRecipients: notify.RecipientIDToReasons{5: []string{"subscribed"}},
			policyCheckResult: map[int64]policy.CheckResult{
				1: {IsDeliverable: true},
				5: {IsDeliverable: true},
			},
			expectedPushes: []*schema_pb_v0.DeliverMobilePush{
				{
					UserId:          5,
					NotificationId:  "test-notification-id",
					Reasons:         []*entities_pb.Reason{{Name: "subscribed"}},
					LayoutData:      getMobileLayout(t),
					SamlEnforcement: getSkipSAMLEnforcement(t),
					Tracking:        getTracking(t, now),
				},
			},
			expectedEmailDelivery: []*schema_pb_v0.DeliverEmail{
				{
					UserId:         5,
					NotificationId: "test-notification-id",
					Reasons:        []*entities_pb.Reason{{Name: "subscribed"}},
					SubjectType:    "Issue",
					LayoutData:     getEmailLayout(t),
					Tracking:       getTracking(t, now),
					MatchData:      &pbany.Any{},
				},
			},
			expectedWeb: []*schema_pb_v1.DeliverWeb{
				{
					NotificationId: "test-notification-id",
					Recipients: []*schema_pb_v1_entities.Recipient{
						{
							UserId:  5,
							Reasons: []string{"subscribed"},
						},
					},
					SubjectType: "Issue",
					SubjectId:   1,
					Tracking:    getTracking(t, now),
				},
			},
			checks: testChecks{authzd: true, policy: true},
		},
		{
			name: "Notifies to recipients that are subscribed with excluded Push channel based on routing settings",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context:        getContext(t),
				Rendering:      getRendering(t),
				Authorization:  &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:       getTracking(t, now),
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2}},
				},
				Subject: &schema_pb_v0.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb_v0.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			authorizableRecipientIDs: []int64{2, 5},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 2, Status: auth.Deny},
				{UserID: 5, Status: auth.Allow},
			},
			subscriptionRecipientIDsToReasons: notify.RecipientIDToReasons{1: {"subscribed"}, 5: {"subscribed"}},
			recipientDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				5: {
					Channels: routing.ToChannelsMap(map[string]bool{"PUSH": false, "EMAIL": true, "WEB": true}),
					Reasons:  []string{"subscribed"}},
			},
			expectedCheckRecipients: notify.RecipientIDToReasons{5: []string{"subscribed"}},
			policyCheckResult: map[int64]policy.CheckResult{
				1: {IsDeliverable: true},
				5: {IsDeliverable: true},
			},
			expectedPushes: []*schema_pb_v0.DeliverMobilePush{},
			expectedEmailDelivery: []*schema_pb_v0.DeliverEmail{
				{
					UserId:         5,
					NotificationId: "test-notification-id",
					Reasons:        []*entities_pb.Reason{{Name: "subscribed"}},
					SubjectType:    "Issue",
					LayoutData:     getEmailLayout(t),
					Tracking:       getTracking(t, now),
					MatchData:      &pbany.Any{},
				},
			},
			expectedWeb: []*schema_pb_v1.DeliverWeb{
				{
					NotificationId: "test-notification-id",
					Recipients: []*schema_pb_v1_entities.Recipient{
						{
							UserId:  5,
							Reasons: []string{"subscribed"},
						},
					}, SubjectType: "Issue",
					SubjectId: 1,
					Tracking:  getTracking(t, now),
				},
			},
			checks: testChecks{authzd: true, policy: true},
		},
		{
			name: "Skip all notifications for explicit recipients and subscriptions when routing settings are turned off",
			notifyMessage: &schema_pb_v0.Notify{
				Actor:          &schema_pb_v0.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context:        getContext(t),
				Rendering:      getRendering(t),
				Authorization:  &schema_pb_v0.Notify_Authorization{SamlEnforcement: getSkipSAMLEnforcement(t)},
				Tracking:       getTracking(t, now),
				ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2}},
				},
				Subject: &schema_pb_v0.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb_v0.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			authorizableRecipientIDs: []int64{2, 3, 5},
			newPolicyChecks: auth.PolicyCheckLookup{
				{UserID: 2, Status: auth.Allow},
				{UserID: 3, Status: auth.Allow},
				{UserID: 5, Status: auth.Allow},
			},
			subscriptionRecipientIDsToReasons: notify.RecipientIDToReasons{1: {"subscribed"}, 5: {"subscribed"}, 3: {"subscribed"}},
			recipientDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				5: {
					Channels: routing.ToChannelsMap(map[string]bool{"PUSH": false, "EMAIL": false}),
					Reasons:  []string{"subscribed"},
				},
				2: {
					Channels: routing.ToChannelsMap(map[string]bool{"PUSH": false, "EMAIL": false}),
					Reasons:  []string{"mention"},
				},
				3: {
					Channels: routing.ToChannelsMap(map[string]bool{"PUSH": false, "EMAIL": false}),
					Reasons:  []string{"subscribed"},
				},
			},
			expectedCheckRecipients: notify.RecipientIDToReasons{
				2: []string{"mention"},
				3: []string{"subscribed"},
				5: []string{"subscribed"},
			},
			policyCheckResult: map[int64]policy.CheckResult{
				1: {IsDeliverable: true},
				2: {IsDeliverable: true},
				3: {IsDeliverable: true},
				5: {IsDeliverable: true},
			},
			expectedPushes:        []*schema_pb_v0.DeliverMobilePush{},
			expectedEmailDelivery: []*schema_pb_v0.DeliverEmail{},
			checks:                testChecks{authzd: true, policy: true},
		},
	}

	for _, test := range tests {
		ctx := context.Background()

		t.Run(test.name, func(t *testing.T) {
			// Each channel can hold at most the number of possible messages per topic (one per recipient)
			pushesChannel := make(chan ghaqueduct.Job, len(test.notifyMessage.ExplicitRecipients))
			emailsChannel := make(chan ghaqueduct.Job, len(test.notifyMessage.ExplicitRecipients))
			webChannel := make(chan ghhydro.Message, len(test.notifyMessage.ExplicitRecipients))
			senderForPushes, err := aqueduct.BuildMemorySender(pushesChannel)
			r.NoError(err)
			senderForEmails, err := aqueduct.BuildMemorySender(emailsChannel)
			r.NoError(err)
			senderForWeb, err := hydro.BuildMemoryPublisher(webChannel)
			r.NoError(err)

			// We build an authorizer mock and we add a check for the right call in case this testcase
			// uses it
			authorizer := new(auth.AuthzdAuthorizerStub)
			if test.checks.authzd {
				authzAttributes := test.notifyMessage.Authorization.GetAuthzdAttributes()
				authorizer.On("AuthorizeRecipients", mock.Anything, mock.Anything, int64(test.notifyMessage.Actor.Id), test.authorizableRecipientIDs, authzAttributes).Return(test.newPolicyChecks, nil)
			}

			subscriptionsService := subscriptions.NewServiceMock(t)
			subscriptionsService.On("GetRecipientsWithReasons", mock.Anything, mock.Anything, mock.Anything).Return(test.subscriptionRecipientIDsToReasons, nil).Maybe()

			featuresClient := featureflags.NewClientMock(t)

			// We build a policy checker stub and set up the right call in case this test case uses it.
			policyChecker := policy.NewCheckerMock(t)
			if test.checks.policy && test.notifyMessage.Context != nil {
				policyChecker.On("BatchCheckIgnoredRepository", mock.Anything, mock.Anything, mock.Anything, test.expectedCheckRecipients).Return(policy.BatchCheckResult{UserIDToCheckResult: test.policyCheckResult}, nil)
			}

			// We build the message handler and make the call
			clock := clock.NewMock()
			telem := logs.NullTelem
			calculateRecipients := stages.NewCalculateRecipientsStage(subscriptionsService, clock, telem, stats.NullStatter, featuresClient)
			authorizeRecipients := stages.NewAuthorizeRecipientsStage(authorizer, clock, telem, stats.NullStatter)
			validateDotcomRecipients := stages.NewValidateDotcomRecipientPoliciesStage(policyChecker, clock, telem, stats.NullStatter)
			routeRecipientsToChannels := new(stages.RouteRecipientsToChannelsStageMock)
			routeRecipientsToChannels.On("RouteRecipientsToChannels", mock.Anything, mock.Anything, mock.Anything).Return(test.recipientDeliveryMetadata)

			metrics := metrics.NewPublisherMetrics(telem, stats.NullStatter)
			pushPublisher := stages.NewPushPublisher(senderForPushes, app, telem, metrics)
			emailPublisher := stages.NewEmailPublisher(senderForEmails, app, telem, metrics)
			webPubliser := stages.NewWebPublisher(senderForWeb, metrics)

			schedulePushNotifications := stages.NewSchedulePushNotificationsStage(stages.PushConfig{Enabled: true}, pushPublisher, clock, telem, stats.NullStatter)
			scheduleEmailNotifications := stages.NewScheduleEmailNotificationsStage(emailPublisher, clock, telem, stats.NullStatter)
			scheduleWebNotifications := stages.NewWebScheduler(webPubliser, clock, telem, stats.NullStatter)

			queueBatchedRecipientsStageMock := new(stages.QueueBatchedRecipientsStageMock)
			queueBatchedRecipientsStageMock.On("QueueBatchedRecipients", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

			routeRecipients := stages.NewRouteRecipientsStage(authorizeRecipients, routeRecipientsToChannels, schedulePushNotifications, scheduleEmailNotifications, scheduleWebNotifications, validateDotcomRecipients, clock, telem, stats.NullStatter, featuresClient)

			notificationService := NewNotificationService(calculateRecipients, authorizeRecipients, validateDotcomRecipients, routeRecipientsToChannels, scheduleEmailNotifications, schedulePushNotifications, scheduleWebNotifications, routeRecipients, queueBatchedRecipientsStageMock)
			consumer := NewHandler(notificationService, featuresClient, telem, stats.NullStatter)
			err = consumer.Run(ctx, tenancy.NewSingleTenant(), test.notifyMessage)
			r.NoError(err, "message handling doesn't err")

			var receivedPushes []*schema_pb_v0.DeliverMobilePush
			var receivedEmailDeliveries []*schema_pb_v0.DeliverEmail
			var receivedWeb []*schema_pb_v1.DeliverWeb
			close(pushesChannel)
			for job := range pushesChannel {
				r.Equal(aqueduct.QueueDeliverMobilePush, job.Queue)
				receivedPush := new(schema_pb_v0.DeliverMobilePush)
				payload, err := inflate(&job)
				r.NoError(err, "error inflating hydro message")
				err = hydro.UnmarshalBytes(payload, receivedPush)
				r.NoError(err, "error unmarshaling hydro message")
				receivedPushes = append(receivedPushes, receivedPush)
			}
			close(emailsChannel)
			for job := range emailsChannel {
				r.Equal(aqueduct.QueueDeliverEmail, job.Queue)
				payload, err := inflate(&job)
				r.NoError(err, "error inflating hydro message")
				recievedEmailDelivery := new(schema_pb_v0.DeliverEmail)
				err = hydro.UnmarshalBytes(payload, recievedEmailDelivery)
				r.NoError(err, "error unmarshaling hydro message")
				receivedEmailDeliveries = append(receivedEmailDeliveries, recievedEmailDelivery)
			}
			close(webChannel)
			for msg := range webChannel {
				webDelivery := new(schema_pb_v1.DeliverWeb)
				err = hydro.UnmarshalMessage(msg, webDelivery)
				r.NoError(err, "error unmarshaling hydro message")
				receivedWeb = append(receivedWeb, webDelivery)
			}

			if len(test.expectedPushes) == 0 {
				r.Empty(receivedPushes)
			} else {
				r.ElementsMatch(asBytes(t, test.expectedPushes), asBytes(t, receivedPushes))
			}

			if len(test.expectedEmailDelivery) == 0 {
				r.Empty(receivedEmailDeliveries)
			} else {
				// compare MatchData separately as it's a binary value
				expectedMatchData := getMatchData(t, test.notifyMessage)
				var actualMatchData structpb.Struct
				err = proto.Unmarshal(receivedEmailDeliveries[0].MatchData.GetValue(), &actualMatchData)
				r.NoError(err)
				r.Equal(expectedMatchData, &actualMatchData)
				receivedEmailDeliveries[0].MatchData = &pbany.Any{}
				r.ElementsMatch(asBytes(t, test.expectedEmailDelivery), asBytes(t, receivedEmailDeliveries))
			}

			r.Equal(len(test.expectedWeb), len(receivedWeb))
			r.ElementsMatch(asBytes(t, test.expectedWeb), asBytes(t, receivedWeb))

			passesPolicy := test.checks.policy
			for _, check := range test.policyCheckResult {
				passesPolicy = passesPolicy && check.IsDeliverable
			}

			assertPolicyCalls(t, policyChecker, test.checks.policy)
		})
	}
}

func Test_HandlerReturnsWhenRecipientsBatched(t *testing.T) {
	r := require.New(t)
	featuresClientMock := new(featureflags.ClientMock)

	notificationServiceMock := NewServiceMock(t)
	ctx := context.Background()
	userIDs := []int32{1, 2}

	recipients := schema_pb_v0.Notify_RecipientGroup{
		UserIds: userIDs,
		Reason:  "mention",
	}

	message := &schema_pb_v0.Notify{
		Actor:          &schema_pb_v0.Notify_Actor{Id: 99999},
		NotificationId: "test-notification-id",
		ExplicitRecipients: []*schema_pb_v0.Notify_RecipientGroup{
			&recipients,
		},
	}

	msg := notify.PBToNotification(message)
	notificationServiceMock.On("AddSubscribers", mock.Anything, msg.Recipients, msg).Return(nil)
	notificationServiceMock.On("QueueBatchedRecipients", mock.Anything, mock.Anything, msg.Recipients, message, mock.AnythingOfType("Batcher"))

	consumer := NewHandler(notificationServiceMock, featuresClientMock, logs.NullTelem, stats.NullStatter)
	consumer.batcher.Size = 1

	err := consumer.Run(ctx, tenancy.NewSingleTenant(), message)
	r.NoError(err, "message handling doesn't err")
}

func assertPolicyCalls(t *testing.T, checker *policy.CheckerMock, called bool) {
	if !called {
		checker.AssertNotCalled(t, "BatchCheckNotifyPolicy")
	}
}

// getMobileLayout constructs an empty layout data with the expected typeUrl
func getMobileLayout(t *testing.T) *pbany.Any {
	t.Helper()

	return &pbany.Any{TypeUrl: basicMobile.TypeURL, Value: nil}
}

func getEmailLayout(t *testing.T) *pbany.Any {
	t.Helper()

	return &pbany.Any{TypeUrl: basicEmail.TypeURL, Value: nil}
}

func getRendering(t *testing.T) *schema_pb_v0.Notify_Rendering {
	t.Helper()

	return &schema_pb_v0.Notify_Rendering{Mobile: getMobileLayout(t), Email: getEmailLayout(t)}
}

func getTracking(t *testing.T, now time.Time) *entities_pb.Tracking {
	t.Helper()

	return &entities_pb.Tracking{
		TriggeredAt: timestamppb.New(now),
	}
}

func getSkipSAMLEnforcement(t *testing.T) *entities_pb.SamlEnforcement {
	t.Helper()

	return &entities_pb.SamlEnforcement{SkipEnforcement: true}
}

func getContext(t *testing.T) *schema_pb_v0.Notify_Context {
	t.Helper()

	return &schema_pb_v0.Notify_Context{
		RepositoryId: &wrappers.Int64Value{Value: 1},
		Trigger:      "create",
		OwnerId:      &wrappers.Int64Value{Value: 1},
		OwnerType:    schema_pb_v0.Notify_Context_OwnerType(notify.OwnerTypeUser),
	}
}

func getMatchData(t *testing.T, msg *schema_pb_v0.Notify) *structpb.Struct {
	t.Helper()

	anypb, err := notify.ExtractArbitraryMatchDataFromMessage(msg)
	require.NoError(t, err)

	var res structpb.Struct
	err = proto.Unmarshal(anypb.GetValue(), &res)
	require.NoError(t, err)

	return &res
}

// Transform a collection of proto.Messages into bytes
// Comparing bytes send in the wire is easier that comparing complex structs
func asBytes[T proto.Message](t *testing.T, messages []T) [][]byte {
	t.Helper()
	output := make([][]byte, len(messages))

	for idx, msg := range messages {
		bytes, err := proto.Marshal(msg)
		require.NoError(t, err)
		output[idx] = bytes
	}

	return output
}
