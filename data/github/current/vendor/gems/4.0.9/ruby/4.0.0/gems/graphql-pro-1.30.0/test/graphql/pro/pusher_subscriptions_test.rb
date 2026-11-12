# frozen_string_literal: true
require "test_helper"

class GraphQLProPusherSubscriptionsTest < Minitest::Test
  REDIS = Redis.new(db: REDIS_NUMBERS[:pusher])

  def setup
    REDIS.flushdb
    @database = REDIS
    @transport = MockPusher.new
    @subscription_arguments = [
      GraphQL::Pro::PusherSubscriptions,
      {
        redis: REDIS,
        pusher: @transport,
        broadcast: true,
        default_broadcastable: true
      }
    ]
    super
  end

  include SubscriptionsAssertions

  def unsubscribe_env(subscription_id)
    body = JSON.dump({ "events" => [{ "name" => "channel_vacated", "channel" => subscription_id }]})
    digest = OpenSSL::Digest::SHA256.new
    signature = OpenSSL::HMAC.hexdigest(digest, @schema.subscriptions.pusher.secret, body)
    {
      "HTTP_X_PUSHER_KEY" => @schema.subscriptions.pusher.key,
      "HTTP_X_PUSHER_SIGNATURE" => signature,
      "CONTENT_TYPE" => 'application/json',
      "rack.input" => StringIO.new(body),
    }
  end

  def test_compress_true_defaults_to_gzip
    res1 = exec("subscription { newBuddy: buddyConnected { screenname } }", context: { compress_pusher_payload: true })
    channel1 = mark_online(res1)

    res = exec("mutation { connect(screenname: \"dhh\") { screenname } }")
    expected_mutation_result = { "data" => { "connect" => { "screenname" => "dhh" } } }
    assert_equal expected_mutation_result, res.to_h
    expected_first_result = { "data" => { "newBuddy" => { "screenname" => "dhh" } } }
    expected_compressed_result = Base64.encode64(Zlib.gzip(JSON.dump(expected_first_result)))
    expected_first_update = {
      compressed_result: expected_compressed_result,
      more: true,
    }

    assert_equal [expected_first_update], channel1.updates
    compressed_result = channel1.updates.first[:compressed_result]
    # Make sure it unzips as expected
    first_result = JSON.load(Zlib.gunzip(Base64.decode64(compressed_result)))
    assert_equal expected_first_result, first_result
  end

  def test_compress_reduces_the_size_of_large_payloads
    large_result = {}
    100.times do |i|
      large_result["aaaaaaaaa#{i}"] = {
        "123": "abc",
        "456": "def",
      }
    end
    # 10x improvement!
    assert_equal 3991, JSON.dump(large_result).bytesize
    assert_equal 391, @schema.subscriptions.compress(large_result).bytesize
  end

  def test_compress_true_calls_compress_with_the_result
    res1 = exec("subscription { newBuddy: buddyConnected { screenname } }", context: { compress_pusher_payload: true })
    channel1 = mark_online(res1)
    res = nil

    compress_impl = ->(result) {
      "Compressed: #{result.inspect}"
    }

    @schema.subscriptions.stub(:compress, compress_impl) do
      res = exec("mutation { connect(screenname: \"dhh\") { screenname } }")
    end

    expected_first_result = { "data" => { "newBuddy" => { "screenname" => "dhh" } } }
    expected_first_update = {
      compressed_result: "Compressed: #{expected_first_result.inspect}",
      more: true,
    }

    assert_equal [expected_first_update], channel1.updates
  end

  def exec_query(schema, query_str, **opts)
    if GRAPHQL_FUTURE
      schema.execute_next(query_str, **opts)
    else
      schema.execute(query_str, **opts)
    end
  end

  def run_batch_setup_and_triggers(schema)
    # These match completely (query fingerprint, scope, args)
    res1 = exec_query(schema, "subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel1 = mark_online(res1)
    ibx1 = channel1.new_inbox
    schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)

    res2 = exec_query(schema, "subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel2 = mark_online(res2)
    ibx2 = channel2.new_inbox
    res3 = exec_query(schema, "subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    _channel3 = mark_online(res3)
    res4 = exec_query(schema, "subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    _channel4 = mark_online(res4)

    schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)

    res5 = exec_query(schema, "subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    _channel5 = mark_online(res5)
    res6 = exec_query(schema, "subscription { evalCounter(counterSuffix: 1) }", context: { counter_prefix: "1" })
    channel6 = mark_online(res6)
    ibx3 = channel6.new_inbox

    assert_equal channel1, channel6, "Broadcastable shares channels"

    schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 1)
    # No subscribers:
    schema.subscriptions.trigger(:eval_counter, {counter_suffix: 1}, {}, scope: 2)

    return ibx1, ibx2, ibx3
  end

  def test_it_sends_in_batches_by_default
    ibx1, ibx2, ibx3 = run_batch_setup_and_triggers(@schema)

    assert_equal 3, ibx1.size
    assert_equal 2, ibx2.size
    assert_equal 1, ibx3.size
    # One message sent each time to all subscribers
    assert_equal [1, 1, 1], @transport.batch_sizes
  end

  def test_it_doesnt_send_batches_when_batch_size_is_1
    sub_class, sub_kwargs = @subscription_arguments
    non_batch_schema = build_schema_from(sub_class, sub_kwargs.merge(batch_size: 1))
    ibx1, ibx2, ibx3 = run_batch_setup_and_triggers(non_batch_schema)

    assert_equal 3, ibx1.size
    assert_equal 2, ibx2.size
    assert_equal 1, ibx3.size
    assert_equal [], @transport.batch_sizes
  end
end
