# frozen_string_literal: true
require "test_helper"

class GraphQLProAblySubscriptionsTest < Minitest::Test
  REDIS = Redis::Namespace.new(:ably, redis: Redis.new(db: REDIS_NUMBERS[:ably]))
  class MockAbly
    attr_reader :channels

    class Channel
      attr_reader :id, :key, :occupants

      def initialize(id, key)
        @id = id
        @key = key
        @occupants = 0
        @inboxes = [[]]
      end

      def publish(message_object, options)
        if message_object.name != "update"
          raise "Invariant: GraphQL is only expected to call update, but received #{event_name.inspect}. Fix tests or implementation."
        end
        @inboxes.each do |inbox|
          inbox << message_object.data
        end
        nil
      end

      # Mock Ably REST API
      def presence
        OpenStruct.new(
          get: OpenStruct.new(
            items: @occupants.times.map { self }
          )
        )
      end

      def occupied?
        @occupants > 0
      end

      def occupant_entered
        @occupants += 1
      end

      def occupant_left
        @occupants -= 1
      end

      def new_inbox
        inbox = []
        @inboxes << inbox
        inbox
      end

      def updates
        @inboxes[0]
      end
    end

    def initialize
      @channels = {}
    end

    def channel(channel_name, cipher: {})
      key = cipher[:key]
      @channels["#{channel_name}#{key}"] ||= Channel.new(channel_name, key)
    end

    def options
      {
        key: "app.abcdef:123",
      }
    end
  end

  MOCK_ABLY = MockAbly.new

  class EncryptedAblyTestSchema < GraphQL::Schema
    query(SubscriptionsAssertions::Types::Query)
    mutation(SubscriptionsAssertions::Types::Mutation)
    subscription(SubscriptionsAssertions::Types::Subscription)

    use GraphQL::Pro::AblySubscriptions,
      redis: REDIS, ably: MOCK_ABLY, cipher_base: "abcdefghij",
      broadcast: true, default_broadcastable: true
  end

  def setup
    REDIS.redis.script("flush")
    REDIS.redis.flushdb
    MOCK_ABLY.channels.clear
    @database = REDIS
    @transport = MOCK_ABLY
    @subscription_arguments = [
      GraphQL::Pro::AblySubscriptions,
      {
        redis: REDIS,
        ably: MOCK_ABLY,
        broadcast: true,
        default_broadcastable: true,
      }
    ]
    super
  end

  def unsubscribe_env(subscription_id, event_name: "channel.closed")
    data = { "items" => [{ "name" => event_name, "data" => { "channelId" => subscription_id } }] }
    if event_name == "presence.message"
      data["items"][0]["data"]["presence"] = [{
        "action" => 3
      }]
    end
    body = JSON.dump(data)
    binary_digest = OpenSSL::HMAC.digest("SHA256", "123", body)
    signature = Base64.encode64(binary_digest).strip
    {
      "HTTP_X_ABLY_SIGNATURE" => signature,
      "HTTP_X_ABLY_KEY" => "abcdef",
      "rack.input" => StringIO.new(body)
    }
  end

  include SubscriptionsAssertions

  def test_it_applies_encryption_when_cipher_base_is_present
    # Run a subscription & update without encryption
    res1 = exec("subscription { newBuddy: buddyConnected { screenname } }")
    assert_nil res1.context[:ably_cipher_base64]
    channel1 = mark_online(res1)
    res = exec("mutation { connect(screenname: \"dhh\") { screenname } }")
    expected_mutation_result = { "data" => { "connect" => { "screenname" => "dhh" } } }
    assert_equal expected_mutation_result, res.to_h
    expected_first_update = {
      result: { "data" => { "newBuddy" => { "screenname" => "dhh" } } },
      more: true,
    }
    assert_equal [expected_first_update], channel1.updates
    refute res1.context[:subscription_id].start_with?("ablyencr-"), "It doesn't add a prefix for plaintext"

    # Then subscribe _with_ encryption
    res2 = EncryptedAblyTestSchema.execute("subscription { newBuddy: buddyConnected { screenname } }")
    res2_sub_id = res2.context[:subscription_id]
    assert res2_sub_id.start_with?("ablyencr-"), "It adds a prefix when encrypting"
    expected_cipher = Digest::SHA256.base64digest("abcdefghij" + res2_sub_id)
    assert_equal expected_cipher, res2.context[:ably_cipher_base64]
    channel2 = mark_online(res2)
    EncryptedAblyTestSchema.execute("mutation { connect(screenname: \"matz\") { screenname } }")
    expected_second_update = {
      result: { "data" => { "newBuddy" => { "screenname" => "matz" } } },
      more: true,
    }

    # Make sure the old subscription got an unencrypted update
    assert_equal [expected_first_update, expected_second_update], channel1.updates
    assert_equal [expected_second_update], channel2.updates

    assert_equal expected_cipher, channel2.key
    assert_nil channel1.key
    assert_equal 2, MOCK_ABLY.channels.size
  end

  def test_it_unsubscribes_from_channel_event_webhooks
    res1 = exec("subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel1 = mark_online(res1)

    res2 = exec("subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel2 = mark_online(res2)

    res3 = exec("subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel3 = mark_online(res3)

    assert_equal channel1.id, channel3.id

    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)
    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)
    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)
    unsubscribe_via_webhook(channel2.id, event_name: "channel.closed")
    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)

    assert_equal [counter_update(1), counter_update(2), counter_update(3)], channel3.updates
    assert_equal [], @database.keys("*")
  end

  def test_it_unsubscribes_from_presence_events_also
    res1 = exec("subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel1 = mark_online(res1)

    res2 = exec("subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel2 = mark_online(res2)

    res3 = exec("subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel3 = mark_online(res3)

    assert_equal channel1.id, channel3.id

    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)
    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)
    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)
    channel2.occupant_left
    channel2.occupant_left
    channel2.occupant_left
    unsubscribe_via_webhook(channel2.id, event_name: "presence.leave")
    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)

    assert_equal [counter_update(1), counter_update(2), counter_update(3)], channel3.updates
    assert_equal [], @database.keys("*")
  end

  def test_it_unsubscribes_from_presence_message_webhooks
    res1 = exec("subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel1 = mark_online(res1)
    res2 = exec("subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel2 = mark_online(res2)
    res3 = exec("subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel3 = mark_online(res3)

    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)
    channel3.occupant_left
    unsubscribe_via_webhook(channel1.id, event_name: "presence.message")
    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)
    channel3.occupant_left
    unsubscribe_via_webhook(channel2.id, event_name: "presence.message")

    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)
    channel3.occupant_left
    unsubscribe_via_webhook(channel2.id, event_name: "presence.message")

    # Goes nowhere:
    @schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)

    assert_equal [counter_update(1), counter_update(2), counter_update(3)], channel3.updates
    assert_equal [], @database.keys("*")
  end
end
