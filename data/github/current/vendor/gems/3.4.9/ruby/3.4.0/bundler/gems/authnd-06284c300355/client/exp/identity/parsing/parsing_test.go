package parsing

import (
	"testing"
	"time"

	"github.com/github/authnd/client"
	"github.com/github/authnd/client/exp/identity"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/stretchr/testify/assert"
)

func TestNewAttrActorParser(t *testing.T) {
	tests := []struct {
		name      string
		input     []*pb.Attribute
		expectErr bool
	}{
		{
			name:      "valid attributes",
			input:     []*pb.Attribute{{Id: "key1", Value: pb.NewStringValue("value1")}},
			expectErr: false,
		},
		{
			name:      "empty attributes",
			input:     []*pb.Attribute{},
			expectErr: false,
		},
		{
			name:      "nil attributes",
			input:     nil,
			expectErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parser, err := newAttrActorParser(tt.input)
			if tt.expectErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, parser)
			}
		})
	}

	for _, tt := range tests {
		t.Run(tt.name+" with attrs as map", func(t *testing.T) {
			var attrs map[string]interface{}
			if tt.input != nil {
				attrs = make(map[string]interface{})
				for _, a := range tt.input {
					v, err := a.Value.Unwrap()
					assert.NoError(t, err)
					attrs[a.Id] = v
				}
			}

			parser, err := newAttrActorParser(attrs)
			if tt.expectErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, parser)
			}
		})
	}
}

func TestAttributeParsingHelperMethods(t *testing.T) {
	now := time.Now().UTC()
	attrs := []*pb.Attribute{
		{Id: "key1", Value: pb.NewInt64Value(42)},
		{Id: "key2", Value: pb.NewStringValue("string_value")},
		{Id: "key3", Value: pb.NewTimeValue(now)},
	}

	parser, _ := newAttrActorParser(attrs)

	t.Run("Test int64Attribute", func(t *testing.T) {
		val, present, err := parser.int64Attribute("key1")
		assert.NoError(t, err)
		assert.True(t, present)
		assert.Equal(t, int64(42), val)

		_, present, err = parser.int64Attribute("key4")
		assert.NoError(t, err)
		assert.False(t, present)
	})

	t.Run("Test stringAttribute", func(t *testing.T) {
		val, present, err := parser.stringAttribute("key2")
		assert.NoError(t, err)
		assert.True(t, present)
		assert.Equal(t, "string_value", val)

		_, present, err = parser.stringAttribute("key4")
		assert.NoError(t, err)
		assert.False(t, present)
	})

	t.Run("Test timeAttribute", func(t *testing.T) {
		// Test with a valid time value if applicable (could add a test for time parsing if implemented).
		val, present, err := parser.timeAttribute("key3")
		assert.NoError(t, err)
		assert.True(t, present)
		assert.Equal(t, now, val)

		_, present, err = parser.timeAttribute("key2")
		assert.Error(t, err)
		assert.EqualError(t, err, "invalid attribute type for key2, expected time.Time but got string")
	})

	t.Run("Test invalid attribute type", func(t *testing.T) {
		_, _, err := parser.int64Attribute("key2")
		assert.Error(t, err)
		assert.EqualError(t, err, "invalid attribute type for key2, expected int64 but got string")
	})
}

func TestActorMethodMissingAttrs(t *testing.T) {
	t.Run("Test error due to missing attribute", func(t *testing.T) {
		// Create an attribute map missing a required value
		attrsMissingType := []*pb.Attribute{
			{Id: client.ActorIDAttribute, Value: pb.NewInt64Value(int64(12345))},
			{Id: client.CredentialIDAttribute, Value: pb.NewInt64Value(int64(67890))},
		}
		parserMissingType, _ := newAttrActorParser(attrsMissingType)

		actor, err := parserMissingType.Actor()
		assert.Error(t, err)
		assert.Nil(t, actor)
		assert.EqualError(t, err, "missing required attribute actor.type")
	})
}

func TestParseBotActorFromAttrs(t *testing.T) {
	attrs := []*pb.Attribute{
		{Id: client.ActorIDAttribute, Value: pb.NewInt64Value(int64(12345))},
		{Id: client.ActorTypeAttribute, Value: pb.NewStringValue("Bot")},
		{Id: client.CredentialIDAttribute, Value: pb.NewInt64Value(int64(67890))},
		{Id: client.CredentialTypeAttribute, Value: pb.NewStringValue("server_to_server_token")},
		{Id: client.ApplicationIDAttribute, Value: pb.NewInt64Value(int64(111))},
		{Id: client.ApplicationOwnerIDAttribute, Value: pb.NewInt64Value(int64(222))},
		{Id: client.ApplicationOwnerTypeAttribute, Value: pb.NewStringValue("Organization")},
		{Id: client.InstallationIDAttribute, Value: pb.NewInt64Value(int64(333))},
		{Id: client.InstallationTargetIDAttribute, Value: pb.NewInt64Value(int64(444))},
		{Id: client.InstallationTargetTypeAttribute, Value: pb.NewStringValue("User")},
	}

	parser, _ := newAttrActorParser(attrs)

	t.Run("Test successful BotActor creation", func(t *testing.T) {
		botActor, err := parseBotActorFromAttrs(12345, identity.ActorTypeBot, parser)
		assert.NoError(t, err)
		assert.NotNil(t, botActor)
	})

	t.Run("Test error due to incorrect actor type", func(t *testing.T) {
		_, err := parseBotActorFromAttrs(12345, identity.ActorTypeUser, parser)
		assert.Error(t, err)
		assert.EqualError(t, err, "actor type is not a bot")
	})
}
