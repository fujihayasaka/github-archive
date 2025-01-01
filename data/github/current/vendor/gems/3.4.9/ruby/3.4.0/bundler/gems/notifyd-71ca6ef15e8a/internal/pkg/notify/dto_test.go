package notify

import (
	"testing"

	"github.com/stretchr/testify/require"

	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/structpb"
	wrappers "google.golang.org/protobuf/types/known/wrapperspb"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
)

func Test_DeliveryMetadata(t *testing.T) {
	r := require.New(t)

	t.Run("If channel is missing in delivery metadata results, it doesn't break", func(t *testing.T) {
		d := DeliveryMetadata{
			Channels: map[string]*dto.Channel{"EMAIL": {Channel: "EMAIL", Enabled: false}},
		}
		r.Nil(d.Channels["PUSH"])
	})
}

func Test_ExtractArbitraryMatchDataFromMessage(t *testing.T) {
	tests := []struct {
		name              string
		notifyMessage     *schema_pb.Notify
		expectedMatchData map[string]interface{}
	}{
		{
			name: "All match data is present",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context:        getContext(t),
				Subject:        &schema_pb.Notify_Subject{Type: "IssueComment", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
				Attributes: []*schema_pb.Notify_Attribute{
					{Name: "watch_activity", Value: "true"},
				},
			},
			expectedMatchData: map[string]interface{}{
				"subject_type": "IssueComment",
				"trigger":      "create",
				"topics": []interface{}{
					map[string]interface{}{"type": "repository", "value": "123"},
				},
				"attributes": []interface{}{
					map[string]interface{}{"name": "watch_activity", "value": "true"},
				},
			},
		},
		{
			name: "Attributes are missing",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context:        getContext(t),
				Subject:        &schema_pb.Notify_Subject{Type: "IssueComment", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			expectedMatchData: map[string]interface{}{
				"subject_type": "IssueComment",
				"trigger":      "create",
				"topics": []interface{}{
					map[string]interface{}{"type": "repository", "value": "123"},
				},
			},
		},
		{
			name: "Topics are missing",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context:        getContext(t),
				Subject:        &schema_pb.Notify_Subject{Type: "IssueComment", Value: "1"},
				Attributes: []*schema_pb.Notify_Attribute{
					{Name: "watch_activity", Value: "true"},
				},
			},
			expectedMatchData: map[string]interface{}{
				"subject_type": "IssueComment",
				"trigger":      "create",
				"attributes": []interface{}{
					map[string]interface{}{"name": "watch_activity", "value": "true"},
				},
			},
		},
	}

	r := require.New(t)

	for _, test := range tests {
		expectedMatchDataStruct, err := structpb.NewStruct(test.expectedMatchData)
		r.NoError(err)

		actualMatchData, err := ExtractArbitraryMatchDataFromMessage(test.notifyMessage)
		r.NoError(err)
		var actualMatchDataStruct structpb.Struct

		err = proto.Unmarshal(actualMatchData.GetValue(), &actualMatchDataStruct)
		r.NoError(err)
		r.Equal(expectedMatchDataStruct.Fields, actualMatchDataStruct.Fields)
	}
}

func getContext(t *testing.T) *schema_pb.Notify_Context {
	t.Helper()

	return &schema_pb.Notify_Context{
		RepositoryId: &wrappers.Int64Value{Value: int64(1)},
		Trigger:      "create",
	}
}
